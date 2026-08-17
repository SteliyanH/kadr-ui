import SwiftUI

/// v0.13.0 — the package's appearance surface.
///
/// KadrUI draws the editor's timeline, keyframe tracks, inspectors and preview.
/// Until this type existed, every colour, radius, stroke and font in those views
/// was hardcoded, so a consumer with its own design system could restyle the
/// screens it drew itself and nothing else — the editor came out half-migrated.
/// `.tint` was the only channel in.
///
/// **Every default here reproduces the pre-0.13 rendering verbatim.** The
/// environment default is ``system``, so a consumer that does nothing sees no
/// change. That is deliberate and load-bearing: the package's snapshot baselines
/// are the proof, and they were not re-recorded when this landed.
///
/// Set it once, near the root of the editor:
///
/// ```swift
/// TimelineView(video, currentTime: $time)
///     .kadrAppearance(.system)   // or your own
/// ```
///
/// Appearance is ambient rather than per-view arguments because `TimelineView`
/// already takes fourteen initialiser parameters; a dozen styling arguments
/// across nine public views would be unusable and would churn every call site.
/// SwiftUI puts `.tint`, `.font` and `.foregroundStyle` in the environment for
/// the same reason.
public struct KadrAppearance: Equatable, Sendable {

    /// How clip content — filmstrip thumbnails, image cells — is rendered.
    ///
    /// This is a *rendering* choice rather than a colour, which is why it is an
    /// enum: the package decides where in its pipeline to apply it. Mono design
    /// systems want ``grayscale`` so footage stops competing with the accent.
    public enum ContentRendering: Equatable, Sendable {
        /// Footage renders in its own colour. The pre-0.13 behaviour.
        case color
        /// Footage is desaturated as it is drawn.
        case grayscale
    }

    /// Shape of the marks on a keyframe track.
    public enum KeyframeMarkShape: Equatable, Sendable {
        /// The pre-0.13 shape.
        case circle
        /// A square turned 45°, which reads as authored-value in most editors.
        case diamond
    }

    /// Fills for timeline cells, keyed by what the cell holds.
    ///
    /// Named fields rather than a `(any Clip) -> Color` closure: a closure is
    /// neither `Equatable` nor `Sendable`, so it would prevent the appearance
    /// from participating in SwiftUI's equality checks and would leak across
    /// isolation boundaries.
    public struct ClipColors: Equatable, Sendable {
        public var video: Color
        public var image: Color
        public var title: Color
        public var transition: Color
        public var audio: Color

        public init(
            video: Color,
            image: Color,
            title: Color,
            transition: Color,
            audio: Color
        ) {
            self.video = video
            self.image = image
            self.title = title
            self.transition = transition
            self.audio = audio
        }

        /// The pre-0.13 hues, verbatim.
        public static let system = ClipColors(
            video: .blue,
            image: .green,
            title: .orange,
            transition: .gray,
            audio: .purple
        )

        /// One fill for every kind — what a mono scheme wants, where the cell's
        /// content and label carry the meaning instead of its hue.
        public static func uniform(_ color: Color) -> ClipColors {
            ClipColors(
                video: color,
                image: color,
                title: color,
                transition: color,
                audio: color
            )
        }
    }

    // MARK: - Geometry

    /// Corner radius for clip cells, keyframe tracks and overlay selection.
    /// Pre-0.13: `4`. Set `0` for a square system.
    public var cornerRadius: CGFloat

    /// Corner radius for lane grounds and the audio cell, which sat tighter than
    /// clip cells. Pre-0.13: `2`. Separate knob because collapsing it into
    /// ``cornerRadius`` would have changed rendering for anyone using defaults.
    public var laneCornerRadius: CGFloat

    /// Width of selection rings and control outlines. Pre-0.13: `2`.
    public var strokeWidth: CGFloat

    /// Shadow radius applied while dragging a clip. Pre-0.13: `6`.
    /// Set `0` to disable — flat systems have no ambient shadow.
    public var elevation: CGFloat

    // MARK: - Timeline

    /// The playhead line and its scrub-strip marker. Pre-0.13: `.red`.
    public var playhead: Color

    /// Ring drawn around a selected clip or overlay. Pre-0.13: `.white`.
    public var selectionRing: Color

    /// Ground behind keyframe and speed-curve tracks.
    /// Pre-0.13: `.gray` at 20% opacity.
    public var trackBackground: Color

    /// Ground behind each timeline lane, distinguishing adjacent lanes.
    /// Pre-0.13: `.gray` at 8% opacity.
    public var laneBackground: Color

    /// Fill shown where a thumbnail has not loaded yet.
    /// Pre-0.13: `.gray` at 20% opacity.
    public var placeholder: Color

    /// The audio lane's waveform and cell fill.
    /// Pre-0.13: `.purple` (drawn at 50% / 60% opacity by the lane).
    public var waveform: Color

    /// Ground for the overlay lane. `nil` keeps the pre-0.13 behaviour of
    /// tinting each cell by its ``ClipColors`` kind.
    public var overlayLaneFill: Color?

    /// Fill for keyframe marks. Pre-0.13: `.white`.
    public var keyframeMark: Color

    /// Shape of a keyframe mark. Pre-0.13: ``KeyframeMarkShape/circle``.
    public var keyframeMarkShape: KeyframeMarkShape

    /// The playhead line drawn through a keyframe or speed-curve track. Distinct
    /// from ``playhead``, which is the timeline's own. Pre-0.13: white at 40%.
    public var trackPlayhead: Color

    /// Fills for timeline cells, by kind.
    public var clipColors: ClipColors

    /// Whether footage renders in colour or grayscale.
    public var clipContentRendering: ContentRendering

    // MARK: - Type
    //
    // Six roles rather than one `labelFont`, because the pre-0.13 sites used
    // four different system styles. Collapsing them would have changed
    // rendering, which is exactly what this type promises not to do.

    /// Clip name inside a timeline cell, and the timeline's own lane labels.
    /// Pre-0.13: `.caption2`.
    public var clipLabelFont: Font

    /// Durations, timecodes and tick readouts. Should be tabular — digits that
    /// change width make a running timecode jitter. Pre-0.13: `.caption2.monospaced()`.
    public var timecodeFont: Font

    /// Row labels down a keyframe or speed-curve track. Pre-0.13: `.caption`.
    /// Distinct from ``clipLabelFont`` because the two sat at different sizes.
    public var trackLabelFont: Font

    /// Inspector and editor panel titles. Pre-0.13: `.headline`.
    public var panelTitleFont: Font

    /// Section headers within a panel. Pre-0.13: `.subheadline`.
    public var panelSectionFont: Font

    /// Numeric readouts beside a panel control. Pre-0.13: `.caption.monospacedDigit()`.
    public var panelValueFont: Font

    public init(
        cornerRadius: CGFloat = 4,
        laneCornerRadius: CGFloat = 2,
        strokeWidth: CGFloat = 2,
        elevation: CGFloat = 6,
        playhead: Color = .red,
        selectionRing: Color = .white,
        trackBackground: Color = .gray.opacity(0.2),
        laneBackground: Color = .gray.opacity(0.08),
        placeholder: Color = .gray.opacity(0.2),
        waveform: Color = .purple,
        overlayLaneFill: Color? = nil,
        keyframeMark: Color = .white,
        keyframeMarkShape: KeyframeMarkShape = .circle,
        trackPlayhead: Color = .white.opacity(0.4),
        clipColors: ClipColors = .system,
        clipContentRendering: ContentRendering = .color,
        clipLabelFont: Font = .caption2,
        timecodeFont: Font = .caption2.monospaced(),
        trackLabelFont: Font = .caption,
        panelTitleFont: Font = .headline,
        panelSectionFont: Font = .subheadline,
        panelValueFont: Font = .caption.monospacedDigit()
    ) {
        self.cornerRadius = cornerRadius
        self.laneCornerRadius = laneCornerRadius
        self.strokeWidth = strokeWidth
        self.elevation = elevation
        self.playhead = playhead
        self.selectionRing = selectionRing
        self.trackBackground = trackBackground
        self.laneBackground = laneBackground
        self.placeholder = placeholder
        self.waveform = waveform
        self.overlayLaneFill = overlayLaneFill
        self.keyframeMark = keyframeMark
        self.keyframeMarkShape = keyframeMarkShape
        self.trackPlayhead = trackPlayhead
        self.clipColors = clipColors
        self.clipContentRendering = clipContentRendering
        self.clipLabelFont = clipLabelFont
        self.timecodeFont = timecodeFont
        self.trackLabelFont = trackLabelFont
        self.panelTitleFont = panelTitleFont
        self.panelSectionFont = panelSectionFont
        self.panelValueFont = panelValueFont
    }

    /// The rendering KadrUI shipped before 0.13.0, exactly. The environment
    /// default, so existing consumers are unaffected by this feature.
    public static let system = KadrAppearance()
}

// MARK: - Environment

private struct KadrAppearanceKey: EnvironmentKey {
    static let defaultValue = KadrAppearance.system
}

public extension EnvironmentValues {
    /// The appearance KadrUI's views draw with. Defaults to ``KadrAppearance/system``.
    var kadrAppearance: KadrAppearance {
        get { self[KadrAppearanceKey.self] }
        set { self[KadrAppearanceKey.self] = newValue }
    }
}

public extension View {
    /// Sets the appearance for every KadrUI view in this subtree.
    ///
    /// Set it once at the editor's root; all of KadrUI's views read it from the
    /// environment.
    func kadrAppearance(_ appearance: KadrAppearance) -> some View {
        environment(\.kadrAppearance, appearance)
    }
}

// MARK: - Internal helpers

extension KadrAppearance {

    /// Fill for a lane item, by kind. Callers apply their own opacity, as they
    /// did when these were literals.
    func color(for kind: ItemKind) -> Color {
        switch kind {
        case .video: return clipColors.video
        case .image: return clipColors.image
        case .title: return clipColors.title
        case .transition: return clipColors.transition
        case .audio: return clipColors.audio
        }
    }
}

extension View {
    /// Applies ``KadrAppearance/ContentRendering`` to footage.
    ///
    /// `contrast(1.08)` accompanies desaturation because removing colour flattens
    /// apparent separation between adjacent frames; the nudge restores it. This
    /// matches what consumers apply to the thumbnails they render themselves, so
    /// a filmstrip and a project thumbnail of the same footage agree.
    @ViewBuilder
    func kadrContentRendering(_ rendering: KadrAppearance.ContentRendering) -> some View {
        switch rendering {
        case .color:
            self
        case .grayscale:
            grayscale(1).contrast(1.08)
        }
    }
}

/// Draws a keyframe mark in the shape the appearance asks for.
///
/// A diamond is a square turned 45°, not a separate path — so it keeps the
/// mark's hit area and centring identical to the circle it replaces.
struct KeyframeMark: View {
    let shape: KadrAppearance.KeyframeMarkShape
    let color: Color
    let size: CGFloat

    var body: some View {
        Group {
            switch shape {
            case .circle:
                Circle().fill(color)
            case .diamond:
                Rectangle().fill(color).rotationEffect(.degrees(45))
            }
        }
        .frame(width: size, height: size)
    }
}
