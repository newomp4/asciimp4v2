import SwiftUI

struct ColorPanel: View {
    @Bindable var state: AppState

    private let cols = Array(repeating: GridItem(.flexible(), spacing: 4), count: 2)

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                colorModeSection
                paletteSection
                postProcessingSection
                Spacer(minLength: 16)
            }
        }
    }

    // ── Color mode grid ───────────────────────────────────────────────────────

    private var colorModeSection: some View {
        CollapsibleSection(title: "Color Mode") {
            VStack(spacing: 6) {
                LazyVGrid(columns: cols, spacing: 4) {
                    ForEach(ColorMode.allCases, id: \.self) { mode in
                        GridCell(
                            label:    mode.label,
                            selected: mode == state.colorMode
                        ) { state.colorMode = mode }
                        .help(mode.description)
                    }
                }
                .padding(.horizontal, 12)

                Text(state.colorMode.description)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(Mono.dim.opacity(0.8))
                    .padding(.horizontal, 12)
                    .padding(.bottom, 2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.bottom, 4)
        }
    }

    // ── Mode-specific palette options ─────────────────────────────────────────

    @ViewBuilder
    private var paletteSection: some View {
        CollapsibleSection(title: "Palette") {
            VStack(spacing: 0) {
                paletteContent
            }
        }
    }

    @ViewBuilder
    private var paletteContent: some View {
        switch state.colorMode {
        case .mono:
            ColorRow(label: "Color", tip: "Solid color for all characters", value: $state.monoColor)

        case .source:
            modeNote("Samples pixel color from the source frame")

        case .analogous:
            ColorRow(label: "Base Color", tip: "Starting hue for the analogous palette", value: $state.primaryColor)
            SliderRow(label: "Hue Spread", tip: "Angular range of hues (degrees)",
                      value: $state.analogousSpread, range: 5...180, format: "%.0f°")
            IntSliderRow(label: "Count", tip: "Number of steps in the analogous palette",
                         value: $state.analogousCount, range: 2...8)
            ToggleRow(label: "Cycle Animation", tip: "Slowly rotate hue over time",
                      value: $state.cycleAnimation)

        case .hueShift:
            modeNote("Hue rotates over time. Use Hue Shift below to add a fixed offset.")

        case .gradient:
            ColorRow(label: "Top Color",    tip: "Color at the top of the frame",    value: $state.primaryColor)
            ColorRow(label: "Bottom Color", tip: "Color at the bottom of the frame", value: $state.secondaryColor)

        case .neon:
            modeNote("High-saturation hues cycle across the frame over time")

        case .thermal:
            modeNote("Maps luminance to blue (cool) through white (hot)")

        case .glitch:
            modeNote("Random color per cell, updated every frame")
        }
    }

    // ── Post-Processing ───────────────────────────────────────────────────────

    private var postProcessingSection: some View {
        CollapsibleSection(title: "Post-Processing") {
            VStack(spacing: 0) {
                SliderRow(label: "Hue Shift",    tip: "Rotate all output hues (degrees)",
                          value: $state.hueShift,          range: -180...180, format: "%.0f°")
                SliderRow(label: "Saturation",   tip: "Scale output color saturation",
                          value: $state.saturation,         range: 0...2.0)
                SliderRow(label: "Brightness",   tip: "Scale output luminance",
                          value: $state.brightness,         range: 0.1...2.0)
                SliderRow(label: "Source Blend", tip: "Mix the original source frame over the ASCII output",
                          value: $state.sourceOverlayBlend, range: 0...1.0)
            }
        }
    }

    // ── Helper ────────────────────────────────────────────────────────────────

    private func modeNote(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, design: .monospaced))
            .foregroundStyle(Mono.dim)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
