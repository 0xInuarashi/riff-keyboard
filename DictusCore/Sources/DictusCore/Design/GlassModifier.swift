#if os(iOS)
import SwiftUI

/// Gives cards and controls a neutral surface with a fine perimeter line.
public struct GlassModifier<S: Shape>: ViewModifier {
    public let shape: S

    public init(shape: S) {
        self.shape = shape
    }

    public func body(content: Content) -> some View {
        content
            .background(shape.fill(Color.dictusSurface))
            .overlay(shape.stroke(Color.dictusBorder, lineWidth: 0.75).allowsHitTesting(false))
    }
}

public struct GlassPressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let pressedScale: CGFloat
    private let pressedOpacity: Double

    public init(pressedScale: CGFloat = 0.97, pressedOpacity: Double = 0.85) {
        self.pressedScale = pressedScale
        self.pressedOpacity = pressedOpacity
    }

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? pressedScale : 1)
            .opacity(configuration.isPressed ? pressedOpacity : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

public extension View {
    func dictusGlass<S: Shape>(in shape: S = RoundedRectangle(cornerRadius: 16)) -> some View {
        modifier(GlassModifier(shape: shape))
    }

    func dictusGlassBar() -> some View {
        dictusGlass(in: Capsule())
    }
}
#endif
