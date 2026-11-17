// DictusKeyboard/Vendored/Models/Theme.swift
// Vendored from giellakbd-ios Keyboard/Models/Theme.swift
// Stripped: No external dependencies to remove

import Foundation
import UIKit

// MARK: - Theme

struct Theme {
    // Colors
    let appearance: UIKeyboardAppearance
    let regularKeyColor: UIColor
    let specialKeyColor: UIColor
    let popupColor: UIColor
    let backgroundColor: UIColor
    let textColor: UIColor
    let inactiveTextColor: UIColor
    let borderColor: UIColor
    let specialKeyBorderColor: UIColor
    let keyShadowColor: UIColor
    let shiftActiveColor: UIColor
    let shiftTintColor: UIColor
    let popupBorderColor: UIColor
    let activeColor: UIColor
    let activeTextColor: UIColor
    let longPressActiveColor: UIColor
    let altKeyTextColor: UIColor

    // Metrics
    let keyCornerRadius: CGFloat
    let popupCornerRadius: CGFloat
    let keyVerticalMargin: CGFloat
    let keyHorizontalMargin: CGFloat

    // Fonts
    let lowerKeyFont: UIFont
    let capitalKeyFont: UIFont
    let modifierKeyFontSize: CGFloat
    let altKeyFontSize: CGFloat
    let altKeyFont: UIFont
    let popupLowerKeyFont: UIFont
    let popupCapitalKeyFont: UIFont
    let popupLongpressLowerKeyFont: UIFont
    let popupLongpressCapitalKeyFont: UIFont
    let bannerFont: UIFont

    // SF Symbols
    let sfSymbolConfiguration: UIImage.SymbolConfiguration

    // Banner
    let bannerBackgroundColor: UIColor
    let bannerSeparatorColor: UIColor
    let bannerTextColor: UIColor
    let bannerHorizontalMargin: CGFloat
    let bannerVerticalMargin: CGFloat
    let bannerHeight: CGFloat

    // Layout
    let altLabelTopAnchorConstant: CGFloat
    let altLabelBottomAnchorConstant: CGFloat
    let popupLongpressKeysPerRow: Int

    // MARK: - Static Factory Methods

    static func current(for traits: UITraitCollection) -> Theme {
        let device = DeviceContext.current
        let isDark = traits.userInterfaceStyle == .dark
        let isLegacy = !iOSVersion.isIOS26OrNewer

        let style: ThemeStyle = {
            switch (isDark, isLegacy) {
            case (true, true): return .legacyDark
            case (true, false): return .dark
            case (false, true): return .legacyLight
            case (false, false): return .light
            }
        }()

        return ThemeFactory.make(style, device: device, traits: traits)
    }
}

// MARK: - Theme Variants

enum ThemeStyle {
    case light
    case dark
    case legacyLight
    case legacyDark

    var isLegacy: Bool {
        switch self {
        case .legacyLight, .legacyDark: return true
        case .light, .dark: return false
        }
    }

    var isDark: Bool {
        switch self {
        case .dark, .legacyDark: return true
        case .light, .legacyLight: return false
        }
    }
}


// MARK: - Theme Factory

private struct ThemeFactory {
    static func make(_ style: ThemeStyle, device: DeviceContext, traits: UITraitCollection) -> Theme {
        let metrics = makeMetrics(for: device, traits: traits, legacy: style.isLegacy)
        let fonts = makeFonts(for: device, traits: traits, legacy: style.isLegacy)
        let colors = makeColors(for: style, device: device)

        return Theme(
            // Colors
            appearance: style.isDark ? .dark : .light,
            regularKeyColor: colors.regularKey,
            specialKeyColor: colors.specialKey,
            popupColor: colors.popup,
            backgroundColor: colors.background,
            textColor: colors.text,
            inactiveTextColor: colors.inactiveText,
            borderColor: colors.border,
            specialKeyBorderColor: colors.specialKeyBorder,
            keyShadowColor: colors.keyShadow,
            shiftActiveColor: colors.shiftActive,
            shiftTintColor: colors.shiftTint,
            popupBorderColor: colors.popupBorder,
            activeColor: colors.active,
            activeTextColor: colors.activeText,
            longPressActiveColor: colors.longPressActive,
            altKeyTextColor: colors.altKeyText,

            // Metrics
            keyCornerRadius: min(metrics.keyCornerRadius, 7),
            popupCornerRadius: 12.0,
            keyVerticalMargin: metrics.keyVerticalMargin,
            keyHorizontalMargin: metrics.keyHorizontalMargin,

            // Fonts
            lowerKeyFont: fonts.lowerKey,
            capitalKeyFont: fonts.capitalKey,
            modifierKeyFontSize: fonts.modifierKeySize,
            altKeyFontSize: fonts.altKeySize,
            altKeyFont: fonts.altKey,
            popupLowerKeyFont: fonts.lowerKey.withSize(fonts.lowerKey.pointSize + (style.isDark ? 10.0 : 16.0)),
            popupCapitalKeyFont: fonts.capitalKey.withSize(fonts.capitalKey.pointSize + (style.isDark ? 10.0 : 16.0)),
            popupLongpressLowerKeyFont: fonts.lowerKey,
            popupLongpressCapitalKeyFont: fonts.capitalKey,
            bannerFont: fonts.banner,

            // SF Symbols
            sfSymbolConfiguration: metrics.sfSymbolConfiguration,

            // Banner
            bannerBackgroundColor: colors.background,
            bannerSeparatorColor: colors.bannerSeparator,
            bannerTextColor: colors.bannerText,
            bannerHorizontalMargin: 16.0,
            bannerVerticalMargin: 8.0,
            bannerHeight: metrics.bannerHeight,

            // Layout
            altLabelTopAnchorConstant: metrics.altLabelTop,
            altLabelBottomAnchorConstant: metrics.altLabelBottom,
            popupLongpressKeysPerRow: metrics.popupLongpressKeysPerRow
        )
    }

    // MARK: - Metrics

    private struct Metrics {
        let keyCornerRadius: CGFloat
        let keyHorizontalMargin: CGFloat
        let keyVerticalMargin: CGFloat
        let bannerHeight: CGFloat
        let altLabelTop: CGFloat
        let altLabelBottom: CGFloat
        let popupLongpressKeysPerRow: Int
        let sfSymbolConfiguration: UIImage.SymbolConfiguration
    }

    private static func makeMetrics(for device: DeviceContext, traits: UITraitCollection, legacy: Bool) -> Metrics {
        if device.shouldUseIPadLayout(traitCollection: traits) {
            return makeiPadMetrics(for: device, legacy: legacy)
        } else {
            return makeiPhoneMetrics(for: device, legacy: legacy)
        }
    }

    private static func makeiPhoneMetrics(for device: DeviceContext, legacy: Bool) -> Metrics {
        let keyCornerRadius: CGFloat = legacy ? 5.0 : 10.0

        let keyVerticalMargin: CGFloat = {
            if legacy {
                return device.isLandscape ? 3.5 : 6.0
            } else {
                return device.isLandscape ? 3.5 : 5.5
            }
        }()

        let bannerHeight: CGFloat = 48.0

        let sfSymbolConfiguration = UIImage.SymbolConfiguration(
            pointSize: device.isLandscape ? 19 : 20,
            weight: .regular
        )

        return Metrics(
            keyCornerRadius: keyCornerRadius,
            keyHorizontalMargin: 3.0,
            keyVerticalMargin: keyVerticalMargin,
            bannerHeight: bannerHeight,
            altLabelTop: 0.0,
            altLabelBottom: 0.0,
            popupLongpressKeysPerRow: 10,
            sfSymbolConfiguration: sfSymbolConfiguration
        )
    }

    private static func makeiPadMetrics(for device: DeviceContext, legacy: Bool) -> Metrics {
        let keyCornerRadius: CGFloat = {
            if legacy {
                if device.isLargeLandscape { return 7.0 }
                else if device.isSmallOrMediumLandscape { return 6.0 }
                else { return 5.0 }
            } else {
                if device.isLargeLandscape { return 12.0 }
                else if device.isSmallOrMediumLandscape { return 11.0 }
                else { return 10.0 }
            }
        }()

        let keyHorizontalMargin: CGFloat = {
            if device.isLargeLandscape { return 4.0 }
            else if device.isSmallOrMediumLandscape { return 7.0 }
            else if device.isLargeIPad { return 3.0 }
            else { return 5.0 }
        }()

        let keyVerticalMargin: CGFloat = {
            if device.isLargeLandscape { return 4.0 }
            else if device.isSmallOrMediumLandscape { return 6.0 }
            else if device.isLargeIPad { return 3.5 }
            else { return 5.0 }
        }()

        let altLabelTop: CGFloat = {
            if device.isLargeIPad { return 3.0 }
            else if device.isSmallOrMediumLandscape { return 4.0 }
            else { return 5.0 }
        }()

        let altLabelBottom: CGFloat = {
            if device.isLargeIPad { return -3.0 }
            else if device.isSmallOrMediumLandscape { return -5.0 }
            else { return -4.0 }
        }()

        let sfSymbolConfiguration = UIImage.SymbolConfiguration(
            pointSize: device.isLandscape ? 24 : 21,
            weight: .light
        )

        return Metrics(
            keyCornerRadius: keyCornerRadius,
            keyHorizontalMargin: keyHorizontalMargin,
            keyVerticalMargin: keyVerticalMargin,
            bannerHeight: 55.0,
            altLabelTop: altLabelTop,
            altLabelBottom: altLabelBottom,
            popupLongpressKeysPerRow: 4,
            sfSymbolConfiguration: sfSymbolConfiguration
        )
    }

    // MARK: - Fonts

    private struct Fonts {
        let lowerKey: UIFont
        let capitalKey: UIFont
        let modifierKeySize: CGFloat
        let altKeySize: CGFloat
        let altKey: UIFont
        let banner: UIFont
    }

    private static func makeFonts(for device: DeviceContext, traits: UITraitCollection, legacy: Bool) -> Fonts {
        if device.shouldUseIPadLayout(traitCollection: traits) {
            let altKeySize: CGFloat = device.isSmallOrMediumLandscape ? 16.0 : 13.0
            let lowerKey: UIFont = {
                (device.isLargeLandscape || device.isSmallOrMediumLandscape)
                ? UIFont.systemFont(ofSize: 29.0)
                : UIFont.systemFont(ofSize: 24.0, weight: .light)
            }()
            let capitalKey: UIFont = {
                (device.isLargeLandscape || device.isSmallOrMediumLandscape)
                ? UIFont.systemFont(ofSize: 28.0)
                : UIFont.systemFont(ofSize: 22.0)
            }()

            return Fonts(
                lowerKey: lowerKey,
                capitalKey: capitalKey,
                modifierKeySize: 17.0,
                altKeySize: altKeySize,
                altKey: UIFont.systemFont(ofSize: altKeySize),
                banner: UIFont.systemFont(ofSize: 17.0)
            )
        } else {
            let altKeySize: CGFloat = 13.0
            let lowerKey = legacy
                ? UIFont.systemFont(ofSize: 25.0, weight: .light)
                : UIFont.systemFont(ofSize: 25.0)

            return Fonts(
                lowerKey: lowerKey,
                capitalKey: UIFont.systemFont(ofSize: 22.0),
                modifierKeySize: 16.0,
                altKeySize: altKeySize,
                altKey: UIFont.systemFont(ofSize: altKeySize),
                banner: UIFont.systemFont(ofSize: 17.0)
            )
        }
    }

    // MARK: - Colors

    private struct Colors {
        let regularKey: UIColor
        let specialKey: UIColor
        let popup: UIColor
        let background: UIColor
        let text: UIColor
        let inactiveText: UIColor
        let border: UIColor
        let specialKeyBorder: UIColor
        let keyShadow: UIColor
        let shiftActive: UIColor
        let shiftTint: UIColor
        let popupBorder: UIColor
        let active: UIColor
        let activeText: UIColor
        let longPressActive: UIColor
        let altKeyText: UIColor
        let bannerSeparator: UIColor
        let bannerText: UIColor
    }

    private static func makeColors(for style: ThemeStyle, device: DeviceContext) -> Colors {
        let dark = style.isDark
        let ink: UIColor = dark ? .white : .black
        let mutedInk = UIColor(white: dark ? 0.7 : 0.34, alpha: 1)
        let edge = UIColor(white: dark ? 0.33 : 0.77, alpha: 1)

        return Colors(
            regularKey: UIColor(white: dark ? 0.16 : 0.98, alpha: 1),
            specialKey: UIColor(white: dark ? 0.09 : 0.88, alpha: 1),
            popup: UIColor(white: dark ? 0.22 : 1, alpha: 1),
            background: .clear,
            text: ink,
            inactiveText: mutedInk,
            border: edge,
            specialKeyBorder: edge,
            keyShadow: .clear,
            shiftActive: ink,
            shiftTint: dark ? .black : .white,
            popupBorder: edge,
            active: UIColor(white: dark ? 0.29 : 0.81, alpha: 1),
            activeText: dark ? .black : .white,
            longPressActive: ink,
            altKeyText: device.isLargeIPad ? ink : mutedInk,
            bannerSeparator: edge,
            bannerText: ink
        )
    }
}
