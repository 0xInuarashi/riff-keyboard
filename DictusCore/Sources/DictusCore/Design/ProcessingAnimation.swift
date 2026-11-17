#if os(iOS)
// DictusCore/Sources/DictusCore/Design/ProcessingAnimation.swift
// Branded processing/transcribing animation using logo-inspired pulsing bars.
import SwiftUI

/// Staggered light bars for processing.
public struct ProcessingAnimation: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase: CGFloat = 0

    /// Overall height of the animation.
    public var height: CGFloat = 48

    private var barWidth: CGFloat { min(height * 0.08, 4) }

    public init(height: CGFloat = 48) {
        self.height = height
    }

    public var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<3, id: \.self) { index in
                let delay = Double(index) * 0.2
                let scale = pulseScale(for: delay)

                RoundedRectangle(cornerRadius: barWidth / 2)
                    .fill(
                        LinearGradient(
                            colors: [.dictusGradientStart, .dictusGradientEnd],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: barWidth, height: height * scale)
                    .opacity(0.5 + scale * 0.5)
            }
        }
        .frame(height: height)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                phase = 1
            }
        }
    }

    /// Compute a pulse scale for a given delay offset.
    private func pulseScale(for delay: Double) -> CGFloat {
        // Each bar pulses between 0.4 and 1.0 with staggered timing
        let adjustedPhase = (phase + CGFloat(delay)).truncatingRemainder(dividingBy: 1.4)
        return 0.4 + 0.6 * abs(sin(adjustedPhase * .pi))
    }
}
#endif
