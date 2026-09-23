//
//  GlobalFunctionKeyPushToTalkMonitor.swift
//  TipTour
//
//  Watches the Fn (globe) key system-wide for JEV's "hold Fn and say the
//  task" gesture. Same listen-only CGEvent tap approach as
//  GlobalPushToTalkShortcutMonitor, but a separate instance on purpose: that
//  one drives Gemini and the overlay's push-to-talk trail, and Fn needs a hold
//  threshold plus a cancelled state (see FunctionKeyPushToTalkShortcut).
//

import AppKit
import Combine
import CoreGraphics
import Foundation

final class GlobalFunctionKeyPushToTalkMonitor: ObservableObject {
    let transitionPublisher = PassthroughSubject<FunctionKeyPushToTalkShortcut.Transition, Never>()

    private var globalEventTap: CFMachPort?
    private var globalEventTapRunLoopSource: CFRunLoopSource?
    /// Mutated only from the event tap callback and the hold countdown, both of
    /// which run on the main run loop.
    private var holdTracker = FunctionKeyPushToTalkShortcut.HoldTracker()
    private var pendingHoldCountdown: DispatchWorkItem?

    deinit {
        stop()
    }

    func start() {
        // The permission poller calls start() every 1.5s. Restarting would
        // reset the hold tracker in the middle of a hold, so only start once.
        guard globalEventTap == nil else { return }

        let monitoredEventTypeRawValues: [UInt32] = [
            CGEventType.flagsChanged.rawValue,
            CGEventType.keyDown.rawValue,
            CGEventType.keyUp.rawValue,
            // Media/brightness keys during a hold must cancel it too.
            FunctionKeyPushToTalkShortcut.systemDefinedEventTypeRawValue
        ]
        let eventMask = monitoredEventTypeRawValues.reduce(CGEventMask(0)) { currentMask, eventTypeRawValue in
            currentMask | (CGEventMask(1) << eventTypeRawValue)
        }

        let eventTapCallback: CGEventTapCallBack = { _, eventType, event, userInfo in
            guard let userInfo else {
                return Unmanaged.passUnretained(event)
            }

            let globalFunctionKeyPushToTalkMonitor = Unmanaged<GlobalFunctionKeyPushToTalkMonitor>
                .fromOpaque(userInfo)
                .takeUnretainedValue()

            return globalFunctionKeyPushToTalkMonitor.handleGlobalEventTap(
                eventType: eventType,
                event: event
            )
        }

        guard let globalEventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: eventMask,
            callback: eventTapCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            print("⚠️ Fn push-to-talk: couldn't create CGEvent tap")
            return
        }

        guard let globalEventTapRunLoopSource = CFMachPortCreateRunLoopSource(
            kCFAllocatorDefault,
            globalEventTap,
            0
        ) else {
            CFMachPortInvalidate(globalEventTap)
            print("⚠️ Fn push-to-talk: couldn't create event tap run loop source")
            return
        }

        self.globalEventTap = globalEventTap
        self.globalEventTapRunLoopSource = globalEventTapRunLoopSource

        CFRunLoopAddSource(CFRunLoopGetMain(), globalEventTapRunLoopSource, .commonModes)
        CGEvent.tapEnable(tap: globalEventTap, enable: true)
    }

    func stop() {
        perform(holdTracker.reset())

        if let globalEventTapRunLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), globalEventTapRunLoopSource, .commonModes)
            self.globalEventTapRunLoopSource = nil
        }

        if let globalEventTap {
            CFMachPortInvalidate(globalEventTap)
            self.globalEventTap = nil
        }
    }

    private func handleGlobalEventTap(
        eventType: CGEventType,
        event: CGEvent
    ) -> Unmanaged<CGEvent>? {
        if eventType == .tapDisabledByTimeout || eventType == .tapDisabledByUserInput {
            if let globalEventTap {
                CGEvent.tapEnable(tap: globalEventTap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }

        let isSystemDefinedEvent = eventType.rawValue == FunctionKeyPushToTalkShortcut.systemDefinedEventTypeRawValue
        let keyActivity = FunctionKeyPushToTalkShortcut.keyActivity(
            eventTypeRawValue: eventType.rawValue,
            keyCode: UInt16(event.getIntegerValueField(.keyboardEventKeycode)),
            modifierFlagsRawValue: event.flags.rawValue,
            systemDefinedEventSubtype: isSystemDefinedEvent ? NSEvent(cgEvent: event)?.subtype.rawValue : nil
        )
        perform(holdTracker.handle(keyActivity))

        return Unmanaged.passUnretained(event)
    }

    private func perform(_ monitorAction: FunctionKeyPushToTalkShortcut.MonitorAction) {
        switch monitorAction {
        case .none:
            break
        case .startHoldCountdown:
            pendingHoldCountdown?.cancel()
            let holdCountdown = DispatchWorkItem { [weak self] in
                guard let self else { return }
                self.pendingHoldCountdown = nil
                self.perform(self.holdTracker.holdCountdownFinished())
            }
            pendingHoldCountdown = holdCountdown
            DispatchQueue.main.asyncAfter(
                deadline: .now() + FunctionKeyPushToTalkShortcut.holdThresholdSeconds,
                execute: holdCountdown
            )
        case .cancelHoldCountdown:
            pendingHoldCountdown?.cancel()
            pendingHoldCountdown = nil
        case .publish(let transition):
            pendingHoldCountdown?.cancel()
            pendingHoldCountdown = nil
            transitionPublisher.send(transition)
        }
    }
}
