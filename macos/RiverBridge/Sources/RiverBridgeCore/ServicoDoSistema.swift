// O serviço que mora DENTRO do aplicativo: registrar, autorizar e remover.
//
// Por que isto existe: arrastar o programa para Aplicativos põe o programa lá,
// e mais nada. O serviço que vigia a energia vai junto dentro do pacote
// (`Contents/Library/LaunchDaemons/`), mas alguém precisa registrá-lo — e quem
// faz isso é o próprio programa, com o `ServiceManagement` da Apple.
//
// Documentação da Apple, citada literalmente (lida em 2026-09-05 e 2026-09-06).
//
// Onde o arquivo do serviço precisa morar — `SMAppService.daemon(plistName:)`:
//
//   "The property list name must correspond to a property list in the calling
//    app's Contents/Library/LaunchDaemons directory"
//
// O registro, que é o ponto que muda a tela — `register()`:
//
//   "Registers the service so it can begin launching subject to user approval."
//   "If the service corresponds to a LaunchDaemon, the system won't bootstrap
//    the LaunchDaemon until an admin approves the LaunchDaemon in System
//    Preferences."
//   "If the service is already registered, this method returns."
//
// E os estados que ele devolve:
//
//   .notRegistered    "The service hasn't registered with the Service
//                      Management framework, or the service attempted to
//                      reregister after it was already registered."
//   .enabled          "The service has been successfully registered and is
//                      eligible to run."
//   .requiresApproval "The service has been successfully registered, but the
//                      user needs to take action in System Preferences." … "The
//                      framework also returns this status if the user revokes
//                      consent for the service to run in System Settings."
//   .notFound         "An error occurred and the framework couldn't find this
//                      service."
//
// `.enabled` é "ELIGIBLE to run" — não "rodando". O dono viu no Mac mini, em
// 2026-09-06, a tela dizer "O serviço está no ar" ao lado de "Sem resposta do
// serviço" e "Serviço parado": o registro de uma instalação anterior continuava
// habilitado e o processo não existia. Por isso o estado da tela combina as DUAS
// fontes: o que o sistema diz do registro, e se o serviço responde de fato.
//
// A remoção — `unregister()`:
//
//   "Unregisters the service so the system no longer launches it. … If the
//    service corresponds to a LoginItem, LaunchAgent, or LaunchDaemon and the
//    service is currently running it, the system terminates it."
//
// É a ÚNICA forma de apagar o interruptor "River Bridge" em Ajustes do Sistema ›
// Geral › Itens de Início de Sessão; um `launchctl bootout` para o processo e
// deixa o interruptor ligado (visto pelo dono, 2026-09-06, com o programa no
// Lixo). Quem chama é este programa (Remover completamente) ou o ajudante
// `river-bridge-servico` dentro do pacote, que o serviço executa quando o
// pacote vai para o Lixo (remocao.py). A LINHA "River Bridge" na lista dos
// Ajustes do Sistema é do macOS: depois de `unregister()` ela pode continuar
// listada, desligada — a Apple não documenta a lista, só o registro.
//
// QUANDO registrar e ONDE pedir a autorização — "Updating helper executables
// from earlier versions of macOS":
//
//   "If your app can't run or operate correctly without helper executables,
//    check the authorization status at launch. If helper executables don't have
//    authorization, alert the user, and call openSystemSettingsLoginItems() to
//    suggest that they update the System Settings."
//
// E as Human Interface Guidelines (Onboarding; Privacy; Alerts; Writing):
//
//   "If your app or game needs access to private data or resources before it
//    can function, consider integrating the permission request into your
//    onboarding flow."
//   "Avoid requesting permission at launch unless the data or resource is
//    required for your app to function."
//   "Write a title that clearly and succinctly describes the situation."
//   "If you need to add an informative message, keep it as short as possible,
//    using complete sentences, sentence-style capitalization, and appropriate
//    punctuation."
//   "Aim for a one- or two-word title that describes the result of selecting
//    the button." "Always use the title 'Cancel' for a button that cancels an
//    alert's action."
//   "When an error message is necessary, display it as close to the problem as
//    possible, avoid blame, and be clear about what someone can do to fix it."
//
// O serviço É o programa: sem ele, nada é vigiado. Logo o registro acontece
// sozinho na abertura, e a autorização é pedida na ABERTURA — no aviso do topo
// do painel, com o botão que leva aos Ajustes do Sistema — e não num botão
// escondido em Ajustes (o dono chamou o que era, 2026-09-05). A autorização é
// um ato do macOS, uma vez, que o certificado do programa NÃO dispensa.
//
// Este arquivo é a parte testável: os estados, as frases nas DUAS línguas e as
// regras de qual ato cada estado pede. Quem fala com o `ServiceManagement` de
// verdade é a camada de tela, que não entra em teste. Toda frase daqui é um PAR
// (português, inglês): no Mac mini (em inglês) a tela misturava as duas línguas
// no mesmo cartão (2026-09-05).

import Foundation

/// O ato que a tela oferece para um estado do serviço.
public enum AcaoDoServico: Sendable, Equatable {
    /// O registro automático da abertura falhou: tentar de novo.
    case registrar
    /// O macOS espera a autorização: levar o dono aos Ajustes do Sistema.
    case abrirAjustesDoSistema
    /// Registrado e autorizado, mas o serviço não responde: religar, que é o
    /// mesmo `register()` — medido no Mac mini em 2026-09-06: num registro já
    /// autorizado ele sobe o serviço na hora, sem nova autorização.
    case religar

    public var rotulo: String { rotulo(emPortugues: L10n.cachedIsPT) }

    public func rotulo(emPortugues pt: Bool) -> String {
        switch self {
        case .registrar:
            return pt ? "Registrar de novo" : "Register again"
        case .abrirAjustesDoSistema:
            return pt ? "Abrir Ajustes do Sistema" : "Open System Settings"
        case .religar:
            return pt ? "Religar o serviço" : "Restart the service"
        }
    }
}

/// Em que pé está o serviço, na língua do dono.
public enum EstadoDoServico: String, Sendable, CaseIterable {
    /// Nunca foi registrado nesta máquina (ou o registro da abertura falhou).
    case naoInstalado
    /// Registrado, e esperando o dono autorizar no macOS.
    case esperandoAprovacao
    /// Registrado, autorizado e respondendo.
    case noAr
    /// Registrado e autorizado, mas o serviço não responde há mais tempo do
    /// que leva para subir. É o gatilho de a abertura religá-lo (uma vez); se
    /// depois disso ele continuar mudo, o botão da tela religa de novo.
    case registradoMasParado
    /// O sistema respondeu `.notFound`: "An error occurred and the framework
    /// couldn't find this service". (Desligar nos Ajustes do Sistema NÃO cai
    /// aqui: a Apple diz que revogar o consentimento devolve `.requiresApproval`.)
    case naoEncontradoPeloSistema
    /// Existe uma instalação pela LINHA DE COMANDO nesta máquina.
    case instaladoPelaLinhaDeComando
    /// O programa está rodando de fora de Aplicativos (do disco de instalação,
    /// de Downloads…): um serviço registrado dali apontaria para um caminho que
    /// some ao ejetar o disco ou mover o arquivo. Nada é registrado até ele
    /// estar em Aplicativos. Inclui a translocação do Gatekeeper: um pacote em
    /// quarentena copiado para Aplicativos SEM o Finder abre de
    /// `/private/var/folders/…/AppTranslocation/…` (medido no Mac mini,
    /// 2026-09-06); mover com o Finder desfaz — e a frase diz isso.
    case foraDeAplicativos

    public var titulo: String { titulo(emPortugues: L10n.cachedIsPT) }
    public var explicacao: String { explicacao(emPortugues: L10n.cachedIsPT) }

    public func titulo(emPortugues pt: Bool) -> String {
        switch self {
        case .naoInstalado:
            return pt ? "O serviço ainda não está registrado"
                      : "The service is not registered yet"
        case .esperandoAprovacao:
            return pt ? "Autorize o River Bridge no macOS"
                      : "Allow River Bridge in macOS"
        case .noAr:
            return pt ? "O serviço está no ar"
                      : "The service is running"
        case .registradoMasParado:
            return pt ? "O serviço está registrado, mas não responde"
                      : "The service is registered but not responding"
        case .naoEncontradoPeloSistema:
            return pt ? "O macOS não encontra o serviço"
                      : "macOS can't find the service"
        case .instaladoPelaLinhaDeComando:
            return pt ? "O serviço já está instalado por fora"
                      : "The service is already installed another way"
        case .foraDeAplicativos:
            return pt ? "Mova o River Bridge para Aplicativos"
                      : "Move River Bridge to Applications"
        }
    }

    public func explicacao(emPortugues pt: Bool) -> String {
        switch self {
        case .naoInstalado:
            return pt
                ? "O River Bridge registra o serviço sozinho ao abrir. Se esta mensagem "
                  + "não sumir em alguns segundos, toque em Registrar de novo."
                : "River Bridge registers the service by itself when it opens. If this "
                  + "message does not go away in a few seconds, click Register again."
        case .esperandoAprovacao:
            return pt
                ? "O macOS pergunta, uma vez, se o River Bridge pode rodar em segundo "
                  + "plano. Clique em Permitir na notificação, ou ligue o River Bridge "
                  + "em Ajustes do Sistema › Geral › Itens de Início de Sessão. Ele pede "
                  + "a sua senha de administrador."
                : "macOS asks once whether River Bridge may run in the background. "
                  + "Click Allow on the notification, or turn River Bridge on in "
                  + "System Settings › General › Login Items. It asks for your "
                  + "administrator password."
        case .noAr:
            return pt
                ? "Ele sobe sozinho quando o computador liga, mesmo sem ninguém entrar "
                  + "na conta."
                : "It starts on its own when the computer boots, even before anyone "
                  + "logs in."
        case .registradoMasParado:
            return pt
                ? "O macOS conhece o serviço, mas ele não está rodando. Toque em "
                  + "Religar o serviço; se não voltar, use Remover completamente e "
                  + "abra o programa de novo."
                : "macOS knows the service, but it is not running. Click Restart the "
                  + "service; if it does not come back, use Remove completely and open "
                  + "the app again."
        case .naoEncontradoPeloSistema:
            return pt
                ? "O macOS respondeu que não encontra o serviço registrado. Toque em "
                  + "Registrar de novo."
                : "macOS answered that it can't find the registered service. Click "
                  + "Register again."
        case .instaladoPelaLinhaDeComando:
            return pt
                ? "Esta máquina já tem o serviço instalado pelo comando de uma linha, e "
                  + "dois serviços disputariam o mesmo cabo. Remova aquele antes (o "
                  + "desinstalador está em /usr/local/river-unifi-bridge/scripts) e volte aqui."
                : "This machine already has the service installed by the one-line command, "
                  + "and two services would fight over the same cable. Remove that one first "
                  + "(the uninstaller is in /usr/local/river-unifi-bridge/scripts) and come back."
        case .foraDeAplicativos:
            return pt
                ? "O programa está aberto de fora da pasta Aplicativos. Arraste-o para "
                  + "Aplicativos com o Finder e abra-o de lá. Se ele já estiver lá, mova-o "
                  + "com o Finder para outra pasta e de volta."
                : "The app is running from outside the Applications folder. Drag it to "
                  + "Applications with the Finder and open it from there. If it is already "
                  + "there, move it with the Finder to another folder and back."
        }
    }

    /// O que o sistema diz do registro, e se o serviço responde — combinados.
    /// `respondendo` é a fonte viva (o fluxo de leituras do serviço).
    /// `haQuantoTempoHabilitado` é quanto tempo o registro está `.enabled` sem
    /// resposta: logo depois de autorizar, o serviço leva alguns segundos para
    /// subir, e isso não é "parado".
    public static func combinado(registro: EstadoDoServico, respondendo: Bool,
                                 haQuantoTempoHabilitado: TimeInterval) -> EstadoDoServico {
        guard registro == .noAr else { return registro }
        if respondendo { return .noAr }
        return haQuantoTempoHabilitado >= tolerancia ? .registradoMasParado : .noAr
    }

    /// O relógio de "habilitado sem resposta", puro e testável: só anda enquanto
    /// o sistema diz `.enabled` E o serviço não responde; qualquer outra coisa o
    /// zera. Antes da autorização ele não anda — senão a tolerância já estaria
    /// gasta quando o dono autorizasse (revisão fria da 0.8.3).
    public struct RelogioDoRegistro: Sendable, Equatable {
        public var desde: Date?
        public init() {}

        public mutating func haQuantoTempo(registro: EstadoDoServico, respondendo: Bool,
                                           agora: Date = Date()) -> TimeInterval {
            guard registro == .noAr, !respondendo else { desde = nil; return 0 }
            let inicio = desde ?? agora
            desde = inicio
            return agora.timeIntervalSince(inicio)
        }
    }

    /// Quanto tempo um registro habilitado pode ficar sem resposta antes de a
    /// tela dizer "não responde": o tempo de o serviço subir (Python, leitor do
    /// no-break, primeira leitura) com folga. Medido no Mac mini em 2026-09-06:
    /// da autorização à primeira leitura, poucos segundos.
    public static let tolerancia: TimeInterval = 15

    /// O registro (que a abertura faz sozinha) ainda precisa acontecer?
    public var precisaRegistrar: Bool {
        switch self {
        case .naoInstalado, .naoEncontradoPeloSistema: return true
        case .esperandoAprovacao, .noAr, .registradoMasParado,
             .instaladoPelaLinhaDeComando, .foraDeAplicativos: return false
        }
    }

    /// A abertura chama `register()` neste estado? Sim quando o sistema não
    /// conhece o serviço, e TAMBÉM quando o conhece, autorizado, mas ele não
    /// responde: registrar de novo é idempotente pela Apple ("If the service is
    /// already registered, this method returns") e, medido no Mac mini em
    /// 2026-09-06, sobe na hora um serviço cujo registro já estava autorizado —
    /// o caso do registro herdado de uma instalação anterior (o dono viu
    /// "no ar" com o serviço morto).
    public var aberturaRegistra: Bool {
        precisaRegistrar || self == .registradoMasParado
    }

    /// Dá para remover por aqui agora?
    public var podeRemover: Bool {
        switch self {
        case .esperandoAprovacao, .noAr, .registradoMasParado, .naoEncontradoPeloSistema: return true
        case .naoInstalado, .instaladoPelaLinhaDeComando, .foraDeAplicativos: return false
        }
    }

    /// O aviso da abertura aparece? Sim para tudo o que impede a vigilância —
    /// inclusive "mova para Aplicativos", que não tem botão: a frase diz o ato.
    public var avisaNaAbertura: Bool {
        switch self {
        case .naoInstalado, .esperandoAprovacao, .registradoMasParado,
             .naoEncontradoPeloSistema, .foraDeAplicativos: return true
        case .noAr, .instaladoPelaLinhaDeComando: return false
        }
    }

    /// O ato que o aviso da ABERTURA oferece — a Apple manda checar na partida,
    /// avisar e levar aos Ajustes do Sistema (citação no alto do arquivo).
    /// `nil` = nada a fazer, ou a frase já diz o ato.
    public var acaoNaAbertura: AcaoDoServico? {
        switch self {
        case .naoInstalado, .naoEncontradoPeloSistema: return .registrar
        case .esperandoAprovacao: return .abrirAjustesDoSistema
        case .registradoMasParado: return .religar
        case .noAr, .instaladoPelaLinhaDeComando, .foraDeAplicativos: return nil
        }
    }
}

/// O que "Remover completamente" faz — a confirmação, no molde das HIG:
/// título que descreve a situação, mensagem curta em frases completas, botão
/// de uma palavra, Cancelar sempre. Nada de "sem volta": registrar de novo
/// existe, e a chave e as senhas nascem outra vez na próxima instalação.
public struct RemocaoCompleta: Sendable, Equatable {
    /// O serviço responde? Sem ele, a chave e as senhas (arquivos do sistema)
    /// não podem ser apagadas por este programa, e a confirmação diz isso.
    public var servicoResponde: Bool

    public init(servicoResponde: Bool) {
        self.servicoResponde = servicoResponde
    }

    public var pergunta: String {
        L10n.t("Remover o River Bridge por completo?", "Remove River Bridge completely?")
    }

    public var aviso: String {
        if servicoResponde {
            return L10n.t("O serviço para e sai dos Itens de Início de Sessão. A chave do "
                          + "console, as senhas e o histórico são apagados. O programa fica "
                          + "em Aplicativos.",
                          "The service stops and leaves Login Items. The console key, the "
                          + "passwords and the history are erased. The app stays in "
                          + "Applications.")
        }
        return L10n.t("O serviço sai dos Itens de Início de Sessão. Como ele não está "
                      + "respondendo, a chave do console, as senhas e o histórico ficam em "
                      + "/Library/Application Support/river-unifi-bridge.",
                      "The service leaves Login Items. Since it is not responding, the "
                      + "console key, the passwords and the history stay in "
                      + "/Library/Application Support/river-unifi-bridge.")
    }

    public var rotuloDoBotao: String {
        L10n.t("Remover", "Remove")
    }

    /// O que acontece ao arrastar o programa para o Lixo — dito ANTES, curto.
    public static var avisoDoLixo: String {
        L10n.t("Arrastar o programa para o Lixo faz o mesmo que Remover completamente.",
               "Dragging the app to the Trash does the same as Remove completely.")
    }
}

/// Onde o pacote pode ser registrado: só dentro de uma pasta Aplicativos.
///
/// Aberto do disco de instalação, de Downloads ou de uma cópia de ensaio, um
/// serviço registrado apontaria para um caminho que some. É função pura para
/// o teste refutar a regra (prefixo com barra, as duas pastas, o caminho de
/// translocação do Gatekeeper); quem passa as pastas reais é a camada de tela.
public enum PastaDeAplicativos {
    public static func contem(_ pacote: URL, pastas: [URL]) -> Bool {
        let caminho = pacote.standardizedFileURL.path
        return pastas.contains { caminho.hasPrefix($0.standardizedFileURL.path + "/") }
    }
}

/// A recusa cruzada entre as duas formas de instalar.
///
/// Dois serviços vigiando o mesmo River é o pior desfecho possível: os dois
/// disputam o cabo, os dois querem a porta 35493, e o que perder a disputa fica
/// mudo sem ninguém perceber. O caminho da tela recusa enquanto o outro existir.
public enum InstalacaoPelaLinhaDeComando {
    public static let plistDoSistema = "/Library/LaunchDaemons/com.river.unifi-bridge.plist"

    public static func existe(fileManager: FileManager = .default,
                              caminho: String = plistDoSistema) -> Bool {
        fileManager.fileExists(atPath: caminho)
    }
}
