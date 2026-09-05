// O grupo "Home Assistant": os quatro campos que ele pede, prontos para copiar.
//
// Por que existe: a senha da conta do Home Assistant é gerada na instalação e
// guardada num arquivo do diretório de estado. Sem esta tela, a única forma de
// saber qual é seria abrir o arquivo pelo terminal — o oposto do que este
// programa promete. O dono disse a frase: "o App tem que ser user friendly e não
// para nerds".
//
// A senha aparece escondida e só se revela a pedido, como um campo de senha do
// sistema: ela dá permissão de MANDAR ordens no no-break, e uma tela aberta na
// mesa não precisa mostrá-la para ninguém que passe.

import RiverBridgeCore
import SwiftUI

struct HomeAssistantGroup: View {
    @State private var senha: String?
    @State private var revelada = false
    @State private var copiado: String?

    private let porta = "3493"
    private let usuario = "homeassistant"

    var body: some View {
        SettingsRows.group("Home Assistant") {
            if senha == nil {
                Aviso(tom: .neutro,
                      texto: L10n.t("A conta do Home Assistant ainda não foi criada",
                                    "The Home Assistant account does not exist yet"),
                      detalhe: L10n.t(
                        "Ela nasce quando o serviço sobe pela primeira vez. Instale o serviço no grupo acima e volte aqui.",
                        "It is created the first time the service runs. Install the service in the group above and come back."))
            } else {
                Text(L10n.t("Em Ajustes › Dispositivos e serviços › Adicionar integração › Network UPS Tools (NUT):",
                            "In Settings › Devices & services › Add Integration › Network UPS Tools (NUT):"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                linha(L10n.t("Servidor", "Host"), enderecoDaMaquina, simbolo: "network")
                linha(L10n.t("Porta", "Port"), porta, simbolo: "number")
                linha(L10n.t("Usuário", "Username"), usuario, simbolo: "person")
                linhaDaSenha
                Text(L10n.t("Escolha o aparelho river-bridge para os sensores, e repita a integração no aparelho do dispositivo protegido para ter as ordens dele.",
                            "Pick the river-bridge device for the sensors, then add the integration again on the protected device to get its orders."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let copiado {
                Aviso(tom: .bom, texto: L10n.t("\(copiado) copiado", "\(copiado) copied"))
            }
        }
        .task { senha = Self.senhaGuardada() }
    }

    // MARK: - linhas

    private func linha(_ rotulo: String, _ valor: String, simbolo: String) -> some View {
        HStack(spacing: Espaco.medio) {
            Image(systemName: simbolo)
                .frame(width: 26)
                .foregroundStyle(.secondary)
            Text(rotulo)
                .font(.system(.body, design: .rounded))
            Spacer()
            Text(valor)
                .font(.system(.body, design: .monospaced))
                .textSelection(.enabled)
                .foregroundStyle(.secondary)
            botaoDeCopiar(rotulo, valor)
        }
    }

    private var linhaDaSenha: some View {
        HStack(spacing: Espaco.medio) {
            Image(systemName: "key")
                .frame(width: 26)
                .foregroundStyle(.secondary)
            Text(L10n.t("Senha", "Password"))
                .font(.system(.body, design: .rounded))
            Spacer()
            // Selecionável só quando revelada: pontinhos não se copiam, e um
            // campo selecionável escondido convida ao arrastar-e-colar às cegas.
            Group {
                if revelada {
                    Text(senha ?? "").textSelection(.enabled)
                } else {
                    Text("••••••••••••")
                }
            }
            .font(.system(.body, design: .monospaced))
            .foregroundStyle(.secondary)
            Button(revelada ? L10n.t("Esconder", "Hide") : L10n.t("Mostrar", "Show")) {
                revelada.toggle()
            }
            .controlSize(.small)
            botaoDeCopiar(L10n.t("Senha", "Password"), senha ?? "")
        }
    }

    private func botaoDeCopiar(_ oQue: String, _ valor: String) -> some View {
        Button {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(valor, forType: .string)
            copiado = oQue
        } label: {
            Image(systemName: "doc.on.doc")
        }
        .controlSize(.small)
        .help(L10n.t("Copiar", "Copy"))
    }

    // MARK: - de onde vem

    /// O nome desta máquina na rede — é o que se digita no campo do servidor.
    private var enderecoDaMaquina: String {
        let nome = ProcessInfo.processInfo.hostName
        return nome.isEmpty ? "127.0.0.1" : nome
    }

    /// A senha, do arquivo que o serviço escreveu. `nil` = a conta ainda não existe.
    ///
    /// Procura nas DUAS pastas de estado pelo mesmo motivo da ficha da API: as
    /// duas formas de instalar convivem, e olhar só numa faria a tela dizer que
    /// a conta não existe com ela existindo.
    static func senhaGuardada() -> String? {
        for pasta in ApiEndpoint.stateDirs() {
            let caminho = pasta.appendingPathComponent("nut-homeassistant.token")
            guard let bruto = try? String(contentsOf: caminho, encoding: .utf8) else { continue }
            let senha = bruto.trimmingCharacters(in: .whitespacesAndNewlines)
            if !senha.isEmpty { return senha }
        }
        return nil
    }
}
