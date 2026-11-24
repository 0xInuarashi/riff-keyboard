// DictusWidgets/DictusLiveActivity.swift
// Live Activity views for Dynamic Island + Lock Screen banner.
import ActivityKit
import SwiftUI
import WidgetKit
import DictusCore

/// Live Activity configuration for Dictus.
///
/// WHY all views in one file:
/// Widget extensions should minimize file count. The compact/expanded/lock screen
/// views are tightly coupled — they share the same ContentState and brand assets.
/// Splitting them would add complexity without benefit.
struct DictusLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: DictusLiveActivityAttributes.self) { context in
            // Lock Screen / StandBy banner
            lockScreenView(context: context)
        } dynamicIsland: { context in
            DynamicIsland {
                // Expanded view (long press on Dynamic Island)
                DynamicIslandExpandedRegion(.leading) {
                    expandedLeading(context: context)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    expandedTrailing(context: context)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    expandedBottom(context: context)
                }
            } compactLeading: {
                compactLeading(context: context)
            } compactTrailing: {
                compactTrailing(context: context)
            } minimal: {
                // Minimal view when multiple Live Activities compete for space
                minimalView(context: context)
            }
            .widgetURL(tapURL(context: context))
        }
    }

    @ViewBuilder
    private func activityMark(context: ActivityViewContext<DictusLiveActivityAttributes>, height: CGFloat) -> some View {
        if context.state.phase == .recording {
            MiniLogoBars(levels: normalizedLevels(context.state.waveformLevels, count: 3), animated: true)
        } else {
            DictusLogo(height: height, color: .white)
        }
    }

    // MARK: - Voice notes (#620)

    /// The voice note ring, when it owns the island for this state. Nil means the
    /// dictation draws, exactly as it did before #620: every region below asks this
    /// first and otherwise falls through to its original switch, untouched. The rule
    /// is `LiveActivityRenderOwner`, tested in DictusCore per state combination.
    private func voiceNotes(_ context: ActivityViewContext<DictusLiveActivityAttributes>) -> VoiceNoteActivityContent? {
        let phase = LiveActivityStateMachine.Phase(rawValue: context.state.phase.rawValue) ?? .idle
        guard LiveActivityRenderOwner.resolve(phase: phase, voiceNote: context.state.voiceNote) == .voiceNotes else {
            return nil
        }
        return context.state.voiceNote
    }

    /// Where a tap goes: the voice note screen when the ring owns the island, the app
    /// as before otherwise.
    private func tapURL(context: ActivityViewContext<DictusLiveActivityAttributes>) -> URL? {
        voiceNotes(context)?.url ?? URL(string: "riff2://open")
    }

    // MARK: - Compact Views (Dynamic Island pill)

    /// Compact leading: logo bars (static in standby, animated heights in recording)
    @ViewBuilder
    private func compactLeading(context: ActivityViewContext<DictusLiveActivityAttributes>) -> some View {
        if voiceNotes(context) != nil {
            // The Dictus logo, whatever the notes are doing (#620 decision 11).
            DictusLogo(height: 14, color: .white)
                .frame(width: 20, height: 14)
        } else {
        switch context.state.phase {
        case .standby:
            // Static 3-bar logo at mini size
            DictusLogo(height: 14, color: .white)
                .frame(width: 20, height: 14)
        case .recording:
            // Animated bars driven by waveform data
            let levels = normalizedLevels(context.state.waveformLevels, count: 3)
            MiniLogoBars(levels: levels, animated: true)
                .frame(width: 20, height: 14)
        case .transcribing:
            // Pulsing bars at medium height
            MiniLogoBars(levels: [0.4, 0.6, 0.4], animated: true)
                .frame(width: 20, height: 14)
        case .processing:
            // A pronounced centre peak, echoing the localized peak the keyboard
            // overlay sweeps in this stage (#267). Three bars cannot carry the
            // sweep itself -- ActivityKit's update budget is ~1/s -- so the shape
            // and the colour of the trailing label do the distinguishing here.
            MiniLogoBars(levels: [0.25, 0.85, 0.25], animated: true)
                .frame(width: 20, height: 14)
        case .ready:
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(Color(hex: 0xE0E0E0))
                .font(.system(size: 14))
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(Color(hex: 0xB5B5B5))
                .font(.system(size: 14))
        }
        }
    }

    /// Compact trailing: "On" text in standby, timer in recording
    @ViewBuilder
    private func compactTrailing(context: ActivityViewContext<DictusLiveActivityAttributes>) -> some View {
        if let note = voiceNotes(context) {
            VoiceNoteCompactTrailing(note: note)
        } else {
        switch context.state.phase {
        case .standby:
            if context.state.isPaused {
                // A call paused standby (#353). A glyph, not the word: the pill grows
                // with its text, and « En pause » would double its width.
                Image(systemName: "pause.fill")
                    .foregroundColor(.white.opacity(0.7))
                    .font(.system(size: 14))
            } else {
                Text("On")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
            }
        case .recording:
            Text("Rec")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(Color(hex: 0xB5B5B5))
        case .transcribing:
            // Small spinner-like indicator via SF Symbol
            Image(systemName: "ellipsis")
                .foregroundColor(.white.opacity(0.7))
                .font(.system(size: 14))
        case .processing:
            // Different glyph AND different colour from transcribing: at compact
            // size the pill shows one icon, so it has to carry the whole
            // distinction on its own (#267). The lighter accent blue keeps it
            // apart from transcribing without leaving the brand's blues (#789).
            Image(systemName: "sparkles")
                .foregroundColor(Color(hex: 0xC4C4C4))
                .font(.system(size: 14))
        case .ready:
            Text("Done")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(Color(hex: 0xE0E0E0))
        case .failed:
            Image(systemName: "xmark")
                .foregroundColor(Color(hex: 0xB5B5B5))
                .font(.system(size: 14))
        }
        }
    }

    // MARK: - Minimal View

    @ViewBuilder
    private func minimalView(context: ActivityViewContext<DictusLiveActivityAttributes>) -> some View {
        if let note = voiceNotes(context) {
            // Smaller than the compact ring: the minimal circle is tighter still.
            VoiceNoteRing(note: note, diameter: 14, lineWidth: 2, countSize: 7)
        } else {
        switch context.state.phase {
        case .standby where context.state.isPaused:
            Image(systemName: "pause.fill")
                .foregroundColor(.white.opacity(0.7))
                .font(.system(size: 12))
        case .standby:
            // Full 3-bar logo even in minimal — single bar was invisible
            DictusLogo(height: 12, color: .white)
                .frame(width: 14, height: 12)
        case .recording:
            let levels = normalizedLevels(context.state.waveformLevels, count: 3)
            MiniLogoBars(levels: levels, animated: true)
                .frame(width: 14, height: 12)
        case .ready:
            Image(systemName: "checkmark")
                .foregroundColor(Color(hex: 0xE0E0E0))
                .font(.system(size: 12, weight: .bold))
        default:
            Image(systemName: "waveform")
                .foregroundColor(.white.opacity(0.7))
                .font(.system(size: 12))
        }
        }
    }

    // MARK: - Expanded Views (long press)

    @ViewBuilder
    private func expandedLeading(context: ActivityViewContext<DictusLiveActivityAttributes>) -> some View {
        if voiceNotes(context) != nil {
            // Logo on the left, on the alert and on a long-press alike (decision 10).
            HStack(spacing: 8) {
                DictusLogo(height: 18, color: .white)
                    .frame(width: 24, height: 18)
                Text(verbatim: "Riff Keyboard")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
            }
            .frame(maxHeight: .infinity, alignment: .center)
        } else {
        HStack(spacing: 8) {
            // Logo bars
            activityMark(context: context, height: 18)
            .frame(width: 24, height: 18)

            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: "Riff Keyboard")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)

                // One line, whatever the language (#664): the leading region is
                // narrow, and « Enregistrement... » wrapped inside its dots on an
                // iPhone 15 Pro Max. A label that does not fit shrinks a little,
                // then truncates, rather than spilling onto a second line.
                Group {
                switch context.state.phase {
                case .standby:
                    (context.state.isPaused ? Text("Paused") : Text("On"))
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.6))
                case .recording:
                    Text("Recording...")
                        .font(.system(size: 12))
                        .foregroundColor(Color(hex: 0xB5B5B5))
                case .transcribing:
                    Text("Transcribing...")
                        .font(.system(size: 12))
                        .foregroundColor(Color(hex: 0xF5F5F5))
                case .processing:
                    Text("Processing...")
                        .font(.system(size: 12))
                        .foregroundColor(Color(hex: 0xC4C4C4))
                case .ready:
                    Text("Transcription ready")
                        .font(.system(size: 12))
                        .foregroundColor(Color(hex: 0xE0E0E0))
                case .failed:
                    Text("Error")
                        .font(.system(size: 12))
                        .foregroundColor(Color(hex: 0xB5B5B5))
                }
                }
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            }
        }
        .frame(maxHeight: .infinity, alignment: .center)
        }
    }

    @ViewBuilder
    private func expandedTrailing(context: ActivityViewContext<DictusLiveActivityAttributes>) -> some View {
        if let note = voiceNotes(context), note.isAlerting {
            // The alert's layout (#620 decision 10): the ring, large, on the right.
            VoiceNoteRing(note: note, diameter: 44, lineWidth: 5, countSize: 18)
                .frame(maxHeight: .infinity, alignment: .center)
        } else {
        HStack(spacing: 10) {
            Spacer(minLength: 0) // Push trailing elements to the right edge
            switch context.state.phase {
            case .standby:
                // Power off button — ends Live Activity via LiveActivityIntent (no app open)
                Button(intent: StopStandbyIntent()) {
                    Image(systemName: "power")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white.opacity(0.8))
                        .frame(width: 32, height: 32)
                        .background(Color.white.opacity(0.15))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)

                // Record button
                // Force unwrap is safe: compile-time constant deep link, always well-formed.
                // swiftlint:disable:next force_unwrapping
                Link(destination: URL(string: "riff2://dictate")!) {
                    Image(systemName: "mic.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.black)
                        .frame(width: 32, height: 32)
                        .background(Color(hex: 0xF5F5F5))
                        .clipShape(Circle())
                }
            case .recording:
                // Stop button (left side)
                // Force unwrap is safe: compile-time constant deep link, always well-formed.
                // swiftlint:disable:next force_unwrapping
                Link(destination: URL(string: "riff2://stop")!) {
                    Image(systemName: "stop.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.black)
                        .frame(width: 32, height: 32)
                        .background(Color(hex: 0xB5B5B5))
                        .clipShape(Circle())
                }

                // Timer (right, naturally trailing — aligns with compact trailing)
                if let startDate = context.state.recordingStartDate {
                    Text(startDate, style: .timer)
                        .font(.system(size: 16, weight: .medium, design: .monospaced))
                        .foregroundColor(.white)
                        .monospacedDigit()
                }
            case .transcribing:
                ProgressView()
                    .tint(.white)
            case .processing:
                ProgressView()
                    .tint(Color(hex: 0xC4C4C4))
            case .ready, .failed:
                EmptyView()
            }
        }
        .frame(maxHeight: .infinity, alignment: .center)
        }
    }

    @ViewBuilder
    private func expandedBottom(context: ActivityViewContext<DictusLiveActivityAttributes>) -> some View {
        if let note = voiceNotes(context) {
            // Under the dictation buttons on a long-press (decision 13), alone under the
            // logo and the large ring on the alert (decision 10).
            VoiceNoteLine(note: note, showsRing: !note.isAlerting, fontSize: note.isAlerting ? 15 : 13)
                .padding(.horizontal, 8)
        } else {
        switch context.state.phase {
        case .recording:
            EmptyView()
        case .ready:
            if let preview = context.state.transcriptionPreview {
                Text(verbatim: preview)
                    .font(.system(size: 13))
                    .foregroundColor(.white.opacity(0.8))
                    .lineLimit(2)
                    .padding(.horizontal, 8)
            }
        default:
            EmptyView()
        }
        }
    }

    // MARK: - Lock Screen Banner

    @ViewBuilder
    private func lockScreenView(context: ActivityViewContext<DictusLiveActivityAttributes>) -> some View {
        if let note = voiceNotes(context) {
            // iPhones without a Dynamic Island get the same design here (decision 12).
            VoiceNoteLockScreen(note: note)
                .widgetURL(tapURL(context: context))
        } else {
        HStack(spacing: 12) {
            // Logo
            activityMark(context: context, height: 20)
            .frame(width: 28, height: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: "Riff Keyboard")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.white)

                switch context.state.phase {
                case .standby:
                    (context.state.isPaused ? Text("Paused") : Text("On"))
                        .font(.system(size: 13))
                        .foregroundColor(.white.opacity(0.6))
                case .recording:
                    if let startDate = context.state.recordingStartDate {
                        HStack(spacing: 4) {
                            Circle()
                                .fill(Color(hex: 0xB5B5B5))
                                .frame(width: 6, height: 6)
                            Text(startDate, style: .timer)
                                .font(.system(size: 13, design: .monospaced))
                                .foregroundColor(.white.opacity(0.8))
                                .monospacedDigit()
                        }
                    }
                case .transcribing:
                    // Same one-line rule as the expanded island (#664).
                    Text("Transcribing...")
                        .font(.system(size: 13))
                        .foregroundColor(Color(hex: 0xF5F5F5))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                case .processing:
                    Text("Processing...")
                        .font(.system(size: 13))
                        .foregroundColor(Color(hex: 0xC4C4C4))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                case .ready:
                    // Two Texts, not `Text(preview ?? "...")`: a `??` turns the fallback
                    // into a plain String, which Text prints without looking it up.
                    // The preview is the user's own words, so it is shown verbatim.
                    (context.state.transcriptionPreview.map { Text(verbatim: $0) } ?? Text("Transcription ready"))
                        .font(.system(size: 13))
                        .foregroundColor(Color(hex: 0xE0E0E0))
                        .lineLimit(1)
                case .failed:
                    Text("Error")
                        .font(.system(size: 13))
                        .foregroundColor(Color(hex: 0xB5B5B5))
                }
            }

            Spacer()

            // Action buttons
            switch context.state.phase {
            case .standby:
                HStack(spacing: 8) {
                    Button(intent: StopStandbyIntent()) {
                        Image(systemName: "power")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.white.opacity(0.7))
                            .frame(width: 36, height: 36)
                            .background(Color.white.opacity(0.1))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    // Force unwrap is safe: compile-time constant deep link, always well-formed.
                    // swiftlint:disable:next force_unwrapping
                    Link(destination: URL(string: "riff2://dictate")!) {
                        Image(systemName: "mic.fill")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.black)
                            .frame(width: 36, height: 36)
                            .background(Color(hex: 0xF5F5F5))
                            .clipShape(Circle())
                    }
                }
            case .recording:
                // Force unwrap is safe: compile-time constant deep link, always well-formed.
                // swiftlint:disable:next force_unwrapping
                Link(destination: URL(string: "riff2://stop")!) {
                    Image(systemName: "stop.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.black)
                        .frame(width: 36, height: 36)
                        .background(Color(hex: 0xB5B5B5))
                        .clipShape(Circle())
                }
            default:
                EmptyView()
            }
        }
        .padding(16)
        .background(Color(hex: 0x0C0C0C))
        }
    }

    // MARK: - Helpers

    /// Normalize waveform levels to the requested count.
    /// Downsamples by averaging groups if input has more values.
    /// Pads with default values if input has fewer.
    private func normalizedLevels(_ levels: [Float], count: Int) -> [Float] {
        guard !levels.isEmpty else {
            // Default levels matching logo proportions
            return count == 3
                ? [0.43, 1.0, 0.64]
                : Array(repeating: 0.3, count: count)
        }

        if levels.count == count {
            return levels
        }

        if levels.count > count {
            // Downsample: average groups
            let groupSize = levels.count / count
            return (0..<count).map { i in
                let start = i * groupSize
                let end = min(start + groupSize, levels.count)
                let slice = levels[start..<end]
                return slice.reduce(0, +) / Float(slice.count)
            }
        }

        // Pad with last value or 0.3
        var result = levels
        let pad = levels.last ?? 0.3
        while result.count < count {
            result.append(pad)
        }
        return result
    }
}

// MARK: - Voice note ring (#620)

/// Colours of the ring, from the brand kit.
private enum RingColor {
    static let pending = Color.white.opacity(0.35)
    static let ready = Color(hex: 0xE0E0E0)
    static let failed = Color(hex: 0xB5B5B5)

    static func of(_ segment: VoiceNoteSegment) -> Color {
        switch segment {
        case .pending: return pending
        case .ready: return ready
        case .failed: return failed
        }
    }
}

/// The ring (#620 decision 9): one segment per note in share order, the number of
/// ready unread notes in the centre, white, like a badge.
///
/// Motion (decision 14), all under 2 s and none when the screen is dimmed
/// (`isLuminanceReduced`, the Always-On case): a segment that changes colour sweeps
/// into its new colour, the number rolls with `numericText`, and the ring settles
/// from a slightly smaller size when every note is finished. Live Activities run no
/// timeline of their own — each animation is the transition between two pushed
/// states — so the "pulse" is that one settling step, not a loop.
private struct VoiceNoteRing: View {
    let note: VoiceNoteActivityContent
    let diameter: CGFloat
    let lineWidth: CGFloat
    let countSize: CGFloat

    @Environment(\.isLuminanceReduced) private var isLuminanceReduced

    var body: some View {
        let count = note.segments.count
        // A small gap between segments so two of the same colour read as two notes.
        let gap = count > 1 ? 0.035 : 0
        ZStack {
            ForEach(Array(note.segments.enumerated()), id: \.offset) { index, segment in
                Circle()
                    .trim(from: Double(index) / Double(count) + gap / 2,
                          to: Double(index + 1) / Double(count) - gap / 2)
                    .stroke(RingColor.of(segment), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            if note.readyCount > 0 {
                Text(verbatim: "\(note.readyCount)")
                    .font(.system(size: countSize, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .monospacedDigit()
                    .contentTransition(.numericText())
            }
        }
        .frame(width: diameter, height: diameter)
        .scaleEffect(note.allFinished || isLuminanceReduced ? 1 : 0.92)
        .animation(isLuminanceReduced ? nil : .easeOut(duration: 0.6), value: note.segments)
        .animation(isLuminanceReduced ? nil : .spring(duration: 0.8, bounce: 0.4), value: note.allFinished)
        .animation(isLuminanceReduced ? nil : .default, value: note.readyCount)
        // The words come localised from DictusApp, which builds them with its own catalog
        // (`VoiceNoteCopy`), so they are printed verbatim here. The brand is the fallback
        // for the first seconds of a note, when there is no line yet; it is the same in
        // every language, so it is spoken verbatim.
        .accessibilityLabel(note.statusLine.map { Text(verbatim: $0) } ?? note.receivedLine.map { Text(verbatim: $0) } ?? Text(verbatim: "Riff Keyboard"))
    }
}

/// Compact trailing: the "received" glyph entering from the top while a slow note
/// runs (decision 6), the ring otherwise.
///
/// No text here (device test, 2026-10-01): iOS fixes the compact island's height and
/// grows its width with the content, so "Message vocal reçu" stretched the pill into
/// a long thin bar. The words stay in the expanded view; the compact one keeps its
/// normal size.
///
/// The ring is 17 pt and sits flush right behind invisible leading space. At 20 pt its
/// right side was cut by the island's rounded edge; with a 4 pt trailing inset instead,
/// its left side was cut, because the padding pushed it past the leading bound of the
/// trailing region (both on an iPhone 15 Pro Max, 2026-10-01). Widening the region on
/// its leading side is what leaves the ring whole.
private struct VoiceNoteCompactTrailing: View {
    let note: VoiceNoteActivityContent

    @Environment(\.isLuminanceReduced) private var isLuminanceReduced

    var body: some View {
        ZStack {
            if note.receivedLine != nil {
                VoiceNoteReceivedGlyph(diameter: 17, label: note.receivedLine)
                    .transition(.move(edge: .top).combined(with: .opacity))
            } else {
                VoiceNoteRing(note: note, diameter: 17, lineWidth: 2.2, countSize: 9)
                    .transition(.opacity)
            }
        }
        .padding(.leading, 6)
        .animation(isLuminanceReduced ? nil : .easeOut(duration: 0.5), value: note.receivedLine)
    }
}

/// "A voice note came in": a pending ring, the shape the note is about to take,
/// with a down arrow in its centre. Chosen over a bare SF Symbol (`arrow.down.circle`
/// reads as "download", `waveform` alone as "recording") because it is the ring's own
/// first frame: the arrow gives way to the count when the note is ready, in place.
private struct VoiceNoteReceivedGlyph: View {
    let diameter: CGFloat
    /// "Voice note received", localised by DictusApp.
    let label: String?

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.35), lineWidth: 2.2)
            Image(systemName: "arrow.down")
                .font(.system(size: diameter * 0.5, weight: .bold))
                .foregroundColor(.white)
        }
        .frame(width: diameter, height: diameter)
        .accessibilityLabel(label.map { Text(verbatim: $0) } ?? Text(verbatim: "Riff Keyboard"))
    }
}

/// The voice notes line: "N voice notes ready · Tap to read" (decision 10), with a
/// small ring in front of it on a long-press, where the dictation buttons hold the
/// top of the expanded island (decision 13).
private struct VoiceNoteLine: View {
    let note: VoiceNoteActivityContent
    let showsRing: Bool
    let fontSize: CGFloat

    var body: some View {
        // Centred in the expanded bottom region (device test, 2026-10-01): left-aligned
        // under the logo and the buttons, it read as belonging to neither.
        HStack(spacing: 8) {
            if showsRing {
                VoiceNoteRing(note: note, diameter: 18, lineWidth: 2.5, countSize: 9)
            }
            // Localised by DictusApp (`VoiceNoteCopy`), printed as is.
            if let line = note.statusLine ?? note.receivedLine {
                Text(verbatim: line)
                    .font(.system(size: fontSize, weight: .semibold))
                    .foregroundColor(.white.opacity(0.9))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }
}

/// The Lock Screen and the banner of an iPhone without a Dynamic Island: the same
/// design, logo, line, ring (decision 12).
private struct VoiceNoteLockScreen: View {
    let note: VoiceNoteActivityContent

    var body: some View {
        HStack(spacing: 12) {
            DictusLogo(height: 20, color: .white)
                .frame(width: 28, height: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: "Riff Keyboard")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.white)
                // Localised by DictusApp (`VoiceNoteCopy`), printed as is.
                if let line = note.statusLine ?? note.receivedLine {
                    Text(verbatim: line)
                        .font(.system(size: 13))
                        .foregroundColor(.white.opacity(0.8))
                        .lineLimit(2)
                }
            }
            Spacer()
            VoiceNoteRing(note: note, diameter: 40, lineWidth: 4.5, countSize: 16)
        }
        .padding(16)
        .background(Color(hex: 0x0C0C0C))
    }
}

// MARK: - Mini Logo Bars

/// Compact waveform for the Dynamic Island.
struct MiniLogoBars: View {
    let levels: [Float]
    let animated: Bool

    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: min(geometry.size.width * 0.12, 3)) {
                ForEach(0..<min(levels.count, 3), id: \.self) { index in
                    Capsule()
                        .fill(DictusWaveformStyle.barColor(at: index, count: 3, color: .white))
                        .frame(
                            width: min(geometry.size.width * 0.15, 3),
                            height: max(1.5, CGFloat(levels[index]) * geometry.size.height)
                        )
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .animation(animated ? .easeOut(duration: 0.3) : nil, value: levels)
        }
    }
}

// MARK: - Waveform Bars (Expanded View)

/// 5-bar waveform for the expanded Dynamic Island view.
struct WaveformBars: View {
    let levels: [Float]

    var body: some View {
        GeometryReader { geo in
            let barWidth: CGFloat = 3
            let spacing: CGFloat = 4  // Fixed tight spacing

            HStack(spacing: spacing) {
                ForEach(0..<min(levels.count, 5), id: \.self) { index in
                    let height = max(4, CGFloat(levels[index]) * geo.size.height)

                    RoundedRectangle(cornerRadius: barWidth / 2)
                        .fill(DictusWaveformStyle.barColor(at: index, count: 5, color: .white))
                        .frame(width: barWidth, height: height)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .center)
            .animation(.easeInOut(duration: 0.3), value: levels)
        }
    }
}
