//  JevStepPanelView.swift
//  The decision, drawn under the Ctrl+K input while the loop runs.
//
//  The panel is a fixed-width floating NSPanel (340pt, 13pt side padding), so
//  there is no GeometryReader here — usable content width is a constant. Bars
//  are sized by an explicit frame, matching MiniAudioGlyph's approach in
//  OverlayWindow.swift rather than introducing a new layout idiom.

import SwiftUI

struct JevStepPanelView: View {
    let snapshot: JevStepSnapshot

    static let contentWidth: CGFloat = 314
    private static let barRowHeight: CGFloat = 15
    private static let barTrackWidth: CGFloat = 150

    /// How much height the results area needs, so the window can grow to match.
    static func height(for snapshot: JevStepSnapshot) -> CGFloat {
        let header: CGFloat = 13
        let gauges: CGFloat = 13
        let bars = CGFloat(snapshot.bars.count) * barRowHeight
        let note: CGFloat = snapshot.note.isEmpty ? 0 : 14
        let gapCount = 2 + snapshot.bars.count + (snapshot.note.isEmpty ? 0 : 1)
        let spacing = CGFloat(gapCount) * 5
        // Include the gap between this view and the command status row.
        return 8 + 1 + header + gauges + bars + note + spacing
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Divider().overlay(DS.Colors.borderSubtle.opacity(0.5)).frame(height: 1)

            HStack(spacing: 6) {
                Text("step \(snapshot.step)")
                    .foregroundColor(DS.Colors.textSecondary)
                Text("· \(snapshot.detected) detected")
                    .foregroundColor(DS.Colors.textTertiary)
                Spacer()
                if snapshot.milliseconds > 0 {
                    Text("\(snapshot.milliseconds)ms")
                        .foregroundColor(DS.Colors.textTertiary)
                }
                Text("\(snapshot.inputTokens) tokens")
                    .foregroundColor(DS.Colors.textTertiary)
            }
            .font(.system(size: 9, weight: .medium, design: .monospaced))
            .frame(height: 13)

            HStack(spacing: 12) {
                gauge("done", snapshot.done, DS.Colors.success)
                gauge("absent", snapshot.absent, DS.Colors.warning)
            }
            .frame(height: 13)

            ForEach(snapshot.bars) { bar in
                HStack(spacing: 6) {
                    Text(bar.label)
                        .font(.system(size: 10, weight: bar.isChosen ? .semibold : .regular))
                        .foregroundColor(bar.isChosen ? DS.Colors.textPrimary : DS.Colors.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(width: 118, alignment: .leading)

                    ZStack(alignment: .leading) {
                        Capsule(style: .continuous)
                            .fill(Color.white.opacity(0.05))
                            .frame(width: Self.barTrackWidth, height: 5)
                        Capsule(style: .continuous)
                            .fill(bar.isChosen ? DS.Colors.accentText : DS.Colors.accent.opacity(0.55))
                            .frame(width: max(2, Self.barTrackWidth * bar.probability), height: 5)
                    }

                    Text(String(format: "%.2f", bar.probability))
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundColor(bar.isChosen ? DS.Colors.textPrimary : DS.Colors.textTertiary)
                }
                .frame(height: Self.barRowHeight, alignment: .center)
            }

            if !snapshot.note.isEmpty {
                Text(snapshot.note)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(DS.Colors.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(height: 14)
                    .help(snapshot.note)
            }
        }
        .frame(width: Self.contentWidth, alignment: .leading)
        .animation(.easeInOut(duration: 0.16), value: snapshot)
    }

    private func gauge(_ title: String, _ value: Double, _ tint: Color) -> some View {
        HStack(spacing: 5) {
            Text(title)
                .font(.system(size: 9, weight: .medium))
                .foregroundColor(DS.Colors.textTertiary)
            ZStack(alignment: .leading) {
                Capsule(style: .continuous)
                    .fill(Color.white.opacity(0.05))
                    .frame(width: 64, height: 4)
                Capsule(style: .continuous)
                    .fill(tint.opacity(0.9))
                    .frame(width: max(2, 64 * value), height: 4)
            }
            Text(String(format: "%.2f", value))
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundColor(DS.Colors.textSecondary)
        }
    }
}
