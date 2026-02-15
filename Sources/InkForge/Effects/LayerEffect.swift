import CoreGraphics

enum StrokePosition {
    case outside
    case center
    case inside
}

struct DropShadowEffect {
    var offsetX: CGFloat = 4
    var offsetY: CGFloat = 4
    var blurRadius: CGFloat = 8
    var color: CGColor = CGColor(red: 0, green: 0, blue: 0, alpha: 1)
    var opacity: CGFloat = 0.6
}

struct StrokeEffect {
    var width: CGFloat = 3
    var color: CGColor = CGColor(red: 0, green: 0, blue: 0, alpha: 1)
    var opacity: CGFloat = 1.0
    var position: StrokePosition = .outside
}

struct OuterGlowEffect {
    var blurRadius: CGFloat = 10
    var color: CGColor = CGColor(red: 1, green: 1, blue: 1, alpha: 1)
    var opacity: CGFloat = 0.75
}

struct InnerShadowEffect {
    var offsetX: CGFloat = 2
    var offsetY: CGFloat = 2
    var blurRadius: CGFloat = 5
    var color: CGColor = CGColor(red: 0, green: 0, blue: 0, alpha: 1)
    var opacity: CGFloat = 0.5
}

struct LayerEffects {
    var dropShadow: DropShadowEffect?
    var stroke: StrokeEffect?
    var outerGlow: OuterGlowEffect?
    var innerShadow: InnerShadowEffect?

    var hasAny: Bool {
        dropShadow != nil || stroke != nil || outerGlow != nil || innerShadow != nil
    }
}
