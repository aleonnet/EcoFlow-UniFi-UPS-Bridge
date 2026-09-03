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

    /// `estreito`: numa largura de telefone o rótulo e o campo não cabem lado a
    /// lado — o campo encolheria até não caber um caminho de chave. Aí a linha
    /// EMPILHA: rótulo em cima, campo ocupando a largura inteira. É o mesmo
    /// desenho que Ajustes do iOS usa quando o valor é longo.
    @ViewBuilder
    static func textRow(_ symbol: String, _ label: String, _ text: Binding<String>,
                        placeholder: String, numeric: Bool = false,
                        estreito: Bool = false) -> some View {
        let campo = TextField(placeholder, text: text)
            .textFieldStyle(.roundedBorder)
            .font(.system(.body, design: numeric ? .monospaced : .default))
            .autocorrectionDisabled()
        if estreito {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 10) {
                    Image(systemName: symbol)
                        .frame(width: 26)
                        .foregroundStyle(.secondary)
                    Text(label)
                        .font(.system(.body, design: .rounded))
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                campo
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity)
                    .padding(.leading, 36)
            }
        } else {
            HStack(spacing: 10) {
                Image(systemName: symbol)
                    .frame(width: 26)
                    .foregroundStyle(.secondary)
                // Largo: o rótulo fica numa linha e o CAMPO cede (do teto ao piso);
                // abaixo do piso a folha já empilhou (DeviceSheetMetrics.narrowBelow).
                Text(label)
                    .font(.system(.body, design: .rounded))
                    .fixedSize()
                Spacer(minLength: 8)
                campo
                    .multilineTextAlignment(numeric ? .trailing : .leading)
                    .frame(minWidth: numeric ? 70 : 150, maxWidth: numeric ? 90 : 260)
            }
        }
    }

    /// Uma escolha de lista fechada (o comando de desligamento do host SSH). O
    /// rótulo NUNCA quebra (mesma regra do sliderRow: o print do dono a 414 pt
    /// mostrou "Shut-down com-mand" hifenizado); a legenda fica sob o rótulo.
    /// Largo: rótulo à esquerda, seletor à direita com teto de largura. Estreito:
    /// empilha — rótulo e legenda em cima, seletor ocupando a largura inteira —
    /// o mesmo desenho das outras linhas empilhadas.
    @ViewBuilder
    static func pickerRow(_ symbol: String, _ label: String, caption: String? = nil,
                          selection: Binding<String>, options: [String],
                          monospaced: Bool = false, estreito: Bool = false) -> some View {
        let seletor = Picker("", selection: selection) {
            ForEach(options, id: \.self) { option in
                Text(option).font(.system(.body, design: monospaced ? .monospaced : .default)).tag(option)
            }
        }
        .labelsHidden()
        let cabecalho = VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(.body, design: .rounded))
                .fixedSize()
            if let caption {
                Text(caption)
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        if estreito {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: symbol).frame(width: 26).foregroundStyle(.secondary)
                    cabecalho
                    Spacer(minLength: 0)
                }
                seletor
                    .frame(maxWidth: .infinity)
                    .padding(.leading, 36)
            }
        } else {
            HStack(alignment: .center, spacing: 10) {
                Image(systemName: symbol).frame(width: 26).foregroundStyle(.secondary)
                cabecalho
                Spacer(minLength: 8)
                // O popup usa a largura NATURAL do seu texto: com um teto flexível
                // ele saía truncado numa folha de 560 pt (captura de 2026-09-03);
                // quem cede é a legenda, que quebra em duas linhas.
                seletor
                    .fixedSize(horizontal: true, vertical: false)
            }
        }
    }

    @ViewBuilder
    static func sliderRow(_ symbol: String, _ label: String,
                          value: Binding<Int>, range: ClosedRange<Int>, unit: String,
                          zeroLabel: String? = nil, accent: Color,
                          estreito: Bool = false) -> some View {
        if estreito {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 10) {
                    Image(systemName: symbol).frame(width: 26).foregroundStyle(.secondary)
                    Text(label).font(.system(.body, design: .rounded))
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 8)
                    Text(value.wrappedValue == 0 && zeroLabel != nil ? zeroLabel! : "\(value.wrappedValue)\(unit)")
                        .font(.system(.body, design: .rounded).weight(.semibold))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                }
                Slider(value: Binding(get: { Double(value.wrappedValue) },
                                      set: { value.wrappedValue = Int($0) }),
                       in: Double(range.lowerBound)...Double(range.upperBound), step: 1)
                    .tint(accent)
                    .padding(.leading, 36)
            }
            .animation(.snappy(duration: 0.2), value: value.wrappedValue)
        } else {
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
}
