import Foundation
import CoreGraphics

struct BrushPreset {
    var name: String
    var type: BrushType
    var maxRadius: CGFloat
    var minRadiusFraction: CGFloat
    var opacity: CGFloat
    var flow: CGFloat
    var hardness: CGFloat
    var spacing: CGFloat
    var tiltInfluence: CGFloat
    var streamLine: CGFloat
    var pressureCurve: PressureCurve
    var nibAngle: CGFloat = 0.52        // fixed chisel angle for marker (~30 deg)
    var scatter: CGFloat = 1.0          // spray scatter radius multiplier
    var particleDensity: Int = 30       // spray particles per dab
    var grainIntensity: CGFloat = 0.6   // pencil noise amount (0=smooth, 1=max grain)

    // Texture tip properties
    var tipType: BrushTipType = .circle
    var tipRotation: TipRotation = .fixed
    var sizeJitter: CGFloat = 0        // 0-1, random size variation per dab
    var rotationJitter: CGFloat = 0    // 0-1, random rotation per dab (fraction of pi)
    var tipFlipX: Bool = false         // randomly flip tip horizontally
    var tipFlipY: Bool = false         // randomly flip tip vertically

    enum BrushTipType: String, CaseIterable, Hashable {
        case circle         // existing procedural circle (fillEllipse)
        case dryBrush       // horizontal bristle streaks with gaps
        case charcoal       // gaussian blob with heavy noise
        case inkSplatter    // solid with irregular edges
        case grunge         // random splotches and noise
        case flatBristle    // rectangular with rough edges
        case crosshatch     // cross-hatched pattern
    }

    enum TipRotation: String {
        case fixed              // no rotation
        case followDirection    // rotates to match stroke direction
        case random             // random rotation per dab
        case tiltAzimuth        // follows tablet tilt direction
    }

    enum BrushType: String {
        case round
        case calligraphy
        case airbrush
        case eraser
        case pencil
        case spray
        case marker
        case softRound
    }

    enum PressureCurve: String {
        case linear
        case easeIn
        case easeOut
        case sCurve
    }

    func adjustedPressure(_ raw: CGFloat) -> CGFloat {
        let p = raw.clamped(to: 0...1)
        switch pressureCurve {
        case .linear:  return p
        case .easeIn:  return p * p
        case .easeOut: return 1 - (1 - p) * (1 - p)
        case .sCurve:  return p * p * (3 - 2 * p)
        }
    }

    func radiusForPressure(_ pressure: CGFloat) -> CGFloat {
        let p = adjustedPressure(pressure)
        return maxRadius * (minRadiusFraction + (1 - minRadiusFraction) * p)
    }

    static let defaultRound = BrushPreset(
        name: "Round",
        type: .round,
        maxRadius: 12,
        minRadiusFraction: 0.1,
        opacity: 1.0,
        flow: 1.0,
        hardness: 0.8,
        spacing: 0.15,
        tiltInfluence: 0.0,
        streamLine: 0.5,
        pressureCurve: .linear
    )

    static let defaultCalligraphy = BrushPreset(
        name: "Calligraphy",
        type: .calligraphy,
        maxRadius: 16,
        minRadiusFraction: 0.15,
        opacity: 1.0,
        flow: 1.0,
        hardness: 1.0,
        spacing: 0.08,
        tiltInfluence: 0.8,
        streamLine: 0.5,
        pressureCurve: .linear
    )

    static let defaultAirbrush = BrushPreset(
        name: "Airbrush",
        type: .airbrush,
        maxRadius: 30,
        minRadiusFraction: 0.2,
        opacity: 0.6,
        flow: 0.3,
        hardness: 0.0,
        spacing: 0.05,
        tiltInfluence: 0.0,
        streamLine: 0.3,
        pressureCurve: .easeOut
    )

    static let defaultEraser = BrushPreset(
        name: "Eraser",
        type: .eraser,
        maxRadius: 20,
        minRadiusFraction: 0.3,
        opacity: 1.0,
        flow: 1.0,
        hardness: 0.9,
        spacing: 0.1,
        tiltInfluence: 0.0,
        streamLine: 0.3,
        pressureCurve: .linear
    )

    static let defaultSpray = BrushPreset(
        name: "Spray",
        type: .spray,
        maxRadius: 40,
        minRadiusFraction: 0.3,
        opacity: 0.8,
        flow: 0.5,
        hardness: 1.0,
        spacing: 0.1,
        tiltInfluence: 0.0,
        streamLine: 0.2,
        pressureCurve: .linear,
        scatter: 1.0,
        particleDensity: 30
    )

    static let defaultMarker = BrushPreset(
        name: "Marker",
        type: .marker,
        maxRadius: 14,
        minRadiusFraction: 0.6,
        opacity: 0.4,
        flow: 0.6,
        hardness: 0.9,
        spacing: 0.06,
        tiltInfluence: 0.0,
        streamLine: 0.4,
        pressureCurve: .easeOut,
        nibAngle: 0.52
    )

    static let defaultPencil = BrushPreset(
        name: "Pencil",
        type: .pencil,
        maxRadius: 6,
        minRadiusFraction: 0.2,
        opacity: 0.5,
        flow: 0.4,
        hardness: 0.7,
        spacing: 0.06,
        tiltInfluence: 0.3,
        streamLine: 0.3,
        pressureCurve: .easeIn,
        grainIntensity: 0.6
    )

    static let defaultSoftRound = BrushPreset(
        name: "Soft Round",
        type: .softRound,
        maxRadius: 20,
        minRadiusFraction: 0.15,
        opacity: 0.3,
        flow: 0.4,
        hardness: 0.0,
        spacing: 0.12,
        tiltInfluence: 0.0,
        streamLine: 0.5,
        pressureCurve: .sCurve
    )

    // MARK: - Texture Brush Presets

    static let defaultDryBrush = BrushPreset(
        name: "Dry Brush", type: .round, maxRadius: 18, minRadiusFraction: 0.15,
        opacity: 0.8, flow: 0.7, hardness: 1.0, spacing: 0.12,
        tiltInfluence: 0.0, streamLine: 0.3, pressureCurve: .easeIn,
        tipType: .dryBrush, tipRotation: .followDirection, sizeJitter: 0.1
    )

    static let defaultCharcoal = BrushPreset(
        name: "Charcoal", type: .round, maxRadius: 14, minRadiusFraction: 0.2,
        opacity: 0.6, flow: 0.5, hardness: 0.5, spacing: 0.1,
        tiltInfluence: 0.4, streamLine: 0.4, pressureCurve: .easeIn,
        tipType: .charcoal, tipRotation: .random, sizeJitter: 0.15, rotationJitter: 0.3
    )

    static let defaultInkSplatter = BrushPreset(
        name: "Ink", type: .round, maxRadius: 10, minRadiusFraction: 0.1,
        opacity: 1.0, flow: 1.0, hardness: 1.0, spacing: 0.08,
        tiltInfluence: 0.0, streamLine: 0.5, pressureCurve: .linear,
        tipType: .inkSplatter, tipRotation: .random, rotationJitter: 0.2
    )

    static let defaultGrunge = BrushPreset(
        name: "Grunge", type: .round, maxRadius: 24, minRadiusFraction: 0.3,
        opacity: 0.7, flow: 0.6, hardness: 1.0, spacing: 0.15,
        tiltInfluence: 0.0, streamLine: 0.2, pressureCurve: .linear,
        tipType: .grunge, tipRotation: .random, sizeJitter: 0.2, rotationJitter: 1.0,
        tipFlipX: true, tipFlipY: true
    )

    static let defaultFlatBristle = BrushPreset(
        name: "Flat Bristle", type: .round, maxRadius: 16, minRadiusFraction: 0.4,
        opacity: 0.9, flow: 0.8, hardness: 1.0, spacing: 0.1,
        tiltInfluence: 0.0, streamLine: 0.4, pressureCurve: .linear,
        tipType: .flatBristle, tipRotation: .followDirection, sizeJitter: 0.05
    )

    static let defaultCrosshatch = BrushPreset(
        name: "Crosshatch", type: .round, maxRadius: 12, minRadiusFraction: 0.2,
        opacity: 0.5, flow: 0.4, hardness: 1.0, spacing: 0.1,
        tiltInfluence: 0.0, streamLine: 0.3, pressureCurve: .easeIn,
        tipType: .crosshatch, tipRotation: .random, rotationJitter: 0.5
    )
}
