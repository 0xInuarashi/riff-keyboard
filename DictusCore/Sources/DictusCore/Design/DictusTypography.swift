#if os(iOS)
import SwiftUI

public extension Font {
    static let dictusHeading: Font = .system(.title, design: .default, weight: .semibold)
    static let dictusSubheading: Font = .system(.title3, design: .default, weight: .medium)
    static let dictusBody: Font = .system(.body)
    static let dictusCaption: Font = .system(.caption)
}
#endif
