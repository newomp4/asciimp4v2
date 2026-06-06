import SwiftUI

// ─────────────────────────────────────────────────────────────────────────────
// MARK: – Presets
// ─────────────────────────────────────────────────────────────────────────────

private struct HUDPreset {
    let name: String
    let icon: String
    let apply: (AppState) -> Void
}

private let hudPresets: [HUDPreset] = [
    HUDPreset(name: "Night Op", icon: "moon.fill") { s in
        s.hudEnabled = true
        s.hudTintEnabled = true;  s.hudTintColor = Color(red: 0.22, green: 0.90, blue: 0.30); s.hudTintOpacity = 0.09
        s.hudVignetteEnabled = true; s.hudVignetteStrength = 0.55
        s.hudScanLineEnabled = false
        s.hudCompassEnabled = true; s.hudCompassSpeed = 4.0
        s.hudCornerFramesEnabled = true
        s.hudRangeCallouts = true
        s.hudCrosshairEnabled = false
        s.hudReticleRing = false; s.hudMildots = false
        s.hudBDCMarks = false; s.hudWindMarks = false
        s.hudScopeFrame = false
        s.hudDataPane = true
        s.hudNVMode = true; s.hudLevelIndicator = false
    },
    HUDPreset(name: "Sniper", icon: "scope") { s in
        s.hudEnabled = true
        s.hudTintEnabled = true; s.hudTintColor = Color(red: 0.22, green: 0.90, blue: 0.30); s.hudTintOpacity = 0.07
        s.hudVignetteEnabled = true; s.hudVignetteStrength = 0.50
        s.hudScanLineEnabled = false
        s.hudCompassEnabled = true; s.hudCompassSpeed = 2.0
        s.hudCornerFramesEnabled = false
        s.hudRangeCallouts = true
        s.hudCrosshairEnabled = true
        s.hudReticleRing = true; s.hudMildots = true
        s.hudBDCMarks = true; s.hudWindMarks = true
        s.hudScopeFrame = true; s.hudScopeRadius = 0.88
        s.hudDataPane = true
        s.hudNVMode = false; s.hudLevelIndicator = true
        s.hudSweepArc = true; s.hudPulseRings = false
        s.hudBreathPause = true; s.hudStadiaCircles = true
        s.hudElevMarks = true; s.hudAcquisitionBrackets = true
        s.hudOuterBox = true; s.hudOuterBoxSize = 0.38
        s.hudRangeArcs = true; s.hudHorizRef = true
        s.hudAnglemarks = true; s.hudLateralScale = true
        s.hudSignalBars = false; s.hudCrosswindArrow = false
        s.hudTacticalGrid = false
        s.hudRangeTickFrame = true; s.hudPerimeterRing = true
        s.hudThreatDiamond = true; s.hudLockArc = true
    },
    HUDPreset(name: "CQB", icon: "person.fill.viewfinder") { s in
        s.hudEnabled = true
        s.hudTintEnabled = false
        s.hudVignetteEnabled = true; s.hudVignetteStrength = 0.40
        s.hudScanLineEnabled = false
        s.hudCompassEnabled = true; s.hudCompassSpeed = 6.0
        s.hudCornerFramesEnabled = true
        s.hudRangeCallouts = true
        s.hudCrosshairEnabled = true
        s.hudReticleRing = true; s.hudMildots = false
        s.hudBDCMarks = false; s.hudWindMarks = false
        s.hudScopeFrame = false
        s.hudDataPane = false
        s.hudNVMode = false; s.hudLevelIndicator = false
    },
    HUDPreset(name: "Thermal", icon: "flame.fill") { s in
        s.hudEnabled = true
        s.hudTintEnabled = true; s.hudTintColor = Color(red: 1.0, green: 0.45, blue: 0.05); s.hudTintOpacity = 0.08
        s.hudVignetteEnabled = true; s.hudVignetteStrength = 0.50
        s.hudScanLineEnabled = true; s.hudScanSpeed = 0.8
        s.hudCompassEnabled = false
        s.hudCornerFramesEnabled = true
        s.hudRangeCallouts = true
        s.hudCrosshairEnabled = true
        s.hudReticleRing = false; s.hudMildots = false
        s.hudBDCMarks = false; s.hudWindMarks = false
        s.hudScopeFrame = false
        s.hudDataPane = true
        s.hudNVMode = false; s.hudLevelIndicator = false
    },
]

// ─────────────────────────────────────────────────────────────────────────────
// MARK: – Panel
// ─────────────────────────────────────────────────────────────────────────────

struct HUDPanel: View {
    @Bindable var state: AppState

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {

                // ── Master toggle ─────────────────────────────────────────────
                HStack {
                    TooltipLabel(text: "Enable HUD",
                                 tip: "Tactical overlay system — compass, scope frame, reticle, rangefinder, data pane")
                    Spacer()
                    Toggle("", isOn: $state.hudEnabled)
                        .toggleStyle(.switch)
                        .scaleEffect(0.75, anchor: .trailing)
                        .tint(Mono.accent)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Mono.bg2)

                Rectangle().fill(Mono.border).frame(height: 1)

                if state.hudEnabled {

                    // ── Presets ───────────────────────────────────────────────
                    CollapsibleSection(title: "Presets", initiallyExpanded: true) {
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 5) {
                            ForEach(hudPresets, id: \.name) { preset in
                                Button { preset.apply(state) } label: {
                                    VStack(spacing: 4) {
                                        Image(systemName: preset.icon)
                                            .font(.system(size: 12, weight: .light))
                                            .foregroundStyle(Mono.text)
                                        Text(preset.name)
                                            .font(.system(size: 8, design: .monospaced))
                                            .foregroundStyle(Mono.sub)
                                    }
                                    .frame(maxWidth: .infinity).frame(height: 44)
                                    .background(Mono.bg2)
                                    .clipShape(RoundedRectangle(cornerRadius: 4))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(10)
                    }

                    // ── Sizing ────────────────────────────────────────────────
                    CollapsibleSection(title: "Sizing") {
                        VStack(spacing: 0) {
                            SliderRow(label: "Margin",        tip: "Inset all elements from the frame edges — useful to keep HUD off the letterbox bars", value: $state.hudMargin, range: 0.0...0.12, format: "%.3f")
                            SliderRow(label: "Element Scale", tip: "Scale all element sizes up or down — increase for 4K output", value: $state.hudScale, range: 0.5...4.0, format: "%.2f")
                            SliderRow(label: "Stroke Width",  tip: "Line thickness multiplier — increase for 4K so hairlines stay visible", value: $state.hudStrokeWidth, range: 0.3...4.0, format: "%.2f")
                            SliderRow(label: "Text Scale",    tip: "Scale all text labels independently from element size", value: $state.hudTextScale, range: 0.5...3.0, format: "%.2f")
                        }
                    }

                    // ── Optic frame ───────────────────────────────────────────
                    CollapsibleSection(title: "Scope Optic") {
                        VStack(spacing: 0) {
                            ToggleRow(label: "Scope Frame",  tip: "Circular lens boundary — dark outside the scope circle, clear inside", value: $state.hudScopeFrame)
                            if state.hudScopeFrame {
                                SliderRow(label: "Radius",   tip: "Size of the scope circle relative to the frame", value: $state.hudScopeRadius, range: 0.40...0.99, format: "%.2f")
                                SliderRow(label: "Progress", tip: "How far the scope has zoomed in (0=full open, 1=fully closed). Set keyframes on the timeline to animate this.", value: $state.hudScopeProgress, range: 0...1, format: "%.2f")
                            }
                        }
                    }

                    // ── Reticle ───────────────────────────────────────────────
                    CollapsibleSection(title: "Reticle") {
                        VStack(spacing: 0) {
                            ToggleRow(label: "Crosshair",      tip: "Gap crosshair at frame center", value: $state.hudCrosshairEnabled)
                            if state.hudCrosshairEnabled {
                                ToggleRow(label: "Reticle Ring",   tip: "Small circle around crosshair center with quarter ticks", value: $state.hudReticleRing)
                                ToggleRow(label: "Mil-Dots",       tip: "Ranging dots along all four arms", value: $state.hudMildots)
                                ToggleRow(label: "BDC Marks",      tip: "Bullet drop compensator hash marks below center — holdover points for 100–500m", value: $state.hudBDCMarks)
                                ToggleRow(label: "Wind Marks",     tip: "Windage correction dots on the horizontal arm", value: $state.hudWindMarks)
                                ToggleRow(label: "Elevation MOA",  tip: "MOA tick marks along the vertical arm for elevation holds", value: $state.hudElevMarks)
                                ToggleRow(label: "Stadia Circles", tip: "Static ranging reference circles — match to a known-size target to estimate distance", value: $state.hudStadiaCircles)
                            }
                        }
                    }

                    // ── Active elements ───────────────────────────────────────
                    CollapsibleSection(title: "Active Elements") {
                        VStack(spacing: 0) {
                            ToggleRow(label: "Sweep Arc",           tip: "Rotating radar-style arc around the reticle center — continuous scan animation", value: $state.hudSweepArc)
                            ToggleRow(label: "Pulse Rings",         tip: "Rings that expand and fade from center — simulates active IR emission", value: $state.hudPulseRings)
                            ToggleRow(label: "Breathing Pause",     tip: "Shot-timing indicator — shows the breathing cycle with a hold window at the natural exhale pause", value: $state.hudBreathPause)
                            ToggleRow(label: "Acquisition Brackets",tip: "Animated corner brackets that frame each detected target, with a confidence arc", value: $state.hudAcquisitionBrackets)
                        }
                    }

                    // ── Compass ───────────────────────────────────────────────
                    CollapsibleSection(title: "Compass") {
                        VStack(spacing: 0) {
                            ToggleRow(label: "Compass Bar",  tip: "MW-style heading indicator at top with cardinal/degree marks", value: $state.hudCompassEnabled)
                            if state.hudCompassEnabled {
                                SliderRow(label: "Drift Speed", tip: "Bearing animation rate — simulates slow pan", value: $state.hudCompassSpeed, range: 0.5...20.0, format: "%.1f")
                            }
                        }
                    }

                    // ── Mid-Field ─────────────────────────────────────────────
                    CollapsibleSection(title: "Mid-Field") {
                        VStack(spacing: 0) {
                            ToggleRow(label: "Outer Box",          tip: "Corner brackets centered on frame between the reticle and screen edges — defines the engagement zone", value: $state.hudOuterBox)
                            if state.hudOuterBox {
                                SliderRow(label: "Box Size", tip: "Outer box half-size as fraction of frame", value: $state.hudOuterBoxSize, range: 0.18...0.65, format: "%.2f")
                            }
                            ToggleRow(label: "Tick Frame",         tip: "Secondary corner-bracket frame at 55% of outer box size — adds a close-range engagement zone with graduation ticks", value: $state.hudRangeTickFrame)
                            ToggleRow(label: "Azimuth Ring",       tip: "24-tick graduated ring at mid-field radius — cardinal / intercardinal azimuth reference like a compass rose", value: $state.hudPerimeterRing)
                            ToggleRow(label: "Threat Diamonds",    tip: "Small diamond markers at the 4 diagonal positions (45°/135°/225°/315°) — visual threat sector indicators", value: $state.hudThreatDiamond)
                            ToggleRow(label: "Lock Arc",           tip: "8-sector acquisition arc that holds on each sector then steps — simulates active sector scan / target lock", value: $state.hudLockArc)
                            ToggleRow(label: "Range Arcs",         tip: "Partial arcs at multiple radii in the mid-field zone with distance labels — depth layers for ranging", value: $state.hudRangeArcs)
                            ToggleRow(label: "Horiz Reference",    tip: "Long thin horizontal reference lines extending from the reticle out into the mid-field zone with ranging ticks", value: $state.hudHorizRef)
                            ToggleRow(label: "Angle Marks",        tip: "Clock-position tick marks around the reticle — 12 marks at every hour position", value: $state.hudAnglemarks)
                            ToggleRow(label: "Tactical Grid",      tip: "Very subtle full-frame dot grid — like a scope with a mil-dot matrix", value: $state.hudTacticalGrid)
                            ToggleRow(label: "Lateral Scales",     tip: "Vertical ruler bars on both sides at mid-height — MOA/mil elevation reference scales", value: $state.hudLateralScale)
                            ToggleRow(label: "IR Signal Bars",     tip: "IR signal-strength bar graph on the right side — animated, shows simulated sensor return strength", value: $state.hudSignalBars)
                            ToggleRow(label: "Crosswind Arrow",    tip: "Animated wind direction arrow with speed readout — positioned in the left mid-field zone", value: $state.hudCrosswindArrow)
                        }
                    }

                    // ── Rangefinder ───────────────────────────────────────────
                    CollapsibleSection(title: "Rangefinder") {
                        VStack(spacing: 0) {
                            ToggleRow(label: "Range Callouts", tip: "Distance estimate near each tracked target, based on apparent size", value: $state.hudRangeCallouts)
                        }
                    }

                    // ── Tactical data ─────────────────────────────────────────
                    CollapsibleSection(title: "Tactical Data") {
                        VStack(spacing: 0) {
                            ToggleRow(label: "Data Pane",        tip: "Bottom-left readout block — time, altitude, temperature, military grid reference", value: $state.hudDataPane)
                            ToggleRow(label: "NV Mode",          tip: "Night vision indicator — adds GEN-3 tag and enhanced atmospheric look", value: $state.hudNVMode)
                            ToggleRow(label: "Level Indicator",  tip: "Cant/bubble level at frame bottom — shows scope tilt", value: $state.hudLevelIndicator)
                        }
                    }

                    // ── Frame marks ───────────────────────────────────────────
                    CollapsibleSection(title: "Frame") {
                        VStack(spacing: 0) {
                            ToggleRow(label: "Corner Marks",  tip: "Small alignment marks at the four corners", value: $state.hudCornerFramesEnabled)
                        }
                    }

                    // ── Lens ──────────────────────────────────────────────────
                    CollapsibleSection(title: "Lens") {
                        VStack(spacing: 0) {
                            ToggleRow(label: "Vignette",      tip: "Circular dark falloff from edges", value: $state.hudVignetteEnabled)
                            if state.hudVignetteEnabled {
                                SliderRow(label: "Strength", tip: "Edge darkening amount", value: $state.hudVignetteStrength, range: 0.1...1.0)
                            }
                            ToggleRow(label: "Color Tint",    tip: "Color wash over content", value: $state.hudTintEnabled)
                            if state.hudTintEnabled {
                                ColorRow(label: "Color",      tip: "Tint color",    value: $state.hudTintColor)
                                SliderRow(label: "Strength",  tip: "Tint opacity",  value: $state.hudTintOpacity, range: 0.0...0.40)
                            }
                        }
                    }

                    // ── Scan ──────────────────────────────────────────────────
                    CollapsibleSection(title: "Scan", initiallyExpanded: false) {
                        VStack(spacing: 0) {
                            ToggleRow(label: "Scan Line",  tip: "Subtle display persistence sweep — useful for thermal look", value: $state.hudScanLineEnabled)
                            if state.hudScanLineEnabled {
                                SliderRow(label: "Speed",  tip: "Sweep rate", value: $state.hudScanSpeed, range: 0.1...3.0, format: "%.2f")
                            }
                        }
                    }

                }

                Spacer(minLength: 16)
            }
        }
    }
}
