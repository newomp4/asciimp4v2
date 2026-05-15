# ASCIImp4

Real-time ASCII art renderer for videos, images, and After Effects rotoscope layers.  
GPU-accelerated via Metal. Monochrome UI. Runs live at 60fps.

---

## Build (Xcode)

1. Open Xcode → **File › Open** → select `Package.swift`
2. Xcode resolves the package and creates a scheme automatically
3. Select the `ASCIImp4` scheme, target **My Mac**
4. **Product › Run** (⌘R)

**Requirements:** macOS 14 Sonoma+, Xcode 15+

---

## Usage

### Loading media
- **Drag & drop** a video file, image, or folder of PNG frames onto the preview
- **⌘O** to use the file browser

### After Effects Bridge
1. Enable **AE Bridge** in the bottom-left toggle
2. Click **Watch…** and choose (or create) an output folder
3. Click **Export .jsx** — this writes `aeExport.jsx` into that folder and opens it in Finder
4. In After Effects: **File › Scripts › Run Script File** → select `aeExport.jsx`
5. The script renders the active comp's frames as numbered PNGs (with alpha) into the folder
6. ASCIImp4 detects new frames and plays them back in real time

> For rotoscope/roto layers with transparency: pre-comp the roto layer alone,
> make it the active comp, then run the script. Frames export with straight alpha.

---

## Controls

### Render tab
| Control | Effect |
|---|---|
| Character Set | 8 sets: Standard, Numbers, Binary, Letters, Symbols, Blocks, Hex, Custom |
| Cell Size | Width of each character cell in pixels (height = 2×) |
| Dynamic Scaling | Vary cell size by luminance (bright areas = smaller cells) |
| Luma Threshold | Discard pixels below this luminance |
| Contrast | Amplify luminance spread |
| Gamma | Gamma curve applied before character mapping |
| Alpha Threshold | Skip semi-transparent pixels below this value |
| Invert Luminance | Swap bright↔dark mapping |

### Color tab
8 modes: Mono, Source, Analogous, Hue Shift, Gradient, Neon, Thermal, Glitch

Post-processing (always applied on top):
- **Hue Shift**: rotate all output hues by a fixed amount
- **Saturation** / **Brightness**: scale output color properties
- **Source Overlay**: blend original frame over ASCII output at chosen opacity

### Tracker tab
Pixel cluster detector using k-means. Modes: Bright, Dark, Edge, Motion.

Overlay options: corner-bracket HUD boxes, dashed connectors between clusters,
numeric labels (ID / coordinates / area / confidence), animated scan line.

### Presets tab
8 built-in presets. Save your current settings, import/export JSON.

---

## Architecture

```
Sources/ASCIImp4/
├── Rendering/
│   ├── ASCII.metal          – GPU shader: luma→char mapping, 8 color modes, post-FX
│   ├── GlyphAtlas.swift     – Core Text → Metal texture glyph atlas
│   └── MetalRenderer.swift  – MTKViewDelegate, uniforms, scan-line pass
├── Processing/
│   ├── VideoProcessor.swift – AVFoundation playback + CVDisplayLink frame pump
│   └── TrackerProcessor.swift – K-means cluster detection (CPU)
├── AEBridge/
│   └── AEBridge.swift       – Folder watcher + companion .jsx generator
├── Presets/
│   └── PresetManager.swift  – JSON save/load + NSOpenPanel export
└── Views/                   – SwiftUI panels and MTKView wrapper
```

### Metal pipeline
1. Source frame (CVPixelBuffer or CGImage) → MTLTexture
2. Fragment shader samples source texture at each cell center → luminance → char index
3. Char index → UV into glyph atlas texture → per-pixel glyph alpha
4. Color mode applied per-cell, post-processing applied globally
5. Optional second pass: scan-line overlay via off-screen texture

---

## Notes

- Metal shader file (`ASCII.metal`) is compiled at build time into `default.metallib` by Xcode automatically — no manual step needed
- The glyph atlas is rebuilt whenever cell size or character set changes
- The tracker downscales to 256px max dimension for performance
- AE Bridge polls the watch folder every 250ms for new frames
