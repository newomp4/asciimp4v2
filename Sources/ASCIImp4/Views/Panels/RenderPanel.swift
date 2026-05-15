import SwiftUI

struct RenderPanel: View {
    @Bindable var state: AppState

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {

                // ── Character Set ─────────────────────────────────────────────
                CollapsibleSection(title: "Character Set") {
                    VStack(spacing: 6) {
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 4) {
                            ForEach(CharacterSetType.allCases, id: \.self) { cs in
                                GridCell(
                                    label: cs.rawValue,
                                    selected: cs == state.characterSetType
                                ) { state.characterSetType = cs }
                            }
                        }
                        .padding(.horizontal, 12)

                        if state.characterSetType == .custom {
                            VStack(spacing: 4) {
                                HStack {
                                    TooltipLabel(
                                        text: "Characters",
                                        tip: "Enter the characters to use, ordered dense→sparse"
                                    )
                                    Spacer()
                                }
                                .padding(.horizontal, 12)
                                TextField("@#S%?*+;:,. ", text: $state.customChars)
                                    .font(.system(size: 11, design: .monospaced))
                                    .padding(7)
                                    .background(Mono.bg0)
                                    .overlay(RoundedRectangle(cornerRadius: Mono.cornerR).stroke(Mono.border.opacity(0.7)))
                                    .clipShape(RoundedRectangle(cornerRadius: Mono.cornerR))
                                    .padding(.horizontal, 12)
                            }
                            .padding(.bottom, 2)
                        }
                    }
                    .padding(.bottom, 4)
                }

                // ── Cell Size ─────────────────────────────────────────────────
                CollapsibleSection(title: "Cell Size") {
                    VStack(spacing: 0) {
                        IntSliderRow(
                            label: "Cell Size",
                            tip: "Width of each character cell in pixels",
                            value: $state.cellSize,
                            range: 2...48
                        )
                        ToggleRow(
                            label: "Dynamic Scaling",
                            tip: "Vary cell size based on local luminance (smaller cells in bright areas)",
                            value: $state.dynamicScaling
                        )
                        if state.dynamicScaling {
                            IntSliderRow(
                                label: "Min Size",
                                tip: "Minimum cell size when dynamic scaling is active",
                                value: $state.minCellSize,
                                range: 2...state.cellSize
                            )
                            IntSliderRow(
                                label: "Max Size",
                                tip: "Maximum cell size when dynamic scaling is active",
                                value: $state.maxCellSize,
                                range: state.cellSize...64
                            )
                        }
                    }
                }

                // ── Image Controls ────────────────────────────────────────────
                CollapsibleSection(title: "Image Controls") {
                    VStack(spacing: 0) {
                        SliderRow(
                            label: "Luma Threshold",
                            tip: "Pixels below this luminance will be treated as fully dark (space)",
                            value: $state.lumaThreshold,
                            range: 0...0.95
                        )
                        SliderRow(
                            label: "Contrast",
                            tip: "Amplify luminance differences between cells",
                            value: $state.contrast,
                            range: 0.1...3.0
                        )
                        SliderRow(
                            label: "Gamma",
                            tip: "Gamma correction applied before character mapping (<1 = brighter)",
                            value: $state.gamma,
                            range: 0.2...3.0
                        )
                        SliderRow(
                            label: "Alpha Threshold",
                            tip: "Pixels with alpha below this value are skipped (transparent gaps)",
                            value: $state.alphaThreshold,
                            range: 0...1.0
                        )
                        ToggleRow(
                            label: "Invert Luminance",
                            tip: "Swap dark↔light mapping — useful for light-on-dark vs dark-on-light",
                            value: $state.invertLuma
                        )
                    }
                }

                Spacer(minLength: 16)
            }
        }
    }
}

