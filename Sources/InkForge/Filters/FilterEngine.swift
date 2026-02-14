import CoreImage
import CoreGraphics

// MARK: - Filter Parameter Descriptor

struct FilterParam {
    let label: String
    let key: String
    let min: Double
    let max: Double
    let defaultValue: Double
}

// MARK: - Filter Type

enum FilterType: String, CaseIterable {
    case invertColors
    case desaturate
    case gaussianBlur
    case motionBlur
    case sharpen
    case noise
    case hueSaturation
    case brightnessContrast
    case posterize
    case pixelate

    var displayName: String {
        switch self {
        case .invertColors:       return "Invert Colors"
        case .desaturate:         return "Desaturate"
        case .gaussianBlur:       return "Gaussian Blur"
        case .motionBlur:         return "Motion Blur"
        case .sharpen:            return "Sharpen"
        case .noise:              return "Noise"
        case .hueSaturation:      return "Hue/Saturation"
        case .brightnessContrast: return "Brightness/Contrast"
        case .posterize:          return "Posterize"
        case .pixelate:           return "Pixelate"
        }
    }

    var isInstant: Bool {
        switch self {
        case .invertColors, .desaturate: return true
        default: return false
        }
    }

    var parameters: [FilterParam] {
        switch self {
        case .invertColors, .desaturate:
            return []
        case .gaussianBlur:
            return [FilterParam(label: "Radius", key: "radius", min: 0, max: 50, defaultValue: 5)]
        case .motionBlur:
            return [
                FilterParam(label: "Radius", key: "radius", min: 0, max: 50, defaultValue: 10),
                FilterParam(label: "Angle", key: "angle", min: 0, max: 360, defaultValue: 0),
            ]
        case .sharpen:
            return [
                FilterParam(label: "Radius", key: "radius", min: 0, max: 10, defaultValue: 2.5),
                FilterParam(label: "Intensity", key: "intensity", min: 0, max: 10, defaultValue: 0.5),
            ]
        case .noise:
            return [FilterParam(label: "Amount", key: "amount", min: 0, max: 1, defaultValue: 0.3)]
        case .hueSaturation:
            return [
                FilterParam(label: "Hue", key: "hue", min: -180, max: 180, defaultValue: 0),
                FilterParam(label: "Saturation", key: "saturation", min: -100, max: 100, defaultValue: 0),
            ]
        case .brightnessContrast:
            return [
                FilterParam(label: "Brightness", key: "brightness", min: -100, max: 100, defaultValue: 0),
                FilterParam(label: "Contrast", key: "contrast", min: -100, max: 100, defaultValue: 0),
            ]
        case .posterize:
            return [FilterParam(label: "Levels", key: "levels", min: 2, max: 32, defaultValue: 6)]
        case .pixelate:
            return [FilterParam(label: "Scale", key: "scale", min: 1, max: 50, defaultValue: 8)]
        }
    }
}

// MARK: - Filter Engine

struct FilterEngine {

    private static let ciContext = CIContext(options: [.useSoftwareRenderer: false])

    /// Apply a filter to a CGImage. Returns nil on failure.
    static func apply(_ filter: FilterType, params: [String: Double],
                      to image: CGImage) -> CGImage? {
        let input = CIImage(cgImage: image)
        guard let output = buildFilterChain(filter, params: params, input: input) else { return nil }

        let extent = CGRect(origin: .zero, size: CGSize(width: image.width, height: image.height))
        let cropped = output.cropped(to: extent)
        return ciContext.createCGImage(cropped, from: extent,
                                       format: .RGBA8,
                                       colorSpace: CGColorSpaceCreateDeviceRGB())
    }

    /// Apply a filter respecting a selection mask. Unselected pixels are unchanged.
    static func applyWithSelection(_ filter: FilterType, params: [String: Double],
                                    to image: CGImage, selection: SelectionMask) -> CGImage? {
        guard let maskImage = selection.makeMaskImage() else {
            return apply(filter, params: params, to: image)
        }

        let input = CIImage(cgImage: image)
        guard let filtered = buildFilterChain(filter, params: params, input: input) else { return nil }

        let extent = CGRect(origin: .zero, size: CGSize(width: image.width, height: image.height))
        let croppedFiltered = filtered.cropped(to: extent)
        let mask = CIImage(cgImage: maskImage)

        // Blend: where mask is white use filtered, where black use original
        guard let blendFilter = CIFilter(name: "CIBlendWithMask") else { return nil }
        blendFilter.setValue(croppedFiltered, forKey: kCIInputImageKey)
        blendFilter.setValue(input, forKey: kCIInputBackgroundImageKey)
        blendFilter.setValue(mask, forKey: kCIInputMaskImageKey)

        guard let blended = blendFilter.outputImage else { return nil }
        return ciContext.createCGImage(blended, from: extent,
                                       format: .RGBA8,
                                       colorSpace: CGColorSpaceCreateDeviceRGB())
    }

    // MARK: - Filter Chain Builder

    private static func buildFilterChain(_ filter: FilterType, params: [String: Double],
                                          input: CIImage) -> CIImage? {
        switch filter {
        case .invertColors:
            return applyInvert(input)
        case .desaturate:
            return applyDesaturate(input)
        case .gaussianBlur:
            return applyGaussianBlur(input, radius: params["radius"] ?? 5)
        case .motionBlur:
            return applyMotionBlur(input, radius: params["radius"] ?? 10,
                                   angle: params["angle"] ?? 0)
        case .sharpen:
            return applySharpen(input, radius: params["radius"] ?? 2.5,
                                intensity: params["intensity"] ?? 0.5)
        case .noise:
            return applyNoise(input, amount: params["amount"] ?? 0.3)
        case .hueSaturation:
            return applyHueSaturation(input, hue: params["hue"] ?? 0,
                                      saturation: params["saturation"] ?? 0)
        case .brightnessContrast:
            return applyBrightnessContrast(input, brightness: params["brightness"] ?? 0,
                                           contrast: params["contrast"] ?? 0)
        case .posterize:
            return applyPosterize(input, levels: params["levels"] ?? 6)
        case .pixelate:
            return applyPixelate(input, scale: params["scale"] ?? 8)
        }
    }

    // MARK: - Individual Filters

    private static func applyInvert(_ input: CIImage) -> CIImage? {
        let f = CIFilter(name: "CIColorInvert")
        f?.setValue(input, forKey: kCIInputImageKey)
        return f?.outputImage
    }

    private static func applyDesaturate(_ input: CIImage) -> CIImage? {
        let f = CIFilter(name: "CIColorControls")
        f?.setValue(input, forKey: kCIInputImageKey)
        f?.setValue(0.0, forKey: kCIInputSaturationKey)
        return f?.outputImage
    }

    private static func applyGaussianBlur(_ input: CIImage, radius: Double) -> CIImage? {
        let clamped = input.clampedToExtent()
        let f = CIFilter(name: "CIGaussianBlur")
        f?.setValue(clamped, forKey: kCIInputImageKey)
        f?.setValue(radius, forKey: kCIInputRadiusKey)
        return f?.outputImage
    }

    private static func applyMotionBlur(_ input: CIImage, radius: Double, angle: Double) -> CIImage? {
        let clamped = input.clampedToExtent()
        let f = CIFilter(name: "CIMotionBlur")
        f?.setValue(clamped, forKey: kCIInputImageKey)
        f?.setValue(radius, forKey: kCIInputRadiusKey)
        f?.setValue(angle * .pi / 180.0, forKey: kCIInputAngleKey) // degrees → radians
        return f?.outputImage
    }

    private static func applySharpen(_ input: CIImage, radius: Double, intensity: Double) -> CIImage? {
        let f = CIFilter(name: "CIUnsharpMask")
        f?.setValue(input, forKey: kCIInputImageKey)
        f?.setValue(radius, forKey: kCIInputRadiusKey)
        f?.setValue(intensity, forKey: kCIInputIntensityKey)
        return f?.outputImage
    }

    private static func applyNoise(_ input: CIImage, amount: Double) -> CIImage? {
        // Generate random noise
        guard let noiseGen = CIFilter(name: "CIRandomGenerator"),
              let noiseImage = noiseGen.outputImage else { return nil }

        // Crop noise to image extent
        let extent = input.extent
        let croppedNoise = noiseImage.cropped(to: extent)

        // Scale noise alpha by amount using CIColorMatrix
        let alphaVector = CIVector(x: 0, y: 0, z: 0, w: CGFloat(amount))
        guard let matrix = CIFilter(name: "CIColorMatrix") else { return nil }
        matrix.setValue(croppedNoise, forKey: kCIInputImageKey)
        matrix.setValue(CIVector(x: 0, y: 0, z: 0, w: 0), forKey: "inputRVector")
        matrix.setValue(CIVector(x: 0, y: 0, z: 0, w: 0), forKey: "inputGVector")
        matrix.setValue(CIVector(x: 0, y: 0, z: 0, w: 0), forKey: "inputBVector")
        matrix.setValue(alphaVector, forKey: "inputAVector")
        matrix.setValue(CIVector(x: CGFloat(amount) * 0.5, y: CGFloat(amount) * 0.5,
                                  z: CGFloat(amount) * 0.5, w: 0), forKey: "inputBiasVector")

        guard let scaledNoise = matrix.outputImage else { return nil }

        // Composite noise over original
        guard let composite = CIFilter(name: "CISourceOverCompositing") else { return nil }
        composite.setValue(scaledNoise, forKey: kCIInputImageKey)
        composite.setValue(input, forKey: kCIInputBackgroundImageKey)
        return composite.outputImage
    }

    private static func applyHueSaturation(_ input: CIImage, hue: Double,
                                            saturation: Double) -> CIImage? {
        var current = input

        // Hue shift (degrees → radians)
        if hue != 0 {
            guard let hueFilter = CIFilter(name: "CIHueAdjust") else { return nil }
            hueFilter.setValue(current, forKey: kCIInputImageKey)
            hueFilter.setValue(hue * .pi / 180.0, forKey: kCIInputAngleKey)
            guard let output = hueFilter.outputImage else { return nil }
            current = output
        }

        // Saturation: UI range -100..100, map to CIFilter range 0..2
        // -100 → 0 (fully desaturated), 0 → 1 (unchanged), 100 → 2 (double saturation)
        let satValue = 1.0 + saturation / 100.0
        if satValue != 1.0 {
            guard let satFilter = CIFilter(name: "CIColorControls") else { return nil }
            satFilter.setValue(current, forKey: kCIInputImageKey)
            satFilter.setValue(satValue, forKey: kCIInputSaturationKey)
            guard let output = satFilter.outputImage else { return nil }
            current = output
        }

        return current
    }

    private static func applyBrightnessContrast(_ input: CIImage, brightness: Double,
                                                 contrast: Double) -> CIImage? {
        // UI range -100..100 → CIFilter range:
        //   brightness: -100..100 → -1..1
        //   contrast: -100..100 → 0..2
        let briValue = brightness / 100.0
        let conValue = 1.0 + contrast / 100.0

        let f = CIFilter(name: "CIColorControls")
        f?.setValue(input, forKey: kCIInputImageKey)
        f?.setValue(briValue, forKey: kCIInputBrightnessKey)
        f?.setValue(conValue, forKey: kCIInputContrastKey)
        return f?.outputImage
    }

    private static func applyPosterize(_ input: CIImage, levels: Double) -> CIImage? {
        let f = CIFilter(name: "CIColorPosterize")
        f?.setValue(input, forKey: kCIInputImageKey)
        f?.setValue(levels, forKey: "inputLevels")
        return f?.outputImage
    }

    private static func applyPixelate(_ input: CIImage, scale: Double) -> CIImage? {
        let f = CIFilter(name: "CIPixellate")
        f?.setValue(input, forKey: kCIInputImageKey)
        f?.setValue(scale, forKey: kCIInputScaleKey)
        // Center at image center
        let center = CIVector(x: input.extent.midX, y: input.extent.midY)
        f?.setValue(center, forKey: kCIInputCenterKey)
        return f?.outputImage
    }
}
