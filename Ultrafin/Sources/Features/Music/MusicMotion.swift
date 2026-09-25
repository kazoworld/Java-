import SwiftUI
#if os(iOS)
import AVFoundation
import MediaPlayer
#endif

// The small moving parts that make the music side feel alive: the backdrop
// that breathes with the record, the sliders that stretch under a thumb, the
// title that scrolls when it's too long to read, and the bars that dance beside
// whatever's playing. Every one of them stands still under Reduce Motion.

// MARK: - Living backdrop

/// The player's backdrop: the cover melted into a 3×3 mesh of its own colours,
/// drifting slowly while the music plays and holding still when it stops.
///
/// Each mesh point takes the colour of the matching ninth of the artwork, so
/// the field is shaped like the record rather than tinted by an average of it.
/// Colours are toned into a band white text always reads on, and a new record
/// cross-fades in over the old one instead of cutting.
struct LivingBackdrop: View {
    /// Nine colours, row-major from the top left (``ImageColor/palette(from:)``).
    let palette: [ArtworkColor]
    /// The single sampled colour, used to build a field while the palette is
    /// still on its way (or couldn't be read).
    var fallback: ArtworkColor?
    /// Drift only while music plays. Paused, the field freezes where it is.
    var isAnimating: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !isAnimating || reduceMotion)) { context in
            let t = reduceMotion ? 0 : context.date.timeIntervalSinceReferenceDate
            ZStack {
                MeshGradient(width: 3, height: 3,
                             points: Self.points(at: t),
                             colors: colors)
                    // Identity follows the record, so a track change is an
                    // insertion and removal — which is what lets it cross-fade.
                    .id(colors.description)
                    .transition(.opacity)
            }
            .animation(.easeInOut(duration: 1.1), value: colors.description)
        }
        .overlay {
            // Settle darker behind the controls and lift faintly under the art.
            LinearGradient(stops: [
                .init(color: .white.opacity(0.04), location: 0),
                .init(color: .clear, location: 0.4),
                .init(color: .black.opacity(0.28), location: 1)
            ], startPoint: .top, endPoint: .bottom)
        }
        .background(UltrafinColors.background)
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }

    private var colors: [Color] {
        if palette.count == 9 {
            return palette.map { $0.toned(floor: 0.14, ceiling: 0.52, saturation: 1.15) }
        }
        guard let base = fallback else {
            return Array(repeating: UltrafinColors.background, count: 9)
        }
        // One colour spun into nine: hue nudged either way, darker toward the
        // bottom, so even a single sample reads as a field rather than a fill.
        return (0 ..< 9).map { i in
            let row = Double(i / 3), column = Double(i % 3)
            return base.shade(brightness: 0.62 - row * 0.1,
                              saturation: 0.6,
                              hue: (column - 1) * 0.025)
        }
    }

    /// Corners pinned, edge points sliding along their edges, the centre free —
    /// so the mesh never tears away from the screen's edge as it moves.
    private static func points(at t: Double) -> [SIMD2<Float>] {
        func wave(_ speed: Double, _ phase: Double, _ amount: Double) -> Float {
            Float(sin(t * speed + phase) * amount)
        }
        // Built point by point: one big literal of SIMD arithmetic is the kind
        // of expression the type checker gives up on.
        var points: [SIMD2<Float>] = []
        points.reserveCapacity(9)
        points.append(SIMD2<Float>(0, 0))
        points.append(SIMD2<Float>(0.5 + wave(0.19, 0, 0.16), 0))
        points.append(SIMD2<Float>(1, 0))
        points.append(SIMD2<Float>(0, 0.5 + wave(0.23, 1.3, 0.14)))
        points.append(SIMD2<Float>(0.5 + wave(0.17, 2.1, 0.18), 0.5 + wave(0.21, 0.4, 0.16)))
        points.append(SIMD2<Float>(1, 0.5 + wave(0.15, 3.2, 0.14)))
        points.append(SIMD2<Float>(0, 1))
        points.append(SIMD2<Float>(0.5 + wave(0.13, 4.4, 0.16), 1))
        points.append(SIMD2<Float>(1, 1))
        return points
    }
}

// MARK: - Now-playing bars

/// The little dancing equalizer that marks the song that's playing — four bars
/// moving out of step while it plays, settling into a still silhouette on
/// pause. Under Reduce Motion it's always the still one.
struct NowPlayingBars: View {
    var isPlaying: Bool
    var color: Color = .white
    var height: CGFloat = 14

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let speeds: [Double] = [5.1, 6.7, 4.3, 7.9]
    private static let phases: [Double] = [0, 1.7, 3.1, 0.8]
    private static let resting: [CGFloat] = [0.35, 0.7, 0.5, 0.25]

    var body: some View {
        let moving = isPlaying && !reduceMotion
        TimelineView(.animation(minimumInterval: 1.0 / 24, paused: !moving)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            HStack(alignment: .bottom, spacing: barWidth * 0.7) {
                ForEach(0 ..< 4, id: \.self) { i in
                    Capsule()
                        .fill(color)
                        .frame(width: barWidth, height: height * level(i, t: t, moving: moving))
                }
            }
            .frame(height: height, alignment: .bottom)
            .animation(.smooth(duration: 0.35), value: moving)
        }
        .accessibilityElement()
        .accessibilityLabel(isPlaying ? "Now playing" : "Paused")
    }

    private var barWidth: CGFloat { max(2, height * 0.17) }

    private func level(_ i: Int, t: Double, moving: Bool) -> CGFloat {
        guard moving else { return Self.resting[i] }
        // Two sines at unrelated speeds, so no bar ever settles into a visible
        // loop.
        let a = sin(t * Self.speeds[i] + Self.phases[i])
        let b = sin(t * Self.speeds[(i + 2) % 4] * 0.61 + Self.phases[i] * 2)
        return CGFloat(0.22 + 0.78 * abs(a * 0.65 + b * 0.35))
    }
}

// MARK: - Marquee

/// A one-line label that, when it's too long for its space, waits a beat and
/// then glides sideways to show the rest — Apple Music's treatment of a long
/// song title on the player. Fits in its space? It's just text. Reduce Motion?
/// It truncates like any other label.
struct MarqueeText: View {
    let text: String
    let font: Font
    var color: Color = .white
    /// Space between the end of the text and its next pass.
    var gap: CGFloat = 44
    /// Points per second.
    var speed: CGFloat = 32
    var pause: Double = 2.6

    @State private var textWidth: CGFloat = 0
    @State private var boxWidth: CGFloat = 0
    @State private var offset: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var overflows: Bool { boxWidth > 0 && textWidth > boxWidth + 1 }
    private var scrolls: Bool { overflows && !reduceMotion }

    var body: some View {
        // The sizing copy: one truncating line that takes the width it's
        // offered, and so gives the row its height without ever widening it.
        label
            .truncationMode(.tail)
            .opacity(scrolls ? 0 : 1)
            // No flexible frame: a short title stays its own width, so a badge
            // beside it sits right after the words rather than at the far end.
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { boxWidth = $0 }
            .overlay(alignment: .leading) {
                if scrolls {
                    HStack(spacing: gap) {
                        label.fixedSize()
                        label.fixedSize()
                    }
                    .offset(x: offset)
                    .frame(width: boxWidth, alignment: .leading)
                    .mask(edgeFade)
                }
            }
            .background(alignment: .leading) {
                // Measures the text's natural width, off to the side where it
                // can't affect anyone's layout.
                label.fixedSize().hidden()
                    .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { textWidth = $0 }
            }
            .task(id: "\(text)|\(Int(textWidth))|\(Int(boxWidth))|\(reduceMotion)") {
                await run()
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(text)
    }

    private var label: some View {
        Text(text).font(font).foregroundStyle(color).lineLimit(1)
    }

    /// Soft edges so the text slides in and out of view instead of being cut.
    private var edgeFade: some View {
        LinearGradient(stops: [
            .init(color: .clear, location: 0),
            .init(color: .black, location: 0.04),
            .init(color: .black, location: 0.9),
            .init(color: .clear, location: 1)
        ], startPoint: .leading, endPoint: .trailing)
    }

    private func run() async {
        var reset = Transaction()
        reset.disablesAnimations = true
        withTransaction(reset) { offset = 0 }
        guard scrolls else { return }
        let distance = textWidth + gap
        let duration = Double(distance / speed)
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(pause))
            guard !Task.isCancelled else { return }
            withAnimation(.linear(duration: duration)) { offset = -distance }
            try? await Task.sleep(for: .seconds(duration))
            guard !Task.isCancelled else { return }
            // The second copy now sits exactly where the first began, so the
            // jump back is invisible.
            withTransaction(reset) { offset = 0 }
        }
    }
}

// MARK: - Interlude

/// Three dots that fill one by one across an instrumental gap in the lyrics,
/// breathing while they wait — so a long intro or solo reads as "the words are
/// coming", not as the lyrics having stalled.
struct InterludeDots: View {
    /// 0...1 through the gap.
    var progress: Double
    var isActive: Bool
    var size: CGFloat = 14

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var breath: CGFloat {
        guard isActive, !reduceMotion else { return 1 }
        return CGFloat(1 + 0.08 * sin(progress * Double.pi * 10))
    }

    var body: some View {
        HStack(spacing: size * 0.7) {
            ForEach(0 ..< 3, id: \.self) { i in
                let fill = min(1, max(0, progress * 3 - Double(i)))
                Circle()
                    .fill(.white.opacity(0.28 + 0.72 * fill))
                    .frame(width: size, height: size)
            }
        }
        .scaleEffect(breath, anchor: .leading)
        // As the gap closes the dots shrink away, handing the stage back to the
        // words.
        .scaleEffect(isActive && progress > 0.94 ? 0.6 : 1, anchor: .leading)
        .opacity(isActive ? 1 : 0.35)
        .animation(.smooth(duration: 0.3), value: isActive)
        .accessibilityLabel("Instrumental")
    }
}

// MARK: - Transport press

#if os(iOS)
/// Apple Music's transport press: the glyph gives a little under your thumb and
/// a soft disc blooms behind it, then both spring back.
struct TransportButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background {
                Circle()
                    .fill(.white.opacity(configuration.isPressed ? 0.16 : 0))
                    .scaleEffect(configuration.isPressed ? 1.05 : 0.6)
            }
            .scaleEffect(configuration.isPressed ? 0.86 : 1)
            .animation(.spring(duration: 0.32, bounce: 0.45), value: configuration.isPressed)
    }
}

// MARK: - Elastic slider

/// The Apple Music slider: a thin, thumbless bar that thickens under your
/// finger, moves *relative* to where you touched (so grabbing it never jumps
/// the playhead), and stretches like elastic when you drag past either end,
/// snapping back with a spring when you let go.
struct ElasticSlider: View {
    /// The value to show while nobody's touching it, 0...1.
    let value: Double
    @Binding var isEditing: Bool
    var restingHeight: CGFloat = 7
    var activeHeight: CGFloat = 13
    var tint: Color = .white
    /// Live, while dragging.
    var onChange: (Double) -> Void = { _ in }
    /// Once, when the finger lifts.
    var onCommit: (Double) -> Void = { _ in }

    @State private var startValue: Double = 0
    @State private var liveValue: Double?
    /// How far past an end the finger has pulled, in points (signed).
    @State private var overshoot: CGFloat = 0

    var body: some View {
        GeometryReader { geo in
            let width = max(1, geo.size.width)
            let stretch = Self.rubberBand(overshoot, limit: 16)
            let trackWidth = width + abs(stretch)
            let shown = min(1, max(0, liveValue ?? value))
            // A stretched band gets thinner, the way a real one would.
            let squeeze = 1 - min(0.35, abs(stretch) / 60)
            let height = (isEditing ? activeHeight : restingHeight) * squeeze

            ZStack(alignment: .leading) {
                Capsule().fill(tint.opacity(0.22))
                Capsule()
                    .fill(tint.opacity(isEditing ? 1 : 0.82))
                    .frame(width: trackWidth * shown)
            }
            .frame(width: trackWidth, height: height)
            .offset(x: stretch < 0 ? stretch : 0)
            .frame(width: width, height: geo.size.height, alignment: .leading)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        if liveValue == nil {
                            startValue = value
                            liveValue = value
                            withAnimation(.spring(duration: 0.3, bounce: 0.3)) { isEditing = true }
                        }
                        let raw = startValue + Double(drag.translation.width / width)
                        let clamped = min(1, max(0, raw))
                        if clamped != liveValue, clamped == 0 || clamped == 1 {
                            Haptics.play(.soft)
                        }
                        overshoot = raw < 0 ? CGFloat(raw) * width
                            : raw > 1 ? CGFloat(raw - 1) * width : 0
                        liveValue = clamped
                        onChange(clamped)
                    }
                    .onEnded { _ in
                        onCommit(liveValue ?? value)
                        liveValue = nil
                        withAnimation(.spring(duration: 0.5, bounce: 0.4)) {
                            overshoot = 0
                            isEditing = false
                        }
                    }
            )
        }
    }

    /// Resistance that grows the further you pull: the first few points come
    /// easily, and it never gives more than `limit`.
    static func rubberBand(_ x: CGFloat, limit: CGFloat) -> CGFloat {
        guard x != 0 else { return 0 }
        let magnitude = limit * (1 - 1 / (abs(x) / limit * 0.55 + 1))
        return x < 0 ? -magnitude : magnitude
    }
}

// MARK: - System volume

/// Device output volume, readable and settable from SwiftUI.
///
/// Reads come straight off the audio session. Writes go through the slider
/// inside a practically-invisible `MPVolumeView` — still the only way an app can
/// move the system volume — and having that view on screen also tells iOS the
/// app is showing its own volume control, so the hardware buttons move the
/// player's slider instead of throwing the system HUD over the artwork.
@Observable
@MainActor
final class SystemVolume {
    static let shared = SystemVolume()

    private(set) var level: Double
    @ObservationIgnored private var observation: NSKeyValueObservation?
    @ObservationIgnored private weak var slider: UISlider?
    /// While a finger is on our slider, the session's own reports lag behind
    /// and would tug the bar backwards.
    @ObservationIgnored private var ignoreReportsUntil: Date = .distantPast

    private init() {
        level = Double(AVAudioSession.sharedInstance().outputVolume)
        observation = AVAudioSession.sharedInstance().observe(\.outputVolume, options: [.new]) { session, _ in
            let volume = Double(session.outputVolume)
            Task { @MainActor in SystemVolume.shared.receive(volume) }
        }
    }

    private func receive(_ volume: Double) {
        guard Date.now > ignoreReportsUntil else { return }
        level = volume
    }

    func set(_ value: Double) {
        level = value
        ignoreReportsUntil = .now.addingTimeInterval(0.4)
        slider?.setValue(Float(value), animated: false)
        slider?.sendActions(for: .valueChanged)
    }

    fileprivate func attach(_ view: MPVolumeView) {
        func find(_ root: UIView) -> UISlider? {
            for sub in root.subviews {
                if let s = sub as? UISlider { return s }
                if let s = find(sub) { return s }
            }
            return nil
        }
        slider = find(view)
    }
}

/// Hosts the hidden `MPVolumeView` that ``SystemVolume`` drives. Put one in the
/// hierarchy wherever the custom volume slider is shown.
struct SystemVolumeBridge: UIViewRepresentable {
    func makeUIView(context: Context) -> MPVolumeView {
        let view = MPVolumeView(frame: CGRect(x: 0, y: 0, width: 120, height: 30))
        // Not zero — a fully transparent view counts as absent and the system
        // HUD comes back.
        view.alpha = 0.0001
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ uiView: MPVolumeView, context: Context) {
        // The slider is built lazily; look for it once the view is laid out.
        Task { @MainActor in SystemVolume.shared.attach(uiView) }
    }
}
#endif
