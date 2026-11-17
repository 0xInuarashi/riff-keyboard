// DictusCore/Sources/DictusCore/PremiumFlags.swift
import Foundation

/// Shared release settings for the app and keyboard.
public enum PremiumFlags {
    /// Set to false for a release that uses StoreKit purchases and trials.
    public static let proIncluded = true

    /// Free releases grant the same features without presenting offers or starting trials.
    public static var paywallVisible: Bool { !proIncluded }

    /// Last day of the lifetime founder window, or `nil` while it is not
    /// scheduled (#350).
    ///
    /// The window runs one month from the App Store release that ships the
    /// first real Pro feature (#79). That release has no date yet, so none can
    /// be written here. While this is `nil` the lifetime row shows its price
    /// and its scope sentence and **no founder line at all** — a promotional
    /// claim with a missing date is worse than no claim.
    ///
    /// WHY it governs copy only: the price comes from StoreKit, so the App
    /// Store Connect price change at the end of the window is what moves
    /// 79,99 € to 149,99 €. Setting this constant announces the deadline; it
    /// does not enforce it. Both have to be done on the same day.
    ///
    /// To open the window, give it the **last day the offer stands**:
    /// `DateComponents(calendar: .current, year: 2026, month: 9, day: 12).date`
    ///
    /// That expression is midnight at the *start* of 12 September, while the
    /// offer runs to the end of that day. Nothing should compare against this
    /// value directly — `LifetimeFounderWindow.announcedEnd()` owns that
    /// boundary, and reading the constant raw retires the line a day early.
    public static let lifetimeFounderOfferEnd: Date? = nil

    #if DEBUG
    /// Debug-only: report the user as a Pro subscriber whatever StoreKit says (#460).
    ///
    /// ### Why it exists
    ///
    /// #460 makes the keyboard's Smart Mode surface *absent* whenever `paywallVisible` is
    /// false, and that hides it from the maintainer too. Smart Modes are still being
    /// built and still need device testing, so the fix would otherwise block the work
    /// it exists to protect. This is the way back in, and it is a hard requirement of
    /// that change rather than a convenience.
    ///
    /// ### Why it lives here
    ///
    /// Beside the flag it opposes. `paywallVisible` decides what may be *sold*; this
    /// decides what the user is *entitled to*, and reading them a screen apart is how
    /// the two get confused. They are not symmetrical and must not be used as if they
    /// were: turning this on does not open the paywall or any of the surfaces gated on
    /// `paywallVisible` — it grants the entitlement those surfaces would have sold.
    ///
    /// ### Why the App Group and not a `static let`
    ///
    /// Two processes have to agree. The fan lives in the keyboard extension and the
    /// toggle that flips this lives in the app, so a per-process constant would grant
    /// entitlement on one side of the App Group and refuse it on the other — which is
    /// #401, already paid for once. A stored value also means the maintainer flips it
    /// on device instead of rebuilding.
    ///
    /// ### Why it cannot ship
    ///
    /// The whole property is `#if DEBUG`, so the Release binary contains neither it nor
    /// the key below nor the branch in `ProStatusManager.isProActiveStatic` that reads
    /// it. There is no runtime path to a forced entitlement in a build a user can install.
    ///
    /// Consulted in exactly one place — `ProStatusManager.isProActiveStatic`, which is
    /// what `FeatureGate.isProActive` and the keyboard's toolbar both already read. One
    /// source of truth for entitlement; no surface gets its own force path.
    public static var debugProEntitlementForced: Bool {
        get { AppGroup.defaults.bool(forKey: SharedKeys.debugProEntitlementForced) }
        set {
            AppGroup.defaults.set(newValue, forKey: SharedKeys.debugProEntitlementForced)
            // The reader is another process — same reason `ProStatusManager.setProActive`
            // synchronises.
            AppGroup.defaults.synchronize()
        }
    }
    #endif
}
