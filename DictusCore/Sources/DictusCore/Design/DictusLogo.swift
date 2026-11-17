#if os(iOS)
import SwiftUI

/// The angular Riff mark. Its proportions match the app icon.
public struct DictusLogo: View {
    public var height: CGFloat

    private let color: Color

    public init(height: CGFloat = 80, color: Color = .dictusAccent) {
        self.height = height
        self.color = color
    }

    public var body: some View {
        Path { path in
            path.addLines([
                point(0.18, 0.89), point(0.18, 0.11), point(0.65, 0.11), point(0.83, 0.29),
                point(0.83, 0.40), point(0.68, 0.55), point(0.18, 0.55)
            ])
            path.move(to: point(0.51, 0.57))
            path.addLine(to: point(0.86, 0.89))
        }
        .stroke(color, style: StrokeStyle(lineWidth: height * 0.075, lineCap: .square, lineJoin: .bevel))
        .frame(width: height, height: height)
        .accessibilityHidden(true)
    }

    private func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
        CGPoint(x: x * height, y: y * height)
    }
}
#endif
