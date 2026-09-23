import Foundation

nonisolated enum TipTourMode: String, CaseIterable, Identifiable {
    case jev
    case gemini

    var id: String { rawValue }
    var title: String { self == .jev ? "JEV" : "Gemini" }
    var keyName: String { self == .jev ? "jevAPIKey" : "geminiAPIKey" }
    var shortcut: String { self == .jev ? "Ctrl+K" : "Ctrl+Option" }
    var systemImage: String { self == .jev ? "text.cursor" : "waveform" }
    var summary: String {
        self == .jev ? "Type a task, or hold Fn and say it. JEV finds and clicks screen controls."
            : "Talk naturally. Gemini can click, type, and guide you."
    }
    var privacySummary: String {
        self == .jev ? "Your task and detected screen labels go to TypeSafe, directly or through Vercel AI Gateway. Images and voice stay on your Mac."
            : "Your voice and optional screenshots go to Google."
    }

    static func restored(from value: String?) -> Self {
        value.flatMap(Self.init(rawValue:)) ?? .jev
    }

    func permissionsReady(desktop: Bool, microphone: Bool) -> Bool {
        desktop && (self == .jev || microphone)
    }
}
