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
    // A escuta na rede (0.8.0): o Home Assistant mora noutra máquina, e até a
    // 0.7.0 abrir a porta era editar um arquivo à mão e reiniciar. `nil` = o
    // serviço ainda não respondeu, ou o arquivo do servidor é do dono.
    @State private var rede: APIClient.RedeDoNut?
    @State private var redeEmVoo = false
    @State private var recadoDaRede: String?
    // Ligar pede confirmação, como as travas: abre o servidor à rede e, com as
    // travas abertas, as ordens passam a ser alcançáveis por quem tiver a senha.
    @State private var confirmandoRede = false

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
                linhaDaRede
                SettingsRows.divider
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
        .task {
            senha = Self.senhaGuardada()
            await carregarRede()
        }
        .confirmacao(Binding(
            get: {
                guard confirmandoRede else { return nil }
                let texto = RedeConfirmation()
                return PedidoDeConfirmacao(
                    titulo: texto.title, detalhe: texto.message,
                    rotuloDaAcao: texto.confirmLabel, destrutivo: true
                ) { Task { await mudarRede(true) } }
            },
            set: { if $0 == nil { confirmandoRede = false } }))
    }

    // MARK: - a escuta na rede

    /// O interruptor que abre o servidor do no-break para a rede local. Sem ele
    /// o Home Assistant não alcança este Mac: o servidor nasce escutando só a
    /// própria máquina. Quando o arquivo do servidor é do dono, a linha explica
    /// em vez de oferecer um interruptor que reescreveria o que é dele.
    @ViewBuilder
    private var linhaDaRede: some View {
        HStack(alignment: .top, spacing: Espaco.medio) {
            Image(systemName: "antenna.radiowaves.left.and.right")
                .frame(width: 26)
                .foregroundStyle(rede?.aberta == true ? Cor.atencao : Cor.neutro)
            VStack(alignment: .leading, spacing: Espaco.fio) {
                Text(L10n.t("Aceitar o Home Assistant pela rede", "Accept Home Assistant over the network"))
                    .font(.system(.body, design: .rounded))
                Text(rede?.propria == false
                     ? L10n.t("A configuração do servidor do no-break não é a que o serviço escreveu (foi escrita à mão, ou ainda não existe): este interruptor não a toca.",
                              "The UPS server configuration is not the one the service wrote (written by hand, or not there yet): this switch does not touch it.")
                     : L10n.t("O servidor do no-break passa a escutar na rede local, e as ordens das travas abertas ficam ao alcance de quem tiver a senha. Desligado, só este Mac fala com ele.",
                              "The UPS server starts listening on the local network, and the orders of the open locks are within reach of anyone with the password. Off, only this Mac talks to it."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let recadoDaRede {
                    Text(recadoDaRede).font(.caption).foregroundStyle(Cor.atencao)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: Espaco.pequeno)
            Toggle("", isOn: Binding(
                get: { rede?.aberta ?? false },
                set: { novo in
                    if novo { confirmandoRede = true } else { Task { await mudarRede(false) } }
                }))
                .labelsHidden()
                .toggleStyle(.switch)
                .disabled(rede?.propria != true || redeEmVoo)
        }
    }

    private func carregarRede() async {
        guard let endpoint = ApiEndpoint.discover() else { return }
        rede = try? await APIClient(endpoint: endpoint).nutRede()
    }

    private func mudarRede(_ aberta: Bool) async {
        guard let endpoint = ApiEndpoint.discover() else {
            recadoDaRede = L10n.t("Serviço parado — nada mudou.", "Service down — nothing changed.")
            return
        }
        redeEmVoo = true
        do {
            let resposta = try await APIClient(endpoint: endpoint).nutRede(aberta: aberta)
            // Serviço que não cuida do servidor do no-break (instalação pela
            // linha de comando com RIVER_NUT_MANAGED=0): o arquivo mudou, mas o
            // servidor só lê a linha na partida — e quem o reinicia é o dono.
            recadoDaRede = (resposta.mudou && !resposta.servidorReiniciado)
                ? L10n.t("Gravado. Este serviço não cuida do servidor do no-break: reinicie-o você para a mudança valer.",
                         "Saved. This service does not manage the UPS server: restart it yourself for the change to apply.")
                : nil
        } catch let APIError.badStatus(_, body) {
            recadoDaRede = ProtectionRefusal.text(body)
        } catch {
            recadoDaRede = L10n.t("Não consegui falar com o serviço.", "Could not reach the service.")
        }
        await carregarRede()
        redeEmVoo = false
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
