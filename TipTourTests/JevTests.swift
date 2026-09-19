import Foundation
import Testing
@testable import TipTour

@MainActor
struct JevTests {
    @Test func targetContinuityAllowsJitterButRejectsDifferentControls() {
        func matches(_ box: [Double], label: String = "New Tab", source: String = "ocr",
                     display: [Double] = [0, 0, 1512, 982]) -> Bool {
            LocalTargetContinuity.matches(label: label, source: source, box: box, display: display,
                previousLabel: "New Tab", previousSource: "ocr", previousBox: [100, 50, 160, 65],
                previousDisplay: [0, 0, 1512, 982])
        }
        #expect(matches([101, 49, 161, 66]))
        #expect(!matches([500, 50, 560, 65]))
        #expect(!matches([100, 50, 160, 65], label: "Close Tab"))
        #expect(!matches([100, 50, 160, 65], display: [1512, 0, 1512, 982]))
        #expect(!matches([100, 50, 160, 65], source: "yolo"))
        #expect(!matches([100, 50]))
    }

    private let metrics = JevCallMetrics(milliseconds: 1, inputTokens: 100, model: "jev-latest")
    private func candidate(_ id: String = "save", label: String = "Save") -> JevCandidate {
        JevCandidate(id: id, label: label, source: "ocr", confidence: 1, centre: .zero)
    }
    private func answers(choice: String = "save", absent: Double = 0.1,
                         probability: Double = 0.9, kind: String = "click") throws -> [String: JevAnswer] {
        let data = try JSONSerialization.data(withJSONObject: [
            "pick": ["choice": choice, "probabilities": [choice: probability]],
            "done": ["noul": 0.1], "absent": ["noul": absent], "kind": ["choice": kind]
        ])
        return try JSONDecoder().decode([String: JevAnswer].self, from: data)
    }

    @Test func defaultModeIsJevAndSavedChoiceIsRespected() {
        #expect(TipTourMode.restored(from: nil) == .jev)
        #expect(TipTourMode.restored(from: "obsolete-provider") == .jev)
        #expect(TipTourMode.restored(from: "gemini") == .gemini)
        #expect(TipTourMode.restored(from: "jev") == .jev)
    }

    @Test func microphoneIsRequiredOnlyForGemini() {
        #expect(TipTourMode.jev.permissionsReady(desktop: true, microphone: false))
        #expect(!TipTourMode.gemini.permissionsReady(desktop: true, microphone: false))
        #expect(TipTourMode.gemini.permissionsReady(desktop: true, microphone: true))
        #expect(!TipTourMode.jev.permissionsReady(desktop: false, microphone: true))
    }

    @Test func selectedModeUsesItsOwnKeyAndShortcut() {
        #expect(TipTourMode.jev.keyName == "jevAPIKey")
        #expect(TipTourMode.gemini.keyName == "geminiAPIKey")
        #expect(TipTourMode.jev.shortcut == "Ctrl+K")
        #expect(TipTourMode.gemini.shortcut == "Ctrl+Option")
    }

    @Test func requestsStayUnderAPILimitAndKeepNoneOption() {
        let candidates = (0..<300).map { candidate("id-\($0)", label: "Button \($0)") }
        let request = JevGrounding.request(task: "Save", candidates: candidates, history: [], excluding: [])
        #expect(request?.pool.count == 200)
        if case let .choice(_, criteria) = request?.questions["pick"] {
            #expect(criteria.count == 201)
            #expect(criteria[JevGrounding.noneKey] != nil)
        } else { Issue.record("Missing bounded choice question") }
    }

    @Test func duplicateAndReservedIDsCannotCrashCandidateDictionary() {
        let request = JevGrounding.request(task: "Save", candidates: [
            candidate(), candidate(label: "Different label"), candidate("__none__"), candidate("")
        ], history: [], excluding: [])
        #expect(request?.pool.count == 1)
    }

    @Test func noneChoiceStopsInsteadOfClickingRunnerUp() throws {
        var payload = try answers(choice: "__none__")
        payload["pick"] = try JSONDecoder().decode(JevAnswer.self, from: Data(
            #"{"choice":"__none__","probabilities":{"__none__":0.9,"save":0.1}}"#.utf8))
        let result = try JevGrounding.decision(from: payload, pool: [candidate()], metrics: metrics)
        #expect(result.best?.candidate.id == "save")
        #expect(result.stopReason == "target_absent")
    }

    @Test func topTargetIsAllowedRegardlessOfAbsentScoreOrProbability() throws {
        let absent = try JevGrounding.decision(from: answers(absent: 0.9), pool: [candidate()], metrics: metrics)
        let weak = try JevGrounding.decision(from: answers(probability: 0.2), pool: [candidate()], metrics: metrics)
        #expect(absent.stopReason == nil)
        #expect(absent.best?.candidate.id == "save")
        #expect(weak.stopReason == nil)
        #expect(weak.best?.candidate.id == "save")
    }

    @Test func inventedTargetOrActionAndIncompleteResponsesAreRejected() throws {
        #expect(throws: JevError.self) {
            try JevGrounding.decision(from: answers(choice: "invented"), pool: [candidate()], metrics: metrics)
        }
        #expect(throws: JevError.self) {
            try JevGrounding.decision(from: answers(kind: "type"), pool: [candidate()], metrics: metrics)
        }
        #expect(throws: JevError.self) {
            try JevGrounding.decision(from: [:], pool: [candidate()], metrics: metrics)
        }
    }

    @Test func validClickUsesSuppliedTarget() throws {
        let decision = try JevGrounding.decision(from: answers(), pool: [candidate()], metrics: metrics)
        #expect(decision.best?.candidate.id == "save")
        #expect(decision.actionKind == "click")
        #expect(decision.stopReason == nil)
    }

    @Test func roundedTieHonorsTheSelectedOption() throws {
        var payload = try answers()
        payload["pick"] = try JSONDecoder().decode(JevAnswer.self, from: Data(
            #"{"choice":"save","probabilities":{"cancel":0.5,"save":0.5}}"#.utf8))
        let result = try JevGrounding.decision(from: payload,
            pool: [candidate(), candidate("cancel", label: "Cancel")], metrics: metrics)
        #expect(result.best?.candidate.id == "save")
    }

    @Test func missingKeyFailsBeforeNetworkRequest() async {
        let client = JevClient(apiKeyProvider: { nil })
        await #expect(throws: JevError.self) {
            try await client.ask(state: [:], questions: [:])
        }
    }
}
