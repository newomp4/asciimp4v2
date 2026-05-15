import SwiftUI

// ─────────────────────────────────────────────────────────────────────────────
// MARK: – Tracker style presets
// ─────────────────────────────────────────────────────────────────────────────

private struct TrackerStylePreset {
    let name: String
    let icon: String
    let apply: (AppState) -> Void
}

private let trackerPresets: [TrackerStylePreset] = [
    TrackerStylePreset(name: "Sci-Fi", icon: "viewfinder.circle") { s in
        s.trackerEnabled   = true
        s.detectionMode    = .motion
        s.maxClusters      = 4
        s.boxStyle         = .cornerHUD
        s.strokeWidth      = 1.5
        s.showFill         = false
        s.showConnectors   = true
        s.connectorStyle   = .dashed
        s.connectorOpacity = 0.45
        s.showLabels       = true
        s.labelContent     = .id
        s.roundedCorners   = false
        s.boxPadding       = 0.1
        s.sensitivity      = 0.5
    },
    TrackerStylePreset(name: "Glitch", icon: "waveform.path") { s in
        s.trackerEnabled   = true
        s.detectionMode    = .random
        s.maxClusters      = 9
        s.boxStyle         = .rect
        s.strokeWidth      = 1.0
        s.showFill         = true
        s.fillOpacity      = 0.18
        s.fillColor        = .white
        s.showConnectors   = false
        s.showLabels       = false
        s.roundedCorners   = false
        s.boxPadding       = 0.0
        s.sensitivity      = 0.45
    },
    TrackerStylePreset(name: "Data", icon: "chart.bar.doc.horizontal") { s in
        s.trackerEnabled   = true
        s.detectionMode    = .edge
        s.maxClusters      = 6
        s.boxStyle         = .rect
        s.strokeWidth      = 1.0
        s.showFill         = false
        s.showConnectors   = true
        s.connectorStyle   = .solid
        s.connectorOpacity = 0.5
        s.showLabels       = true
        s.labelContent     = .coordinates
        s.roundedCorners   = false
        s.boxPadding       = 0.04
        s.sensitivity      = 0.5
    },
    TrackerStylePreset(name: "Eye", icon: "eye.circle") { s in
        s.trackerEnabled   = true
        s.detectionMode    = .bright
        s.maxClusters      = 3
        s.boxStyle         = .cornerHUD
        s.strokeWidth      = 2.0
        s.showFill         = false
        s.showConnectors   = false
        s.showLabels       = true
        s.labelContent     = .coordinates
        s.roundedCorners   = true
        s.boxPadding       = 0.18
        s.sensitivity      = 0.45
    },
    TrackerStylePreset(name: "Ambient", icon: "cloud") { s in
        s.trackerEnabled   = true
        s.detectionMode    = .random
        s.maxClusters      = 5
        s.boxStyle         = .filled
        s.strokeWidth      = 1.0
        s.showFill         = true
        s.fillOpacity      = 0.12
        s.fillColor        = .white
        s.showConnectors   = false
        s.showLabels       = false
        s.roundedCorners   = true
        s.boxPadding       = 0.25
        s.sensitivity      = 0.65
    },
    TrackerStylePreset(name: "Cinema", icon: "film") { s in
        s.trackerEnabled   = true
        s.detectionMode    = .bright
        s.maxClusters      = 2
        s.boxStyle         = .cornerHUD
        s.strokeWidth      = 2.5
        s.showFill         = true
        s.fillOpacity      = 0.07
        s.fillColor        = .white
        s.showConnectors   = false
        s.showLabels       = false
        s.roundedCorners   = false
        s.boxPadding       = 0.14
        s.sensitivity      = 0.4
    },
]

// ─────────────────────────────────────────────────────────────────────────────
// MARK: – Panel
// ─────────────────────────────────────────────────────────────────────────────

struct TrackerPanel: View {
    @Bindable var state: AppState

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {

                // ── Master toggle ─────────────────────────────────────────────
                HStack {
                    TooltipLabel(text: "Enable Tracker",
                                 tip: "Overlay cluster bounding boxes on the ASCII output")
                    Spacer()
                    Toggle("", isOn: $state.trackerEnabled)
                        .toggleStyle(.switch)
                        .scaleEffect(0.75, anchor: .trailing)
                        .tint(Mono.accent)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Mono.bg2)

                Rectangle().fill(Mono.border).frame(height: 1)

                if state.trackerEnabled {

                    // ── Style presets ─────────────────────────────────────────
                    CollapsibleSection(title: "Presets") {
                        LazyVGrid(
                            columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())],
                            spacing: 6
                        ) {
                            ForEach(trackerPresets, id: \.name) { preset in
                                Button { preset.apply(state) } label: {
                                    VStack(spacing: 4) {
                                        Image(systemName: preset.icon)
                                            .font(.system(size: 13, weight: .light))
                                            .foregroundStyle(Mono.text)
                                        Text(preset.name)
                                            .font(.system(size: 9, design: .monospaced))
                                            .foregroundStyle(Mono.sub)
                                    }
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 46)
                                    .background(Mono.bg2)
                                    .clipShape(RoundedRectangle(cornerRadius: 4))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(10)
                    }

                    // ── Detection ─────────────────────────────────────────────
                    CollapsibleSection(title: "Detection") {
                        VStack(spacing: 0) {
                            VStack(spacing: 4) {
                                TooltipLabel(
                                    text: "Mode",
                                    tip: "Bright/Dark/Edge/Motion cluster on pixel properties. Random & Free place boxes each frame without tracking."
                                )
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 12)

                                MonoSegmented(options: [
                                    ("Bright",  DetectionMode.bright),
                                    ("Dark",    DetectionMode.dark),
                                    ("Edge",    DetectionMode.edge),
                                    ("Motion",  DetectionMode.motion),
                                    ("Random",  DetectionMode.random)
                                ], selection: $state.detectionMode)
                                .padding(.horizontal, 12)
                            }
                            .padding(.vertical, 6)

                            IntSliderRow(
                                label: state.detectionMode == .random ? "Box Count" : "Max Clusters",
                                tip: state.detectionMode == .random
                                    ? "Number of random boxes placed each frame"
                                    : "Max clusters detected (boxes cycle to new positions each frame)",
                                value: $state.maxClusters,
                                range: 1...12
                            )

                            if state.detectionMode == .random {
                                SliderRow(
                                    label: "Size Scale",
                                    tip: "Controls random box size range",
                                    value: $state.sensitivity,
                                    range: 0.05...1.0
                                )
                            } else {
                                SliderRow(
                                    label: "Sensitivity",
                                    tip: "Pixel threshold — boxes cycle between different hot regions each pass",
                                    value: $state.sensitivity,
                                    range: 0...1.0
                                )
                                SliderRow(
                                    label: "Min Area",
                                    tip: "Ignore clusters smaller than this pixel area",
                                    value: $state.minArea,
                                    range: 50...5000,
                                    step: 50,
                                    format: "%.0f"
                                )
                            }
                        }
                    }

                    // ── Bounding Boxes ────────────────────────────────────────
                    CollapsibleSection(title: "Bounding Boxes") {
                        VStack(spacing: 0) {
                            ToggleRow(
                                label: "Show Boxes",
                                tip: "Draw bounding boxes around each detected cluster",
                                value: $state.showBoundingBoxes
                            )
                            if state.showBoundingBoxes {
                                VStack(spacing: 4) {
                                    TooltipLabel(
                                        text: "Style",
                                        tip: "Rect = full outline · Corner = HUD brackets · Filled = soft block · Cross = crosshair marker"
                                    )
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.horizontal, 12)

                                    MonoSegmented(options: [
                                        ("Rect",   BoxStyle.rect),
                                        ("Corner", BoxStyle.cornerHUD),
                                        ("Filled", BoxStyle.filled),
                                        ("Cross",  BoxStyle.crosshair)
                                    ], selection: $state.boxStyle)
                                    .padding(.horizontal, 12)
                                }
                                .padding(.vertical, 4)

                                if state.boxStyle != .filled {
                                    ToggleRow(
                                        label: "Rounded Corners",
                                        tip: "Use rounded corners on the bounding box",
                                        value: $state.roundedCorners
                                    )
                                    SliderRow(
                                        label: "Stroke Width",
                                        tip: "Line thickness of the bounding box",
                                        value: $state.strokeWidth,
                                        range: 0.5...4.0
                                    )
                                }

                                SliderRow(
                                    label: "Box Padding",
                                    tip: "Expand or shrink the box relative to the detected cluster",
                                    value: $state.boxPadding,
                                    range: -0.5...1.5
                                )

                                // Fill controls
                                if state.boxStyle == .filled {
                                    // Filled style: fill IS the box — always show controls
                                    SliderRow(
                                        label: "Opacity",
                                        tip: "Fill opacity",
                                        value: $state.fillOpacity,
                                        range: 0.01...1.0
                                    )
                                    ColorRow(
                                        label: "Color",
                                        tip: "Fill color",
                                        value: $state.fillColor
                                    )
                                    ToggleRow(
                                        label: "Rounded",
                                        tip: "Round the corners of the filled block",
                                        value: $state.roundedCorners
                                    )
                                } else {
                                    ToggleRow(
                                        label: "Show Fill",
                                        tip: "Draw a semi-transparent fill inside the box",
                                        value: $state.showFill
                                    )
                                    if state.showFill {
                                        SliderRow(
                                            label: "Fill Opacity",
                                            tip: "Opacity of the box fill",
                                            value: $state.fillOpacity,
                                            range: 0.01...1.0
                                        )
                                        ColorRow(
                                            label: "Fill Color",
                                            tip: "Color of the box fill",
                                            value: $state.fillColor
                                        )
                                    }
                                }
                            }
                        }
                    }

                    // ── Connectors ────────────────────────────────────────────
                    CollapsibleSection(title: "Connectors") {
                        VStack(spacing: 0) {
                            ToggleRow(
                                label: "Show Connectors",
                                tip: "Draw lines connecting cluster centers",
                                value: $state.showConnectors
                            )
                            if state.showConnectors {
                                VStack(spacing: 4) {
                                    TooltipLabel(
                                        text: "Line Style",
                                        tip: "Connector line dash pattern"
                                    )
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.horizontal, 12)

                                    MonoSegmented(options: [
                                        ("Solid",  LineStyle.solid),
                                        ("Dashed", LineStyle.dashed),
                                        ("Dotted", LineStyle.dotted)
                                    ], selection: $state.connectorStyle)
                                    .padding(.horizontal, 12)
                                }
                                .padding(.vertical, 4)

                                SliderRow(
                                    label: "Opacity",
                                    tip: "Transparency of the connector lines",
                                    value: $state.connectorOpacity,
                                    range: 0...1.0
                                )
                            }
                        }
                    }

                    // ── Labels ────────────────────────────────────────────────
                    CollapsibleSection(title: "Labels") {
                        VStack(spacing: 0) {
                            ToggleRow(
                                label: "Show Labels",
                                tip: "Show text labels on each cluster",
                                value: $state.showLabels
                            )
                            if state.showLabels {
                                VStack(spacing: 4) {
                                    TooltipLabel(
                                        text: "Content",
                                        tip: "What to display in the cluster label"
                                    )
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.horizontal, 12)

                                    MonoSegmented(options: [
                                        ("ID",     LabelContent.id),
                                        ("Coords", LabelContent.coordinates),
                                        ("Area",   LabelContent.area),
                                        ("Conf",   LabelContent.confidence)
                                    ], selection: $state.labelContent)
                                    .padding(.horizontal, 12)
                                }
                                .padding(.vertical, 4)
                            }
                        }
                    }

                    // ── Animation ─────────────────────────────────────────────
                    CollapsibleSection(title: "Animation") {
                        ToggleRow(
                            label: "Scan Line",
                            tip: "Animate a horizontal scan line over the output",
                            value: $state.scanLineAnimation
                        )
                    }
                }

                Spacer(minLength: 16)
            }
        }
    }
}
