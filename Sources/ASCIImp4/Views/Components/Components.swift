import SwiftUI

// ─────────────────────────────────────────────────────────────────────────────
// MARK: – Theme
// ─────────────────────────────────────────────────────────────────────────────

enum Mono {
    // Surfaces
    static let bg0    = Color(white: 0.05)   // window / deepest
    static let bg1    = Color(white: 0.09)   // panel body
    static let bg2    = Color(white: 0.13)   // raised / input
    static let bg3    = Color(white: 0.18)   // hover
    static let bg4    = Color(white: 0.22)   // pressed / selected bg

    // Text
    static let muted  = Color(white: 0.30)   // hairline borders
    static let border = Color(white: 0.22)
    static let dim    = Color(white: 0.38)   // placeholder / secondary
    static let sub    = Color(white: 0.52)   // values, hints
    static let text   = Color(white: 0.84)   // body text
    static let accent = Color(white: 1.00)   // white / primary action

    static let cornerR: CGFloat = 4
    static let panelW:  CGFloat = 280
    static let rowH:    CGFloat = 32
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: – Tooltip label
// ─────────────────────────────────────────────────────────────────────────────

struct TooltipLabel: View {
    let text: String
    let tip:  String

    var body: some View {
        HStack(spacing: 5) {
            Text(text)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Mono.text)
            Image(systemName: "questionmark.circle")
                .font(.system(size: 9))
                .foregroundStyle(Mono.dim)
                .help(tip)
        }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: – Collapsible section
// ─────────────────────────────────────────────────────────────────────────────

struct CollapsibleSection<Content: View>: View {
    let title: String
    @State private var expanded = true
    @State private var hovered  = false
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 0) {

            // ── Header ────────────────────────────────────────────────────────
            Button {
                withAnimation(.spring(response: 0.2, dampingFraction: 0.8)) {
                    expanded.toggle()
                }
            } label: {
                HStack(spacing: 0) {
                    // Left accent line
                    Rectangle()
                        .fill(expanded ? Mono.accent.opacity(0.55) : Color.clear)
                        .frame(width: 2)
                        .animation(.easeInOut(duration: 0.18), value: expanded)

                    HStack(spacing: 8) {
                        Text(title)
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .foregroundStyle(hovered ? Mono.text : Mono.sub)
                            .tracking(0.4)
                            .animation(.easeOut(duration: 0.12), value: hovered)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(expanded ? Mono.sub : Mono.dim)
                            .rotationEffect(.degrees(expanded ? 90 : 0))
                            .animation(.spring(response: 0.2, dampingFraction: 0.8), value: expanded)
                    }
                    .padding(.leading, 10)
                    .padding(.trailing, 12)
                }
                .frame(height: 30)
                .background(hovered ? Mono.bg2.opacity(0.6) : Mono.bg0.opacity(0.6))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { hovered = $0 }
            .animation(.easeOut(duration: 0.1), value: hovered)

            // ── Content ───────────────────────────────────────────────────────
            if expanded {
                content
                    .padding(.bottom, 4)
            }

            // ── Separator ─────────────────────────────────────────────────────
            Rectangle()
                .fill(Mono.muted.opacity(0.8))
                .frame(height: 1)
        }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: – Slider row
// ─────────────────────────────────────────────────────────────────────────────

struct SliderRow: View {
    let label:  String
    let tip:    String
    @Binding var value: Float
    let range:  ClosedRange<Float>
    var step:   Float? = nil
    var format: String = "%.2f"

    @State private var hovered = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                TooltipLabel(text: label, tip: tip)
                Spacer()
                Text(String(format: format, value))
                    .font(.system(size: 10, design: .monospaced).monospacedDigit())
                    .foregroundStyle(Mono.sub)
                    .frame(width: 46, alignment: .trailing)
            }
            .padding(.horizontal, 12)
            .padding(.top, 6)

            Slider(
                value: $value,
                in: range,
                step: step ?? ((range.upperBound - range.lowerBound) / 200)
            )
            .tint(Mono.accent)
            .padding(.horizontal, 12)
            .padding(.bottom, 4)
        }
        .background(hovered ? Mono.bg2.opacity(0.35) : Color.clear)
        .animation(.easeOut(duration: 0.1), value: hovered)
        .onHover { hovered = $0 }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: – Integer slider row
// ─────────────────────────────────────────────────────────────────────────────

struct IntSliderRow: View {
    let label:  String
    let tip:    String
    @Binding var value: Int
    let range:  ClosedRange<Int>

    @State private var hovered = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                TooltipLabel(text: label, tip: tip)
                Spacer()
                Text("\(value)")
                    .font(.system(size: 10, design: .monospaced).monospacedDigit())
                    .foregroundStyle(Mono.sub)
                    .frame(width: 30, alignment: .trailing)
            }
            .padding(.horizontal, 12)
            .padding(.top, 6)

            Slider(value: Binding(
                get: { Double(value) },
                set: { value = Int($0.rounded()) }
            ), in: Double(range.lowerBound)...Double(range.upperBound), step: 1)
            .tint(Mono.accent)
            .padding(.horizontal, 12)
            .padding(.bottom, 4)
        }
        .background(hovered ? Mono.bg2.opacity(0.35) : Color.clear)
        .animation(.easeOut(duration: 0.1), value: hovered)
        .onHover { hovered = $0 }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: – Toggle row
// ─────────────────────────────────────────────────────────────────────────────

struct ToggleRow: View {
    let label: String
    let tip:   String
    @Binding var value: Bool

    @State private var hovered = false

    var body: some View {
        HStack {
            TooltipLabel(text: label, tip: tip)
            Spacer()
            Toggle("", isOn: $value)
                .toggleStyle(.switch)
                .scaleEffect(0.68, anchor: .trailing)
                .tint(Mono.accent)
        }
        .padding(.horizontal, 12)
        .frame(height: Mono.rowH)
        .background(hovered ? Mono.bg2.opacity(0.35) : Color.clear)
        .animation(.easeOut(duration: 0.1), value: hovered)
        .onHover { hovered = $0 }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: – Picker row
// ─────────────────────────────────────────────────────────────────────────────

struct PickerRow<T: Hashable & RawRepresentable>: View where T.RawValue == String {
    let label:   String
    let tip:     String
    @Binding var value: T
    let options: [T]

    @State private var hovered = false

    var body: some View {
        HStack {
            TooltipLabel(text: label, tip: tip)
            Spacer()
            Picker("", selection: $value) {
                ForEach(options, id: \.self) { opt in
                    Text(opt.rawValue).tag(opt)
                }
            }
            .labelsHidden()
            .frame(width: 120)
        }
        .padding(.horizontal, 12)
        .frame(height: Mono.rowH)
        .background(hovered ? Mono.bg2.opacity(0.35) : Color.clear)
        .animation(.easeOut(duration: 0.1), value: hovered)
        .onHover { hovered = $0 }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: – Color row
// ─────────────────────────────────────────────────────────────────────────────

struct ColorRow: View {
    let label: String
    let tip:   String
    @Binding var value: Color

    @State private var hovered = false

    var body: some View {
        HStack {
            TooltipLabel(text: label, tip: tip)
            Spacer()
            ColorPicker("", selection: $value, supportsOpacity: false)
                .labelsHidden()
                .frame(width: 32, height: 22)
        }
        .padding(.horizontal, 12)
        .frame(height: Mono.rowH)
        .background(hovered ? Mono.bg2.opacity(0.35) : Color.clear)
        .animation(.easeOut(duration: 0.1), value: hovered)
        .onHover { hovered = $0 }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: – Mono button
// ─────────────────────────────────────────────────────────────────────────────

struct MonoButton: View {
    let label:  String
    var small:  Bool = false
    let action: () -> Void

    @State private var hovered = false
    @State private var pressed = false

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: small ? 10 : 11, weight: .medium, design: .monospaced))
                .foregroundStyle(hovered ? Mono.accent : Mono.text)
                .padding(.horizontal, small ? 8 : 12)
                .padding(.vertical,   small ? 4 : 6)
                .background(pressed ? Mono.bg4 : (hovered ? Mono.bg3 : Mono.bg2))
                .overlay(
                    RoundedRectangle(cornerRadius: Mono.cornerR)
                        .stroke(Mono.border.opacity(hovered ? 0.8 : 0.45), lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: Mono.cornerR))
                .scaleEffect(pressed ? 0.97 : 1.0)
        }
        .buttonStyle(.plain)
        .animation(.easeOut(duration: 0.08), value: pressed)
        .animation(.easeOut(duration: 0.1),  value: hovered)
        .onHover { hovered = $0 }
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in pressed = true }
                .onEnded   { _ in pressed = false }
        )
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: – Segmented control
// ─────────────────────────────────────────────────────────────────────────────

struct MonoSegmented<T: Hashable>: View {
    let options: [(String, T)]
    @Binding var selection: T

    var body: some View {
        HStack(spacing: 0) {
            ForEach(options.indices, id: \.self) { i in
                SegmentCell(label: options[i].0, value: options[i].1, selection: $selection)
                if i < options.count - 1 {
                    Rectangle()
                        .fill(Mono.muted.opacity(0.5))
                        .frame(width: 1)
                        .padding(.vertical, 4)
                }
            }
        }
        .background(Mono.bg2)
        .overlay(RoundedRectangle(cornerRadius: Mono.cornerR).stroke(Mono.border.opacity(0.5), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: Mono.cornerR))
    }
}

private struct SegmentCell<T: Hashable>: View {
    let label: String
    let value: T
    @Binding var selection: T
    @State private var hovered = false

    var selected: Bool { value == selection }

    var body: some View {
        Text(label)
            .font(.system(size: 10, weight: selected ? .semibold : .regular, design: .monospaced))
            .foregroundStyle(selected ? Mono.bg0 : (hovered ? Mono.text : Mono.sub))
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity)
            .background(selected ? Mono.text : (hovered ? Mono.bg3 : Color.clear))
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(.easeOut(duration: 0.1)) { selection = value }
            }
            .onHover { hovered = $0 }
            .animation(.easeOut(duration: 0.1), value: hovered)
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: – Tab switcher
// ─────────────────────────────────────────────────────────────────────────────

enum PanelTab: String, CaseIterable {
    case render  = "Render"
    case color   = "Color"
    case tracker = "Tracker"
    case presets = "Presets"

    var icon: String {
        switch self {
        case .render:  return "textformat"
        case .color:   return "paintpalette"
        case .tracker: return "viewfinder"
        case .presets: return "slider.horizontal.3"
        }
    }
}

struct TabSwitcher: View {
    @Binding var selected: PanelTab
    @Namespace private var ns

    var body: some View {
        HStack(spacing: 0) {
            ForEach(PanelTab.allCases, id: \.self) { tab in
                TabCell(tab: tab, selected: $selected, ns: ns)
            }
        }
        .background(Mono.bg0)
        .overlay(Rectangle().fill(Mono.muted.opacity(0.6)).frame(height: 1), alignment: .bottom)
    }
}

private struct TabCell: View {
    let tab: PanelTab
    @Binding var selected: PanelTab
    var ns: Namespace.ID

    @State private var hovered = false
    var active: Bool { tab == selected }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 3) {
                Image(systemName: tab.icon)
                    .font(.system(size: 11, weight: active ? .medium : .regular))
                    .foregroundStyle(active ? Mono.accent : (hovered ? Mono.text : Mono.dim))
                Text(tab.rawValue)
                    .font(.system(size: 9, weight: active ? .semibold : .regular, design: .monospaced))
                    .foregroundStyle(active ? Mono.accent : (hovered ? Mono.text : Mono.dim))
            }
            .frame(maxWidth: .infinity)
            .frame(height: 44)
            .contentShape(Rectangle())
            .animation(.easeOut(duration: 0.1), value: hovered)

            ZStack {
                Rectangle().fill(Color.clear).frame(height: 2)
                if active {
                    Rectangle()
                        .fill(Mono.accent)
                        .frame(height: 2)
                        .matchedGeometryEffect(id: "tab", in: ns)
                }
            }
        }
        .onTapGesture {
            withAnimation(.spring(response: 0.22, dampingFraction: 0.8)) { selected = tab }
        }
        .onHover { hovered = $0 }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: – Grid cell  (char set / color mode buttons)
// ─────────────────────────────────────────────────────────────────────────────

struct GridCell: View {
    let label:    String
    let selected: Bool
    let action:   () -> Void

    @State private var hovered = false

    var body: some View {
        Text(label)
            .font(.system(size: 10, weight: selected ? .semibold : .regular, design: .monospaced))
            .foregroundStyle(selected ? Mono.bg0 : (hovered ? Mono.accent : Mono.text))
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity)
            .background(selected ? Mono.accent : (hovered ? Mono.bg3 : Mono.bg2))
            .overlay(
                RoundedRectangle(cornerRadius: Mono.cornerR)
                    .stroke(selected ? Color.clear : Mono.border.opacity(hovered ? 0.8 : 0.4), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: Mono.cornerR))
            .contentShape(Rectangle())
            .onTapGesture { action() }
            .onHover { hovered = $0 }
            .animation(.easeOut(duration: 0.1), value: hovered)
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: – Preview background
// ─────────────────────────────────────────────────────────────────────────────

enum PreviewBackground: CaseIterable {
    case checker, black, white

    var next: PreviewBackground {
        let all = Self.allCases
        return all[(all.firstIndex(of: self)! + 1) % all.count]
    }

    var icon: String {
        switch self {
        case .checker: return "squareshape.split.2x2"
        case .black:   return "square.fill"
        case .white:   return "square"
        }
    }

    var label: String {
        switch self {
        case .checker: return "Checker"
        case .black:   return "Black"
        case .white:   return "White"
        }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: – Checkerboard background  (alpha transparency indicator)
// ─────────────────────────────────────────────────────────────────────────────

struct CheckerboardView: View {
    private let tileSize: CGFloat = 12
    private let dark  = Color(white: 0.07)
    private let light = Color(white: 0.13)

    var body: some View {
        Canvas { ctx, size in
            let cols = Int(ceil(size.width  / tileSize))
            let rows = Int(ceil(size.height / tileSize))
            for row in 0...rows {
                for col in 0...cols {
                    let rect = CGRect(x: CGFloat(col) * tileSize,
                                     y: CGFloat(row) * tileSize,
                                     width: tileSize, height: tileSize)
                    ctx.fill(Path(rect), with: .color((row + col) % 2 == 0 ? dark : light))
                }
            }
        }
        .allowsHitTesting(false)
        .ignoresSafeArea()
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: – Drop zone
// ─────────────────────────────────────────────────────────────────────────────

struct DropZoneOverlay: View {
    var body: some View {
        VStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Mono.muted.opacity(0.35), style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
                    .frame(width: 56, height: 56)
                Image(systemName: "arrow.down.to.line")
                    .font(.system(size: 20, weight: .thin))
                    .foregroundStyle(Mono.dim.opacity(0.55))
            }
            VStack(spacing: 4) {
                Text("Drop a file to start")
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(Mono.sub)
                Text("Video  ·  Image  ·  PNG sequence folder")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(Mono.dim.opacity(0.6))
                    .tracking(0.3)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
