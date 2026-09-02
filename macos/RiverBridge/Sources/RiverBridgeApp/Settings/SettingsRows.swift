// Linhas de UI compartilhadas entre a tela de Ajustes e as folhas dos
// dispositivos. Saíram de SettingsView quando a folha do UDR7 passou a precisar
// das mesmas linhas: duas cópias divergiriam no primeiro ajuste de espaçamento.
//
// `toggleRow` NÃO veio junto: seu único chamador era o grupo de proteção, que
// deixou de existir, e a folha não tem toggle. Código sem consumidor não migra.

import RiverBridgeCore
import SwiftUI

enum SettingsRows {
    static var divider: some View {
        Divider().padding(.leading, 46)
    }

    @ViewBuilder
    static func group(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).eyebrow()
            // No hover on big containers — hover belongs to interactive
            // elements only (owner 2026-08-31, print do bloco aceso).
            VStack(spacing: 8) { content() }
                .padding(14)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                // Material, NOT glassEffect: neighbouring glass shapes merge
                // their backdrop into a gray wash when the window is key
                // (measured 2026-08-31). House grammar: glass is for the
                // CONTROL layer; content panels sit on material.
        }
    }

    /// HIG-fit for mouse AND finger: a menu picker over sensible presets
    /// (values anchored in the SOTA research). A custom value already in the
    /// .env stays selectable — it joins the list instead of vanishing.
    static func presetRow(_ symbol: String, _ label: String,
                           value: Binding<Int>, presets: [Int]) -> some View {
        let options = presets.contains(value.wrappedValue)
            ? presets
            : (presets + [value.wrappedValue]).sorted()
        return HStack(spacing: 10) {
            Image(systemName: symbol)
                .frame(width: 26)
                .foregroundStyle(.secondary)
            Text(label)
                .font(.system(.body, design: .rounded))
                .fixedSize()
            Spacer()
            Picker("", selection: value) {
                ForEach(options, id: \.self) { v in
                    Text("\(v) s").tag(v)
                }
            }
            .labelsHidden()
            .fixedSize()
        }
    }

    static func textRow(_ symbol: String, _ label: String, _ text: Binding<String>,
                         placeholder: String, numeric: Bool = false) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .frame(width: 26)
                .foregroundStyle(.secondary)
            Text(label)
                .font(.system(.body, design: .rounded))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            TextField(placeholder, text: text)
                .textFieldStyle(.roundedBorder)
                .font(.system(.body, design: numeric ? .monospaced : .default))
                .multilineTextAlignment(numeric ? .trailing : .leading)
                .frame(minWidth: numeric ? 70 : 150, maxWidth: numeric ? 90 : 260)
                .autocorrectionDisabled()
        }
    }

    static func sliderRow(_ symbol: String, _ label: String,
                           value: Binding<Int>, range: ClosedRange<Int>, unit: String,
                           zeroLabel: String? = nil, accent: Color) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .frame(width: 26)
                .foregroundStyle(.secondary)
            // The LABEL never wraps (owner's print at min width) — the
            // slider is the flexible element, with a floor that keeps it
            // usable for both pointer and finger (native Slider = the HIG
            // control for continuous ranges on every input).
            Text(label)
                .font(.system(.body, design: .rounded))
                .fixedSize()
            Spacer(minLength: 8)
            Text(value.wrappedValue == 0 && zeroLabel != nil ? zeroLabel! : "\(value.wrappedValue)\(unit)")
                .font(.system(.body, design: .rounded).weight(.semibold))
                .monospacedDigit()
                .contentTransition(.numericText())
            Slider(
                value: Binding(
                    get: { Double(value.wrappedValue) },
                    set: { value.wrappedValue = Int($0) }
                ),
                in: Double(range.lowerBound)...Double(range.upperBound), step: 1
            )
            .tint(accent)
            .frame(minWidth: 90, maxWidth: 170)
        }
        .animation(.snappy(duration: 0.2), value: value.wrappedValue)
    }
}
