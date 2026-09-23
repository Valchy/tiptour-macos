//
//  FunctionKeyPushToTalkShortcut.swift
//  TipTour
//
//  Pure logic for "hold Fn (globe) to talk to JEV". Kept free of AppKit and
//  event-tap plumbing so scripts/test-jev.sh can unit test it.
//
//  Why a hold threshold and cancellation: bare Fn is the first half of many
//  ordinary chords (Fn+Arrow for Home/End/Page Up/Down, Fn+Delete, the F-keys).
//  A press only counts as push-to-talk once Fn has been held on its own for a
//  moment, and any other key or modifier during the hold cancels it so those
//  chords keep working in the user's app.
//

import CoreGraphics

nonisolated enum FunctionKeyPushToTalkShortcut {
    /// kVK_Function. Some Apple keyboards report the globe key as 179.
    static let functionKeyCodes: Set<UInt16> = [63, 179]

    /// How long Fn must be held alone before listening starts.
    static let holdThresholdSeconds: Double = 0.25

    /// What CompanionManager is told.
    enum Transition: Equatable {
        case pressed
        case released
        case cancelled
    }

    /// A raw keyboard event, reduced to what the hold logic cares about.
    enum KeyActivity: Equatable {
        case functionKeyWentDown
        case functionKeyWentUp
        case otherKeyOrModifierActivity
        case irrelevant
    }

    /// NX_SYSDEFINED. Media and brightness keys (e.g. Fn+F12 with "Use F1, F2,
    /// etc. as standard function keys" on) arrive as these, not as keyDown.
    static let systemDefinedEventTypeRawValue: UInt32 = 14
    /// NX_SUBTYPE_AUX_CONTROL_BUTTONS: the media/brightness key subtype.
    static let auxiliaryControlButtonsSubtype: Int16 = 8

    /// Takes the raw event type because NX_SYSDEFINED has no CGEventType case.
    static func keyActivity(
        eventTypeRawValue: UInt32,
        keyCode: UInt16,
        modifierFlagsRawValue: UInt64,
        systemDefinedEventSubtype: Int16? = nil
    ) -> KeyActivity {
        let modifierFlags = CGEventFlags(rawValue: modifierFlagsRawValue)
        let otherModifierFlags: CGEventFlags = [.maskControl, .maskAlternate, .maskCommand, .maskShift]

        switch eventTypeRawValue {
        case CGEventType.flagsChanged.rawValue:
            // Only a flagsChanged for the Fn key itself changes the Fn state.
            // Arrow and F-keys carry maskSecondaryFn on keyDown even when Fn
            // is not physically held, so keyDown flags are never trusted here.
            guard functionKeyCodes.contains(keyCode) else {
                return .otherKeyOrModifierActivity
            }
            guard modifierFlags.contains(.maskSecondaryFn) else {
                return .functionKeyWentUp
            }
            if !modifierFlags.intersection(otherModifierFlags).isEmpty {
                return .otherKeyOrModifierActivity
            }
            return .functionKeyWentDown
        case CGEventType.keyDown.rawValue:
            return .otherKeyOrModifierActivity
        case systemDefinedEventTypeRawValue:
            return systemDefinedEventSubtype == auxiliaryControlButtonsSubtype
                ? .otherKeyOrModifierActivity
                : .irrelevant
        default:
            return .irrelevant
        }
    }

    /// What the event-tap monitor should do next.
    enum MonitorAction: Equatable {
        case none
        case startHoldCountdown
        case cancelHoldCountdown
        case publish(Transition)
    }

    /// Tracks one Fn hold at a time.
    struct HoldTracker {
        private(set) var isFunctionKeyDown = false
        private(set) var wasHoldInterruptedByOtherKey = false
        private(set) var isPushToTalkActive = false

        mutating func handle(_ keyActivity: KeyActivity) -> MonitorAction {
            switch keyActivity {
            case .functionKeyWentDown:
                guard !isFunctionKeyDown else { return .none }
                isFunctionKeyDown = true
                wasHoldInterruptedByOtherKey = false
                isPushToTalkActive = false
                return .startHoldCountdown

            case .functionKeyWentUp:
                guard isFunctionKeyDown else { return .none }
                isFunctionKeyDown = false
                if isPushToTalkActive {
                    isPushToTalkActive = false
                    return .publish(.released)
                }
                return .cancelHoldCountdown

            case .otherKeyOrModifierActivity:
                guard isFunctionKeyDown, !wasHoldInterruptedByOtherKey else { return .none }
                wasHoldInterruptedByOtherKey = true
                if isPushToTalkActive {
                    isPushToTalkActive = false
                    return .publish(.cancelled)
                }
                return .cancelHoldCountdown

            case .irrelevant:
                return .none
            }
        }

        /// Called when the hold countdown fires.
        mutating func holdCountdownFinished() -> MonitorAction {
            guard isFunctionKeyDown, !wasHoldInterruptedByOtherKey, !isPushToTalkActive else { return .none }
            isPushToTalkActive = true
            return .publish(.pressed)
        }

        /// Called when the monitor stops (e.g. Accessibility was revoked) so an
        /// active hold never leaves the microphone running.
        mutating func reset() -> MonitorAction {
            let wasPushToTalkActive = isPushToTalkActive
            isFunctionKeyDown = false
            wasHoldInterruptedByOtherKey = false
            isPushToTalkActive = false
            return wasPushToTalkActive ? .publish(.cancelled) : .cancelHoldCountdown
        }
    }
}
