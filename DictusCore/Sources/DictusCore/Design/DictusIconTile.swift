#if os(iOS)
import SwiftUI

public struct DictusIconTile: View {
    public var logoHeight: CGFloat

    public init(logoHeight: CGFloat) {
        self.logoHeight = logoHeight
    }

    public var body: some View {
        let side = DictusLogoGeometry.tileSide(forHeight: logoHeight)
        let tile = RoundedRectangle(
            cornerRadius: DictusLogoGeometry.tileCornerRadius(forSide: side),
            style: .continuous
        )

        DictusLogo(height: logoHeight, color: .white)
            .frame(width: side, height: side)
            .background(
                tile.fill(
                    LinearGradient(
                        colors: [Color(hex: 0x222222), Color(hex: 0x080808)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            )
            .overlay(tile.strokeBorder(.white.opacity(0.28), lineWidth: 0.75))
    }
}
#endif
