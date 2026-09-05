// A moldura comum de toda folha de dispositivo: cabeçalho (ícone do tipo, o
// nome DIGITADO, o badge, a legenda do tipo), o corpo rolável que cada tipo
// preenche à mão, e o rodapé (feedback, Remover…, Cancelar/Fechar,
// Adicionar/Salvar). O tamanho vem de DeviceSheetMetrics — os mesmos números
// que o teste do Core lê, para a folha caber na janela mínima de 414×480.
//
// Um sheet por vez (HIG): a confirmação de remover é um confirmationDialog
// DENTRO desta moldura, porque a folha é uma NSWindow própria.

import RiverBridgeCore
import SwiftUI

struct DeviceSheetFrame<Content: View>: View {
    let mode: DeviceSheetMode
    let type: DeviceTypeDescriptor
    let typedName: String
    let currentName: String
    let badge: (String, Color)?
    let hostSize: CGSize
    var feedback: String?
    var notice: String?
    var canSave: Bool
    var hasChanges: Bool
    let onClose: () -> Void
    let onSave: () -> Void
    var onBack: (() -> Void)?
    var onRemove: (() -> Void)?
    /// O corpo recebe `estreito`: verdadeiro quando a folha, na largura em que
    /// está REALMENTE desenhada, não tem espaço para rótulo e controle lado a lado.
    @ViewBuilder let content: (_ estreito: Bool) -> Content

    @State private var showRemoveDialog = false
    /// A largura medida da folha. Nasce com a aritmética da janela-mãe (para o
    /// primeiro desenho não piscar) e passa a ser o valor medido no primeiro layout.
    @State private var larguraMedida: CGFloat?

    private var size: CGSize { DeviceSheetMetrics.size(host: hostSize) }
    private var estreito: Bool { DeviceSheetMetrics.isNarrow(width: larguraMedida ?? size.width) }
    private var accent: Color { Theme.accentColor(onBattery: false, lowBattery: false) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) { content(estreito) }
                    .padding(20)
            }
            // A folha abre no TOPO, sempre: a de edição do host SSH abria rolada
            // até o seletor de comando (captura de 2026-09-03), porque o valor
            // da instância chega depois do primeiro desenho e o seletor puxa a
            // rolagem ao mudar.
            .defaultScrollAnchor(.top)
            // A variante estreita/larga das linhas segue a largura em que a folha
            // FOI desenhada, não a que a aritmética previu: quando as duas
            // divergiram (2026-09-03), as linhas largas cortavam o cabeçalho.
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { larguraMedida = $0 }
            Divider()
            footer
        }
        // Quadro FIXO, e só ele: medido em 2026-09-03, com min/ideal/máx o macOS
        // dimensiona a janela da folha pelo conteúdo e ignora a largura ideal
        // (470 pt tanto numa janela de 414 quanto numa de 600). Com o quadro fixo
        // a folha tem exatamente `size`, que é a janela-mãe menos a margem, e por
        // isso nunca passa da janela — desde que `hostSize` seja a medida do
        // espaço oferecido (GeometryReader em SettingsView), não a de um conteúdo
        // que transbordou: foi essa medida errada que fez a folha vazar antes.
        .frame(width: size.width, height: size.height)
        .interactiveDismissDisabled(hasChanges)
        .confirmationDialog(L10n.t("Remover \(currentName)?", "Remove \(currentName)?"),
                            isPresented: $showRemoveDialog, titleVisibility: .visible) {
            Button(L10n.t("Remover", "Remove"), role: .destructive) { onRemove?() }
            Button(L10n.t("Cancelar", "Cancel"), role: .cancel) {}
        } message: {
            Text(L10n.t("Os eventos gravados continuam no histórico. A chave e a identidade registrada do aparelho, que você mesmo criou, não são apagadas.",
                        "Recorded events stay in the history. The key and the device's registered identity, which you created yourself, are not deleted."))
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: type.symbol)
                .font(.title2)
                .foregroundStyle(accent)
            VStack(alignment: .leading, spacing: 2) {
                // O nome DIGITADO manda no cabeçalho: a pessoa vê o que está
                // prestes a salvar, não o que já está salvo.
                Text(typedName.trimmingCharacters(in: .whitespaces).isEmpty ? currentName : typedName)
                    .font(.system(.title3, design: .rounded).weight(.semibold))
                if let badge, !mode.isNew {
                    Text(badge.0).font(.caption).foregroundStyle(badge.1)
                } else {
                    Text(type.label).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    /// O aviso ocupa a linha de cima, em toda a largura; os botões ficam
    /// inteiros na de baixo (com o aviso ao lado, "Remover dispositivo…"
    /// quebrava em duas linhas — captura de 2026-09-03).
    private var footer: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let feedback {
                Label(feedback, systemImage: "exclamationmark.triangle.fill")
                    .font(.callout).foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            } else if let notice {
                Label(notice, systemImage: "checkmark.circle")
                    .font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 12) {
            Spacer()
            if onRemove != nil, !mode.isNew {
                // HIG destructive-in-a-list: texto vermelho, não um bloco cheio.
                Button(role: .destructive) { showRemoveDialog = true } label: {
                    Text(L10n.t("Remover dispositivo…", "Remove device…"))
                        .foregroundStyle(.red)
                        .frame(minHeight: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
            }
            if let onBack, mode.isNew {
                Button(L10n.t("Voltar", "Back")) { onBack() }
                    .buttonStyle(.glass)
            }
            Button(mode.isNew ? L10n.t("Cancelar", "Cancel") : L10n.t("Fechar", "Close")) { onClose() }
                .buttonStyle(.glass)
                .keyboardShortcut(.cancelAction)
            Button(mode.isNew ? L10n.t("Adicionar", "Add") : L10n.t("Salvar", "Save")) { onSave() }
                .buttonStyle(.glassProminent)
                .tint(accent)
                .disabled(!canSave)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }
}

/// A linha de armamento de uma instância: o estado do ensaio (vindo do health,
/// nunca de uma cópia local), a trava do dono, e o botão que desliga o ensaio
/// SÓ depois de uma confirmação — nunca um Toggle ligado ao estado.
struct ArmingRow: View {
    let dryRun: Bool
    let enabled: Bool
    let armAllowed: Bool
    /// Falso quando o serviço ainda não provou que alcança o aparelho. É outra
    /// coisa que a trava: misturar os dois fazia a tela dizer "a trava está
    /// fechada" com a trava aberta (revisão fria da 0.6.0).
    var alcanceProvado: Bool = true
    var estreito: Bool = false
    let onTurnOffRehearsal: () -> Void
    let onTurnOnRehearsal: () -> Void

    /// O rótulo de um botão nunca quebra (HIG, Buttons): a 414 pt o "Desligar
    /// modo ensaio…" saía em duas linhas ao lado do texto (captura do dono,
    /// 2026-09-03). Estreito: o botão desce para a linha de baixo e fica à
    /// DIREITA (é a ação da linha), a partir da coluna do texto — nunca sob o ícone.
    var body: some View {
        if estreito {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top, spacing: 10) {
                    icone
                    textos
                    Spacer(minLength: 0)
                }
                HStack { Spacer(minLength: 36); botao }
            }
        } else {
            HStack(spacing: 10) {
                icone
                textos
                Spacer(minLength: 8)
                botao
            }
        }
    }

    private var icone: some View {
        Image(systemName: dryRun ? "theatermasks.fill" : "bolt.shield.fill")
            .frame(width: 26)
            .foregroundStyle(dryRun ? Color.secondary : Color.red)
    }

    private var textos: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(dryRun ? L10n.t("Modo ensaio", "Rehearsal mode")
                        : L10n.t("ARMADA — desliga o aparelho de verdade", "ARMED — really shuts the device down"))
                .font(.system(.body, design: .rounded))
                .fixedSize(horizontal: false, vertical: true)
            Text(!alcanceProvado
                 ? L10n.t("Falta provar que o serviço alcança este aparelho: use Conectar ou Testar conexão, logo abaixo.",
                          "The service still has to prove it reaches this device: use Connect or Test connection, just below.")
                 : armAllowed
                 ? L10n.t("A trava de armamento está aberta. Feche-a no arquivo do serviço depois de armar (veja o guia).",
                          "The arming lock is open. Close it in the service file after arming (see the guide).")
                 : L10n.t("A trava de armamento está fechada. Para armar, abra-a no arquivo do serviço e reinicie (veja o guia).",
                          "The arming lock is closed. To arm, open it in the service file and restart (see the guide)."))
                .font(.caption)
                .foregroundStyle(armAllowed && alcanceProvado ? Color.orange : Color.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var botao: some View {
        if dryRun {
            Button(role: .destructive) { onTurnOffRehearsal() } label: {
                Text(L10n.t("Desligar modo ensaio…", "Turn rehearsal off…"))
                    .fixedSize()
                    .foregroundStyle(armAllowed && enabled && alcanceProvado ? Color.red : Color.secondary)
                    .frame(minHeight: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .disabled(!armAllowed || !enabled || !alcanceProvado)
        } else {
            Button(L10n.t("Ligar modo ensaio", "Turn rehearsal on")) { onTurnOnRehearsal() }
                .buttonStyle(.glass)
        }
    }
}
