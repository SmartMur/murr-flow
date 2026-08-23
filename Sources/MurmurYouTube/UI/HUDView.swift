import SwiftUI

/// The floating pill that appears while you dictate.
///
/// Spec (Whispr Flow-matched):
///   – 386 × 76 pt, cornerRadius 16, `.regularMaterial` + windowBackgroundColor tint
///   – 1 pt border at 14 % white opacity
///   – Drop shadow: radius 22, y-offset 8, black 22 %
///   – Left: 32-bar VU meter (2.5 pt wide, 2 pt gap, wave-animated, level-coloured)
///   – Right: live transcript or state label in Figtree Medium 13 pt
struct HUDView: View {
    @Bindable var controller: DictationController

    var body: some View {
        HStack(spacing: 0) {
            // VU meter
            VUMeter(level: controller.level, isActive: controller.state == .listening)
                .frame(width: MF.Pill.vuWidth, height: MF.Pill.height - 28)
                .padding(.leading, 18)

            // Divider
            Rectangle()
                .fill(.white.opacity(0.10))
                .frame(width: 1)
                .padding(.vertical, 18)
                .padding(.horizontal, 14)

            // Status / transcript text
            Text(statusText)
                .font(MF.Font.label)
                .foregroundStyle(.primary.opacity(0.85))
                .lineLimit(2)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.trailing, 18)
                .animation(.easeOut(duration: 0.12), value: controller.transcript)
        }
        .frame(width: MF.Pill.width, height: MF.Pill.height)
        .background { pillBackground }
        .shadow(color: .black.opacity(0.22), radius: 22, x: 0, y: 8)
    }

    // MARK: - Background

    private var pillBackground: some View {
        ZStack {
            // Tint behind the material so windowBackgroundColor bleeds through vibrancy
            RoundedRectangle(cornerRadius: MF.Pill.cornerRadius, style: .continuous)
                .fill(MF.Color.pillTint)
            // Material layer
            RoundedRectangle(cornerRadius: MF.Pill.cornerRadius, style: .continuous)
                .fill(.regularMaterial)
            // 1 pt border
            RoundedRectangle(cornerRadius: MF.Pill.cornerRadius, style: .continuous)
                .strokeBorder(MF.Color.pillBorder, lineWidth: 1)
        }
    }

    // MARK: - Status text

    private var statusText: String {
        switch controller.state {
        case .idle:                    return ""
        case .starting:                return "Starting…"
        case .listening:
            return controller.transcript.isEmpty ? "Listening…" : controller.transcript
        case .finishing:
            // Parakeet resolves in one pass on release — nothing to show until it lands.
            return controller.transcript.isEmpty ? "Transcribing…" : controller.transcript
        case .error(let message):      return message
        }
    }
}

// MARK: - VU meter

/// 32 capsule bars that breathe with the mic level.
///
/// Golden-ratio phase offsets make bars ripple instead of pumping in unison.
/// `controller.level` is already smoothed by DictationController, so no second
/// smoothing pass is needed here.
private struct VUMeter: View {
    let level: Float
    let isActive: Bool

    // Golden-ratio-spaced phase offsets — computed once at compile time.
    private static let phases: [Double] = {
        (0..<MF.VU.barCount).map { i in
            (Double(i) * 0.618033988749895).truncatingRemainder(dividingBy: 1.0)
        }
    }()

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !isActive)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            Canvas { ctx, size in
                let midY = size.height / 2

                for i in 0..<MF.VU.barCount {
                    let phase = Self.phases[i]
                    let wave = sin(t * 5.5 + phase * .pi * 2)
                    let amp = CGFloat(max(0.05, level))
                    let h = max(3.0, amp * (0.50 + 0.50 * CGFloat(wave)) * size.height)
                    let x = CGFloat(i) * (MF.VU.barWidth + MF.VU.barGap)

                    let rect = CGRect(
                        x: x,
                        y: midY - h / 2,
                        width: MF.VU.barWidth,
                        height: h
                    )
                    let path = Path(
                        roundedRect: rect,
                        cornerRadius: MF.VU.barWidth / 2
                    )
                    ctx.fill(path, with: .color(barColor(for: CGFloat(level))))
                }
            }
        }
    }

    /// Colour shifts with level to provide headroom feedback without a separate meter.
    private func barColor(for level: CGFloat) -> Color {
        switch level {
        case ..<0.55: return MF.VU.barColorLow
        case ..<0.85: return MF.VU.barColorMid
        default:      return MF.VU.barColorHigh
        }
    }
}
