#if os(iOS)
// DictusCore/Sources/DictusCore/Design/BrandWaveform.swift
// Live microphone and processing waveform.
import SwiftUI
import QuartzCore

@MainActor
final class BrandWaveformDriver: ObservableObject {
    @Published private(set) var displayLevels: [Float] = Array(repeating: 0, count: 30)
    @Published private(set) var processingPhase: Double = 0
    @Published private(set) var renderTick: Int = 0
    @Published private(set) var animation: WaveformAnimation = .micLevels

    private let barCount = 30
    private let smoothingFactor: Float = 0.3
    private let decayFactor: Float = 0.85

    private var energyLevels: [Float] = []
    private var isActive = false
    private var displayLink: CADisplayLink?

    /// Timestamp of the previous display-link callback, and the worst interval between
    /// two of them since the last heartbeat. Both read `CADisplayLink.timestamp` rather
    /// than the wall clock: it is monotonic, it is the frame's own time rather than the
    /// moment the callback happened to run, and it is what the keyboard's driver
    /// already used -- the two now measure the same thing the same way (#314).
    private var lastTickTime: CFTimeInterval?
    private var maxGapSinceHeartbeat: CFTimeInterval = 0
    private var lastHeartbeatTime: Date = .distantPast

    deinit {
        displayLink?.invalidate()
    }

    func update(energyLevels: [Float], animation: WaveformAnimation, isActive: Bool) {
        let previousAnimation = self.animation
        self.energyLevels = energyLevels
        self.animation = animation
        self.isActive = isActive

        // Restart the phase whenever the animation changes rather than only on the
        // way out of a self-driven one: the sine and the travelling peak share it,
        // and handing the peak the sine's phase would drop it mid-travel (#267).
        if animation != previousAnimation {
            processingPhase = ProcessingWaveform.centredPhase
        }

        if !isActive {
            displayLevels = targetLevels()
        }

        updateLoopState()
    }

    func forceStop() {
        stopLoop()
    }

    /// Whether the current animation has to be redrawn every frame.
    ///
    /// `.still` draws a fixed picture, and `Canvas` re-renders on `renderTick`, so
    /// without this a still waveform would repaint at display rate for as long as
    /// its host kept `isActive` true.
    private var needsDisplayLink: Bool {
        switch animation {
        case .micLevels, .sweep, .travellingPeak:
            return true
        case .still:
            return false
        }
    }

    private func updateLoopState() {
        if isActive && needsDisplayLink {
            startLoopIfNeeded()
        } else {
            stopLoop()
        }
    }

    private func startLoopIfNeeded() {
        guard displayLink == nil else { return }

        let link = CADisplayLink(target: self, selector: #selector(handleDisplayLink))
        link.add(to: .main, forMode: .common)
        displayLink = link
        lastTickTime = nil
        maxGapSinceHeartbeat = 0
        lastHeartbeatTime = .distantPast

        PersistentLog.log(.waveformAppeared(
            refreshID: renderTick,
            isProcessing: animation.isSelfDriven,
            energyCount: energyLevels.count,
            killedState: false
        ))
    }

    private func stopLoop() {
        guard displayLink != nil else { return }

        displayLink?.invalidate()
        displayLink = nil
        lastTickTime = nil

        PersistentLog.log(.waveformDisappeared(
            refreshID: renderTick,
            renderTick: renderTick
        ))
    }

    @objc
    private func handleDisplayLink(_ link: CADisplayLink) {
        let now = Date()
        let timestamp = link.timestamp
        let previousTimestamp = lastTickTime
        lastTickTime = timestamp

        // The nominal frame duration stands in on the first callback only, which is the
        // one tick with no previous timestamp to measure from. Everywhere else it is
        // the wrong number: it never reports the frames that were missed (#314).
        let elapsed = previousTimestamp.map { timestamp - $0 } ?? link.duration

        if let previousTimestamp {
            let gap = timestamp - previousTimestamp
            maxGapSinceHeartbeat = max(maxGapSinceHeartbeat, gap)

            let gapMs = Int(gap * 1000)
            if gapMs > 500 {
                PersistentLog.log(.waveformStall(
                    gapMs: gapMs,
                    renderTick: renderTick,
                    energyCount: energyLevels.count
                ))
            }
        }

        switch animation {
        case .micLevels:
            tickLevels()
        case .sweep, .travellingPeak:
            processingPhase += ProcessingWaveform.phaseAdvance(for: animation, elapsedSeconds: elapsed)
        case .still:
            break
        }

        if now.timeIntervalSince(lastHeartbeatTime) >= 2.0 {
            let sourceLevels: [Float] = levels(for: animation)
            let avg = sourceLevels.isEmpty ? Float(0) : sourceLevels.reduce(0, +) / Float(sourceLevels.count)
            PersistentLog.log(.waveformHeartbeat(
                renderTick: renderTick,
                avgLevel: avg,
                energyCount: energyLevels.count,
                maxGapMs: Int(maxGapSinceHeartbeat * 1000)
            ))
            maxGapSinceHeartbeat = 0
            lastHeartbeatTime = now
        }

        renderTick += 1
    }

    private func tickLevels() {
        let targets = targetLevels()
        var updated = displayLevels

        for i in 0..<barCount {
            let target = targets[i]
            let current = updated[i]

            if target > current {
                updated[i] = current + (target - current) * smoothingFactor
            } else {
                updated[i] = target + (current - target) * decayFactor
            }

            if updated[i] < 0.005 {
                updated[i] = 0
            }
        }

        displayLevels = updated
    }

    func processingEnergy(at index: Int, phase: Double) -> Float {
        let normalizedIndex = Double(index) / Double(max(barCount - 1, 1))
        let sineValue = sin(2 * .pi * (normalizedIndex + phase))
        return Float(0.2 + 0.25 * (sineValue + 1.0))
    }

    /// The bar heights the current animation is drawing, for the heartbeat log.
    private func levels(for animation: WaveformAnimation) -> [Float] {
        switch animation {
        case .sweep:
            return (0..<barCount).map { processingEnergy(at: $0, phase: processingPhase) }
        case .travellingPeak:
            return ProcessingWaveform.levels(phase: processingPhase)
        case .micLevels, .still:
            return displayLevels
        }
    }

    private func targetLevels() -> [Float] {
        guard !energyLevels.isEmpty else {
            return Array(repeating: Float(0), count: barCount)
        }

        var result = [Float]()
        result.reserveCapacity(barCount)

        for index in 0..<barCount {
            let position = Float(index) / Float(max(barCount - 1, 1))
            let arrayIndex = position * Float(energyLevels.count - 1)
            let lower = Int(arrayIndex)
            let upper = min(lower + 1, energyLevels.count - 1)
            let fraction = arrayIndex - Float(lower)
            let value = energyLevels[lower] * (1 - fraction) + energyLevels[upper] * fraction
            let thresholded = value < 0.05 ? Float(0) : value
            result.append(min(max(thresholded, 0), 1))
        }

        return result
    }
}

/// The waveform fades toward its edges on each recording surface.
public enum DictusWaveformStyle {
    public static func barColor(at index: Int, count: Int, color: Color = .dictusAccent) -> Color {
        let center = Double(count - 1) / 2
        let distance = abs(Double(index) - center) / max(center, 1)
        return color.opacity(1 - distance * 0.62)
    }
}

/// A narrow, tapered waveform driven by microphone levels or processing progress.
public struct BrandWaveform: View {
    /// Array of energy levels (0.0-1.0) for each bar. Count determines bar count.
    public let energyLevels: [Float]

    /// Fixed height of the waveform container. Bars grow within this space.
    public var maxHeight: CGFloat = 80

    /// Which animation the bars draw.
    ///
    /// WHY the two synthetic ones exist at all: after the microphone stops, the
    /// audio engine is idle but the wait is not over, and bars frozen at their last
    /// levels read as a hang. `.sweep` carries continuity from the recording state
    /// through transcription; `.travellingPeak` says the language model is running,
    /// which is a different and much longer wait (#267).
    public var animation: WaveformAnimation = .micLevels

    /// When false, pauses the TimelineView animation schedule (stops CADisplayLink).
    /// WHY: Some hosts need a hard kill switch when the view is still structurally
    /// alive for a moment (for example during keyboard overlay transitions). This
    /// must stop both live recording animation and the processing sine wave.
    public var isActive: Bool = true

    public init(energyLevels: [Float] = [], maxHeight: CGFloat = 80,
                animation: WaveformAnimation = .micLevels, isActive: Bool = true) {
        self.energyLevels = energyLevels
        self.maxHeight = maxHeight
        self.animation = animation
        self.isActive = isActive
    }

    @StateObject private var driver = BrandWaveformDriver()

    /// Number of bars to display.
    private let barCount = 30

    public var body: some View {
        waveformContent
            .onAppear {
                driver.update(
                    energyLevels: energyLevels,
                    animation: animation,
                    isActive: isActive
                )
            }
            .onDisappear {
                driver.forceStop()
            }
            .onChange(of: energyLevels) { _, newLevels in
                driver.update(
                    energyLevels: newLevels,
                    animation: animation,
                    isActive: isActive
                )
            }
            .onChange(of: animation) { _, newValue in
                driver.update(
                    energyLevels: energyLevels,
                    animation: newValue,
                    isActive: isActive
                )
            }
            .onChange(of: isActive) { _, newValue in
                driver.update(
                    energyLevels: energyLevels,
                    animation: animation,
                    isActive: newValue
                )
            }
    }

    // Render all bars in a single Canvas while the display link updates their levels.
    private var waveformContent: some View {
        Canvas { context, size in
            _ = driver.renderTick
            let step = size.width / CGFloat(barCount)
            let barWidth = min(step * 0.46, 3)

            for index in 0..<barCount {
                let energy: Float
                switch driver.animation {
                case .sweep:
                    energy = driver.processingEnergy(at: index, phase: driver.processingPhase)
                case .travellingPeak:
                    energy = ProcessingWaveform.level(
                        at: index,
                        peakPosition: ProcessingWaveform.peakPosition(phase: driver.processingPhase)
                    )
                case .micLevels, .still:
                    energy = index < driver.displayLevels.count ? driver.displayLevels[index] : 0
                }

                let minHeight: CGFloat = driver.animation.isSelfDriven ? 3 : 1.5
                let height = minHeight + CGFloat(energy) * (maxHeight - minHeight)

                let x = CGFloat(index) * step + (step - barWidth) / 2
                let y = (size.height - height) / 2
                let rect = CGRect(x: x, y: y, width: barWidth, height: max(height, 0))
                let path = Path(roundedRect: rect, cornerRadius: barWidth / 2)

                context.fill(path, with: .color(DictusWaveformStyle.barColor(at: index, count: barCount)))
            }
        }
        .frame(height: maxHeight)
    }
}

#Preview("Idle") {
    ZStack {
        Color.dictusBackground.ignoresSafeArea()
        BrandWaveform(energyLevels: Array(repeating: Float(0), count: 30))
    }
}

#Preview("Active") {
    ZStack {
        Color.dictusBackground.ignoresSafeArea()
        BrandWaveform(energyLevels: (0..<30).map { _ in
            Float.random(in: 0.2...0.8)
        })
    }
}

#Preview("Processing") {
    ZStack {
        Color.dictusBackground.ignoresSafeArea()
        BrandWaveform(maxHeight: 120, animation: .sweep)
            .opacity(0.3)
            .padding(.horizontal)
    }
}
#endif
