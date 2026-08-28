import SwiftUI
import CoreMedia
import Kadr

/// The kinds of transition kadr can insert, as a value you can enumerate.
///
/// ``Kadr/Transition`` carries associated values — a duration, and for slide a
/// direction — so it cannot be `CaseIterable`. This is the menu-shaped view of
/// it, in the same spirit as ``Kadr/FilterKind``.
///
/// Added in v0.19.
public enum TransitionKind: String, Sendable, Equatable, Hashable, CaseIterable, Identifiable {
    case fade
    case dissolve
    case slide

    public var id: String { rawValue }

    /// An English name, for menus. ``rawValue`` is a stable key a localised app
    /// can look up instead.
    public var displayName: String {
        switch self {
        case .fade:     return "Fade"
        case .dissolve: return "Dissolve"
        case .slide:    return "Slide"
        }
    }

    /// Whether this kind needs a direction. Only ``slide`` does.
    public var needsDirection: Bool { self == .slide }

    /// Build a transition of this kind.
    ///
    /// `direction` is ignored except by ``slide``.
    public func transition(duration: CMTime, direction: SlideDirection = .fromLeft) -> Kadr.Transition {
        switch self {
        case .fade:     return .fade(duration: duration)
        case .dissolve: return .dissolve(duration: duration)
        case .slide:    return .slide(direction: direction, duration: duration)
        }
    }

    /// Which kind an existing transition is.
    ///
    /// Exhaustive over ``Kadr/Transition``, so a new transition case fails the
    /// build here until it is classified.
    public static func kind(of transition: Kadr.Transition) -> TransitionKind {
        switch transition {
        case .fade:     return .fade
        case .dissolve: return .dissolve
        case .slide:    return .slide
        }
    }
}

/// Menu-shaped view of ``Kadr/SlideDirection``.
///
/// A local mirror rather than an extension on kadr's type, deliberately.
/// `SlideDirection` is not `Hashable` upstream and a SwiftUI `Picker` selection
/// must be — but adding a *retroactive* conformance to another module's type is
/// a trap: the day kadr declares its own, the two collide, and a duplicate
/// conformance is a runtime hazard rather than a compile error across module
/// boundaries. A mirror costs four lines and cannot break that way.
///
/// Added in v0.19.
public enum SlideDirectionOption: String, Sendable, Equatable, Hashable, CaseIterable, Identifiable {
    case fromLeft
    case fromRight
    case fromTop
    case fromBottom

    public var id: String { rawValue }

    /// An English name, for menus. ``rawValue`` is a stable key a localised app
    /// can look up instead.
    public var displayName: String {
        switch self {
        case .fromLeft:   return "From Left"
        case .fromRight:  return "From Right"
        case .fromTop:    return "From Top"
        case .fromBottom: return "From Bottom"
        }
    }

    /// The kadr value this option stands for.
    public var direction: SlideDirection {
        switch self {
        case .fromLeft:   return .fromLeft
        case .fromRight:  return .fromRight
        case .fromTop:    return .fromTop
        case .fromBottom: return .fromBottom
        }
    }

    /// The option matching a kadr direction. Exhaustive, so a new direction
    /// upstream fails the build here.
    public init(_ direction: SlideDirection) {
        switch direction {
        case .fromLeft:   self = .fromLeft
        case .fromRight:  self = .fromRight
        case .fromTop:    self = .fromTop
        case .fromBottom: self = .fromBottom
        }
    }
}

/// Pick a transition — kind, duration, and direction — and hand it back.
///
/// The engine has had `.fade`, `.dissolve` and `.slide` since v0.2, and no view
/// package offered a way to author one: every consumer building an editor wrote
/// the same picker. Like the rest of KadrUI this view mutates nothing. It emits
/// a fully-formed ``Kadr/Transition`` and the consumer rebuilds.
///
/// ```swift
/// TransitionPicker(initial: existing) { transition in
///     insert(transition, after: selectedClipID)
/// }
/// ```
///
/// **Duration bounds.** `0.1...4` seconds by default. kadr overlaps a transition
/// into its neighbours, so a transition longer than either adjacent clip is not
/// meaningful — pass `durationRange` to clamp it to what the actual neighbours
/// allow.
///
/// Added in v0.19.
public struct TransitionPicker: View {

    @Environment(\.kadrAppearance) private var appearance

    @State private var kind: TransitionKind
    @State private var seconds: Double
    @State private var direction: SlideDirectionOption

    private let durationRange: ClosedRange<Double>
    private let onChange: (Kadr.Transition) -> Void

    /// Create a transition picker.
    /// - Parameters:
    ///   - initial: An existing transition to edit. `nil` starts on a 0.5 s fade.
    ///   - durationRange: Selectable duration in seconds. Defaults to `0.1...4`.
    ///   - onChange: Fires on every edit with the resulting transition. The
    ///     consumer inserts or replaces it in the composition.
    public init(
        initial: Kadr.Transition? = nil,
        durationRange: ClosedRange<Double> = 0.1...4,
        onChange: @escaping (Kadr.Transition) -> Void
    ) {
        let resolvedKind = initial.map(TransitionKind.kind(of:)) ?? .fade
        _kind = State(initialValue: resolvedKind)
        _seconds = State(initialValue: initial?.duration.seconds ?? 0.5)
        _direction = State(initialValue: TransitionPicker.direction(of: initial).map(SlideDirectionOption.init) ?? .fromLeft)
        self.durationRange = durationRange
        self.onChange = onChange
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("Transition", selection: $kind) {
                ForEach(TransitionKind.allCases) { kind in
                    Text(kind.displayName).tag(kind)
                }
            }
            .pickerStyle(.segmented)
            .onChange(of: kind) { _, _ in emit() }
            .accessibilityLabel("Transition style")

            if kind.needsDirection {
                Picker("Direction", selection: $direction) {
                    ForEach(SlideDirectionOption.allCases) { option in
                        Text(option.displayName).tag(option)
                    }
                }
                .onChange(of: direction) { _, _ in emit() }
                .accessibilityLabel("Slide direction")
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Duration \(seconds, specifier: "%.2f")s")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Slider(value: $seconds, in: durationRange) { editing in
                    if !editing { emit() }
                }
                .accessibilityLabel("Transition duration")
                .accessibilityValue("\(String(format: "%.2f", seconds)) seconds")
            }
        }
    }

    private func emit() {
        onChange(kind.transition(
            duration: CMTime(seconds: seconds, preferredTimescale: 600),
            direction: direction.direction
        ))
    }

    /// The direction of a transition, or `nil` when its kind has none.
    nonisolated static func direction(of transition: Kadr.Transition?) -> SlideDirection? {
        guard case let .slide(direction, _) = transition else { return nil }
        return direction
    }
}
