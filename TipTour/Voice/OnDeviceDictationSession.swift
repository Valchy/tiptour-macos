//
//  OnDeviceDictationSession.swift
//  TipTour
//
//  One "hold Fn and say the JEV task" recording. Speech is transcribed by
//  Apple's on-device recognizer only (requiresOnDeviceRecognition), so no
//  audio leaves the Mac; the resulting text becomes an ordinary JEV task.
//
//  This is deliberately separate from GeminiLiveSession: Gemini streams audio
//  to a realtime model, while JEV only ever receives text.
//

import AVFoundation
import Foundation
import Speech

@MainActor
final class OnDeviceDictationSession {
    enum PermissionState {
        case authorized
        case notDetermined
        case denied
    }

    enum DictationError: LocalizedError {
        case speechRecognizerUnavailable
        case onDeviceRecognitionUnavailable(languageName: String)
        case microphoneInputUnavailable

        var errorDescription: String? {
            switch self {
            case .speechRecognizerUnavailable:
                return "Speech recognition isn't available right now"
            case let .onDeviceRecognitionUnavailable(languageName):
                return "On-device speech for \(languageName) isn't installed. Turn on Dictation in System Settings → Keyboard"
            case .microphoneInputUnavailable:
                return "No microphone input found"
            }
        }
    }

    /// Called on the main actor with the best transcript so far.
    var onLiveTranscriptChanged: ((String) -> Void)?

    private(set) var latestTranscript = ""

    private var audioEngine: AVAudioEngine?
    /// Held for the whole recording so the recognizer outlives its task.
    private var speechRecognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var hasRecognitionEnded = false
    private var hasStartedFinishing = false
    private var finalResultContinuation: CheckedContinuation<Void, Never>?

    // MARK: - Permissions

    static func currentPermissionState() -> PermissionState {
        let microphoneAuthorizationStatus = AVCaptureDevice.authorizationStatus(for: .audio)
        let speechAuthorizationStatus = SFSpeechRecognizer.authorizationStatus()

        if microphoneAuthorizationStatus == .authorized && speechAuthorizationStatus == .authorized {
            return .authorized
        }
        if microphoneAuthorizationStatus == .denied || microphoneAuthorizationStatus == .restricted
            || speechAuthorizationStatus == .denied || speechAuthorizationStatus == .restricted {
            return .denied
        }
        return .notDetermined
    }

    /// Shows the macOS Microphone and Speech Recognition prompts for whichever
    /// is still undecided. Returns true only if both end up authorized.
    static func requestPermissions() async -> Bool {
        if AVCaptureDevice.authorizationStatus(for: .audio) == .notDetermined {
            _ = await AVCaptureDevice.requestAccess(for: .audio)
        }
        if SFSpeechRecognizer.authorizationStatus() == .notDetermined {
            _ = await requestSpeechRecognitionAuthorization()
        }
        return currentPermissionState() == .authorized
    }

    /// Nonisolated so the callback, which arrives on an arbitrary queue, is
    /// not treated as main-actor code.
    nonisolated private static func requestSpeechRecognitionAuthorization() async -> SFSpeechRecognizerAuthorizationStatus {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { authorizationStatus in
                continuation.resume(returning: authorizationStatus)
            }
        }
    }

    // MARK: - Recording

    func start() throws {
        let speechRecognizer = SFSpeechRecognizer(locale: Locale.current)
            ?? SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
        guard let speechRecognizer, speechRecognizer.isAvailable else {
            throw DictationError.speechRecognizerUnavailable
        }
        // Never fall back to Apple's servers: the promise is that voice stays
        // on this Mac.
        guard speechRecognizer.supportsOnDeviceRecognition else {
            let languageName = Locale.current.localizedString(forIdentifier: speechRecognizer.locale.identifier)
                ?? speechRecognizer.locale.identifier
            throw DictationError.onDeviceRecognitionUnavailable(languageName: languageName)
        }

        let recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        recognitionRequest.shouldReportPartialResults = true
        recognitionRequest.requiresOnDeviceRecognition = true
        recognitionRequest.taskHint = .dictation

        // A fresh engine per recording picks up the current input device
        // (e.g. AirPods connected since the last hold), like GeminiLiveSession.
        let audioEngine = AVAudioEngine()
        let inputNode = audioEngine.inputNode
        let inputFormat = inputNode.inputFormat(forBus: 0)
        guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0 else {
            throw DictationError.microphoneInputUnavailable
        }
        inputNode.installTap(
            onBus: 0,
            bufferSize: 1024,
            format: inputFormat,
            block: Self.makeMicrophoneTapBlock(appendingTo: recognitionRequest)
        )
        audioEngine.prepare()
        do {
            try audioEngine.start()
        } catch {
            inputNode.removeTap(onBus: 0)
            throw error
        }

        self.audioEngine = audioEngine
        self.speechRecognizer = speechRecognizer
        self.recognitionRequest = recognitionRequest
        latestTranscript = ""
        hasRecognitionEnded = false
        recognitionTask = speechRecognizer.recognitionTask(
            with: recognitionRequest,
            resultHandler: Self.makeRecognitionResultHandler(for: self)
        )
    }

    /// Stops the microphone and waits briefly for the recognizer's final
    /// result. Falls back to the latest partial transcript if the final one
    /// doesn't arrive in time (e.g. the user said nothing).
    func finish(finalResultTimeoutSeconds: Double = 1.5) async -> String {
        // A second call while the first is still waiting must not replace
        // (and so leak) the first call's continuation.
        guard !hasStartedFinishing else {
            return latestTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        hasStartedFinishing = true
        stopMicrophoneCapture()
        recognitionRequest?.endAudio()

        if !hasRecognitionEnded && recognitionTask != nil {
            await withCheckedContinuation { continuation in
                finalResultContinuation = continuation
                DispatchQueue.main.asyncAfter(deadline: .now() + finalResultTimeoutSeconds) { [weak self] in
                    self?.resumeFinalResultWaiterIfNeeded()
                }
            }
        }

        let finalTranscript = latestTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        tearDownRecognition()
        return finalTranscript
    }

    func cancel() {
        stopMicrophoneCapture()
        tearDownRecognition()
    }

    // MARK: - Private

    private func handleRecognitionUpdate(transcript: String?, hasEnded: Bool) {
        if let transcript, !transcript.isEmpty {
            latestTranscript = transcript
            onLiveTranscriptChanged?(transcript)
        }
        if hasEnded {
            hasRecognitionEnded = true
            resumeFinalResultWaiterIfNeeded()
        }
    }

    private func resumeFinalResultWaiterIfNeeded() {
        guard let finalResultContinuation else { return }
        self.finalResultContinuation = nil
        finalResultContinuation.resume()
    }

    private func stopMicrophoneCapture() {
        guard let audioEngine else { return }
        audioEngine.inputNode.removeTap(onBus: 0)
        audioEngine.stop()
        self.audioEngine = nil
    }

    private func tearDownRecognition() {
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil
        speechRecognizer = nil
        onLiveTranscriptChanged = nil
        resumeFinalResultWaiterIfNeeded()
    }

    /// Runs on Core Audio's real-time thread, so it only hands buffers to the
    /// request (append is thread-safe) and never touches the main actor.
    nonisolated private static func makeMicrophoneTapBlock(
        appendingTo recognitionRequest: SFSpeechAudioBufferRecognitionRequest
    ) -> AVAudioNodeTapBlock {
        { buffer, _ in
            recognitionRequest.append(buffer)
        }
    }

    /// The recognizer calls back on its own queue; hop to the main actor with
    /// plain values only.
    nonisolated private static func makeRecognitionResultHandler(
        for dictationSession: OnDeviceDictationSession
    ) -> (SFSpeechRecognitionResult?, Error?) -> Void {
        { [weak dictationSession] result, error in
            let transcript = result?.bestTranscription.formattedString
            let hasEnded = (result?.isFinal ?? false) || error != nil
            Task { @MainActor [dictationSession] in
                dictationSession?.handleRecognitionUpdate(transcript: transcript, hasEnded: hasEnded)
            }
        }
    }
}
