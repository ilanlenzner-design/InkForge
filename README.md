# InkForge

A native macOS drawing app built entirely in Swift with AppKit. No Electron, no web views — just fast, GPU-backed bitmap rendering with Wacom tablet support.

## Features

### Drawing Tools
- **Pen** with pressure sensitivity (Wacom tablets supported)
- **Pencil**, **Marker**, **Spray**, **Soft Round** brush presets
- **Smudge** tool for blending
- **Eraser** with pressure support
- **Fill** (flood fill with tolerance)
- **Eyedropper** color picker
- **Text** tool with font/size/color options

### Texture Brushes
- 6 procedural brush tip textures: Round, Dry Brush, Ink, Charcoal, Stipple, Noise
- Per-brush jitter controls (size, opacity, angle)
- Tip rotation modes: Fixed, Random, Direction-based
- Visual brush picker with live stroke previews

### Layer System
- Unlimited layers with visibility, opacity, and lock
- 12 blend modes (Normal, Multiply, Screen, Overlay, Soft Light, Hard Light, Color Dodge, Color Burn, Darken, Lighten, Difference, Exclusion)
- Alpha Lock (preserve transparency while painting)
- Clipping Masks (clip layer to base layer alpha)
- Reference Layer for fill tool boundary detection
- Drag to reorder layers

### Selection & Transform
- Rectangle, Ellipse, Lasso, and Magic Wand selection modes
- Add (Shift) and Subtract (Option) selection modifiers
- Marching ants animation on selection boundary
- Transform tool: Move, Scale (with Shift for aspect ratio lock)
- QuickShape detection — hold at end of stroke to snap to line/ellipse/rectangle

### AI Integration
- **Generate**: Create images from text prompts
- **Style Transfer**: Apply artistic styles to your artwork
- **Inpaint**: Edit selected regions with AI (select area, describe what to fill)
- **Describe**: Get AI descriptions of your artwork
- Supports Gemini and Replicate API providers
- Configurable API keys via Settings sheet

### Color System
- HSB color wheel with hue/saturation/brightness sliders
- Hex color input
- Color history swatches (recent colors)

### Export
- PNG, JPEG, TIFF export
- Configurable canvas size and DPI (New Canvas dialog with presets)

### UI
- Procreate-inspired dark theme with neumorphic controls
- Compact top toolbar with tool toggles
- Vertical brush size & opacity sliders (left sidebar)
- Layer panel with color picker (right sidebar)
- Zoom slider with fit-to-screen
- Full keyboard shortcut coverage

## Keyboard Shortcuts

| Key | Tool |
|-----|------|
| B | Pen |
| S | Smudge |
| E | Eraser |
| G | Fill |
| I | Eyedropper |
| T | Text |
| M | Selection |
| V | Transform |
| H | Pan |
| Z | Zoom |
| F | Dry Brush tip |
| J | Ink tip |
| R | Charcoal tip |
| Space | Pan (hold) |

| Shortcut | Action |
|----------|--------|
| Cmd+N | New Canvas |
| Cmd+Z | Undo |
| Cmd+Shift+Z | Redo |
| Cmd+A | Select All |
| Cmd+D | Deselect |
| Cmd+Shift+I | Invert Selection |
| Cmd+Shift+A | AI Edit |
| Cmd+E | Export |
| [ / ] | Brush size down/up |

## Building

Requires macOS 13+ and Swift 5.9+.

```bash
# Debug build
swift build

# Run
.build/debug/InkForge

# Release build + .dmg installer
./scripts/build-dmg.sh
```

The `build-dmg.sh` script produces `InkForge.dmg` with the app bundle — open it and drag to Applications.

## Project Structure

```
Sources/InkForge/
  App/           — AppDelegate, MainWindowController
  AI/            — AIProvider protocol, Gemini + Replicate providers
  Brushes/       — BrushPreset, tip generator, tip cache
  Canvas/        — CanvasModel, CanvasView, SelectionMask, StrokeRenderer
  Drawing/       — StrokePoint, interpolation, smoothing, shape detection
  Export/        — ExportManager (PNG/JPEG/TIFF)
  Filters/       — FilterEngine (CIFilter wrappers)
  History/       — Undo/redo snapshots
  Layers/        — Layer, LayerStack, TextContent
  Tools/         — All tool implementations
  UI/            — Toolbar, panels, popovers, sheets, theme
  Utilities/     — Geometry helpers
  Wacom/         — Tablet pressure driver
```

## Requirements

- macOS 13 Ventura or later
- Apple Silicon or Intel Mac
- Optional: Wacom tablet for pressure sensitivity
- Optional: Gemini / Replicate API keys for AI features

## License

MIT
