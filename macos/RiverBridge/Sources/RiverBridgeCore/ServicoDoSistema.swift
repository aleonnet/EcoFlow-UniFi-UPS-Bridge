// O serviço que mora DENTRO do aplicativo: registrar, autorizar e remover.
//
// Por que isto existe: arrastar o programa para Aplicativos põe o programa lá,
// e mais nada. O serviço que vigia a energia vai junto dentro do pacote
// (`Contents/Library/LaunchDaemons/`), mas alguém precisa registrá-lo — e quem
// faz isso é o próprio programa, com o `ServiceManagement` da Apple.
//
// Documentação da Apple, citada literalmente (lida em 2026-09-05).
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
//                      Management framework…"
//   .enabled          "The service has been successfully registered and is
//                      eligible to run."
//   .requiresApproval "The service has been successfully registered, but the
//                      user needs to take action in System Preferences." … "The
//                      framework also returns this status if the user revokes
//                      consent for the service to run in System Settings."
//   .notFound         "An error occurred and the framework couldn't find this
//                      service."
//
// QUANDO registrar e ONDE pedir a autorização — "Updating helper executables
// from earlier versions of macOS":
//
//   "If your app can't run or operate correctly without helper executables,
//    check the authorization status at launch. If helper executables don't have
//    authorization, alert the user, and call openSystemSettingsLoginItems() to
//    suggest that they update the System Settings."
//
// E as Human Interface Guidelines (Onboarding; Privacy):
//
//   "If your app or game needs access to private data or resources before it
//    can function, consider integrating the permission request into your
//    onboarding flow."
//   "Avoid requesting permission at launch unless the data or resource is
//    required for your app to function."
//
// O serviço É o programa: sem ele, nada é vigiado. Logo o registro acontece
// sozinho na abertura, e a autorização é pedida na ABERTURA — no aviso do topo
// do painel, com o botão que leva aos Ajustes do Sistema — e não num botão
// escondido em Ajustes. Até a 0.8.0 havia um botão "Instalar o serviço" dentro
// de Ajustes › Serviço; o dono abriu o programa no Mac mini, não achou nada na
// abertura, e chamou o que era (2026-09-05).
//
// E o que a autorização É: um ato do macOS, uma vez, que o certificado do
// programa NÃO dispensa — o certificado prova quem assinou, não que o dono quer
// um serviço de sistema permanente. O macOS mostra uma notificação ("River
// Bridge can run in the background for all users. Do you want to allow this?")
// e o mesmo interruptor em Ajustes do Sistema › Geral › Itens de Início de
// Sessão; os dois pedem a senha de administrador.
//
// `register()` não termina o trabalho — ele o COMEÇA, e o estado fica esperando
// autorização até o dono agir. Uma tela que dissesse "instalado" ali estaria
// mentindo, e o dono descobriria isso na próxima queda de energia.
//
// E `unregister()`: "Unregisters the service so the system no longer launches
// it" — e "if the service … is currently running it, the system terminates it".
//
// Este arquivo é a parte testável: os estados, as frases nas DUAS línguas e as
// regras de qual ato cada estado pede. Quem fala com o `ServiceManagement` de
// verdade é a camada de tela, que não entra em teste.
//
// Toda frase daqui é um PAR (português, inglês): até a 0.8.0 metade delas saía
// só em português, e no Mac mini (em inglês) a tela misturava as duas línguas
// no mesmo cartão — visto pelo dono em 2026-09-05.

import Foundation

/// O ato que a tela oferece para um estado do serviço.
public enum AcaoDoServico: Sendable, Equatable {
    /// O registro automático da abertura falhou: tentar de novo.
    case registrar
    /// O macOS espera a autorização: levar o dono aos Ajustes do Sistema.
    case abrirAjustesDoSistema

    public var rotulo: String { rotulo(emPortugues: L10n.cachedIsPT) }

    public func rotulo(emPortugues pt: Bool) -> String {
        switch self {
        case .registrar:
            return pt ? "Registrar de novo" : "Register again"
        case .abrirAjustesDoSistema:
            return pt ? "Abrir Ajustes do Sistema" : "Open System Settings"
        }
    }
}

/// Em que pé está o serviço, na língua do dono.
public enum EstadoDoServico: String, Sendable, CaseIterable {
    /// Nunca foi registrado nesta máquina (ou o registro da abertura falhou).
    case naoInstalado
    /// Registrado, e esperando o dono autorizar no macOS.
    case esperandoAprovacao
    /// Registrado e no ar.
    case noAr
    /// O sistema respondeu `.notFound`: "An error occurred and the framework
    /// couldn't find this service". (Desligar nos Ajustes do Sistema NÃO cai
    /// aqui: a Apple diz que revogar o consentimento devolve `.requiresApproval`.)
    case naoEncontradoPeloSistema
    /// Existe uma instalação pela LINHA DE COMANDO nesta máquina.
    case instaladoPelaLinhaDeComando
    /// O programa está rodando de fora de Aplicativos (do disco de instalação,
    /// de Downloads…): um serviço registrado dali apontaria para um caminho que
    /// some ao ejetar o disco ou mover o arquivo. Nada é registrado até ele
    /// estar em Aplicativos.
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
                  + "não sumir em alguns segundos, o macOS recusou o registro: toque em "
                  + "Registrar de novo. Até lá, a energia não está sendo vigiada."
                : "River Bridge registers the service by itself when it opens. If this "
                  + "message does not go away in a few seconds, macOS refused the "
                  + "registration: click Register again. Until then, the power is not "
                  + "being watched."
        case .esperandoAprovacao:
            return pt
                ? "O macOS pergunta, uma vez, se o River Bridge pode rodar em segundo "
                  + "plano para vigiar a energia. Clique em Permitir na notificação, ou "
                  + "ligue o River Bridge em Ajustes do Sistema › Geral › Itens de Início "
                  + "de Sessão. Ele pede a sua senha de administrador. Até lá, a energia "
                  + "não está sendo vigiada."
                : "macOS asks once whether River Bridge may run in the background to "
                  + "watch the power. Click Allow on the notification, or turn River "
                  + "Bridge on in System Settings › General › Login Items. It asks for "
                  + "your administrator password. Until then, the power is not being "
                  + "watched."
        case .noAr:
            return pt
                ? "Ele sobe sozinho quando o computador liga, mesmo sem ninguém entrar "
                  + "na conta."
                : "It starts on its own when the computer boots, even before anyone "
                  + "logs in."
        case .naoEncontradoPeloSistema:
            return pt
                ? "O macOS respondeu que não encontra o serviço registrado. Toque em "
                  + "Registrar de novo; se continuar assim, use Remover completamente em "
                  + "Ajustes › Serviço e abra o programa outra vez. Até lá, a energia não "
                  + "está sendo vigiada."
                : "macOS answered that it can't find the registered service. Click "
                  + "Register again; if it stays this way, use Remove completely in "
                  + "Settings › Service and open the app once more. Until then, the power "
                  + "is not being watched."
        case .instaladoPelaLinhaDeComando:
            return pt
                ? "Esta máquina já tem o serviço instalado pelo comando de uma linha. "
                  + "Dois serviços disputando o mesmo cabo e a mesma porta é o pior "
                  + "desfecho possível — remova aquele antes (o desinstalador dele está "
                  + "em /usr/local/river-unifi-bridge/scripts) e volte aqui."
                : "This machine already has the service installed by the one-line "
                  + "command. Two services fighting over the same cable and the same "
                  + "port is the worst possible outcome — remove that one first (its "
                  + "uninstaller is in /usr/local/river-unifi-bridge/scripts) and come "
                  + "back."
        case .foraDeAplicativos:
            return pt
                ? "O programa está aberto de fora da pasta Aplicativos. Arraste-o para "
                  + "Aplicativos e abra-o de lá: o serviço que vigia a energia precisa de "
                  + "um lugar fixo para subir com o computador."
                : "The app is running from outside the Applications folder. Drag it to "
                  + "Applications and open it from there: the service that watches the "
                  + "power needs a fixed place to start with the computer."
        }
    }

    /// O registro (que a abertura faz sozinha) ainda precisa acontecer?
    public var precisaRegistrar: Bool {
        switch self {
        case .naoInstalado, .naoEncontradoPeloSistema: return true
        case .esperandoAprovacao, .noAr, .instaladoPelaLinhaDeComando, .foraDeAplicativos: return false
        }
    }

    /// Dá para remover por aqui agora?
    public var podeRemover: Bool {
        switch self {
        case .esperandoAprovacao, .noAr, .naoEncontradoPeloSistema: return true
        case .naoInstalado, .instaladoPelaLinhaDeComando, .foraDeAplicativos: return false
        }
    }

    /// O aviso da abertura aparece? Sim para tudo o que impede a vigilância —
    /// inclusive "mova para Aplicativos", que não tem botão: a frase diz o ato.
    public var avisaNaAbertura: Bool {
        switch self {
        case .naoInstalado, .esperandoAprovacao, .naoEncontradoPeloSistema, .foraDeAplicativos: return true
        case .noAr, .instaladoPelaLinhaDeComando: return false
        }
    }

    /// O ato que o aviso da ABERTURA oferece — a Apple manda checar na partida,
    /// avisar e levar aos Ajustes do Sistema (citação no alto do arquivo).
    /// `nil` = nada a fazer: o aviso não aparece.
    public var acaoNaAbertura: AcaoDoServico? {
        switch self {
        case .naoInstalado, .naoEncontradoPeloSistema: return .registrar
        case .esperandoAprovacao: return .abrirAjustesDoSistema
        case .noAr, .instaladoPelaLinhaDeComando, .foraDeAplicativos: return nil
        }
    }
}

/// O que "Remover completamente" apaga — a lista que a confirmação mostra.
///
/// Desde a 0.8.0 arrastar o programa para o Lixo faz o mesmo: o serviço vigia
/// onde o pacote está e se retira sozinho. Este botão é o mesmo ato sem jogar
/// o programa fora — para quem quer reinstalar do zero, por exemplo.
public struct RemocaoCompleta: Sendable, Equatable {
    public var itens: [String]

    public init(estadoExiste: Bool, configuracaoDoNutExiste: Bool) {
        var lista = [L10n.t("o registro do serviço no sistema (ele para de subir no boot)",
                            "the service's registration (it stops starting at boot)")]
        if estadoExiste {
            lista.append(L10n.t("a chave que o serviço criou para o console, e a identidade dele",
                                "the key the service created for the console, and its identity"))
            lista.append(L10n.t("as senhas das contas do no-break",
                                "the passwords of the UPS accounts"))
            lista.append(L10n.t("o histórico e a lista de dispositivos protegidos",
                                "the history and the list of protected devices"))
        }
        if configuracaoDoNutExiste {
            lista.append(L10n.t("o trecho que o serviço escreveu na configuração do no-break",
                                "the section the service wrote in the UPS configuration"))
        }
        self.itens = lista
    }

    public var pergunta: String {
        L10n.t("Remover o River Bridge por completo?", "Remove River Bridge completely?")
    }

    public var aviso: String {
        L10n.t("Isto apaga, sem volta:\n", "This erases, for good:\n")
            + itens.map { "• \($0)" }.joined(separator: "\n")
            + L10n.t("\n\nO programa em si continua em Aplicativos — arraste-o para o Lixo "
                     + "depois, se quiser.",
                     "\n\nThe app itself stays in Applications — drag it to the Trash "
                     + "afterwards, if you want.")
    }

    /// O que acontece ao arrastar o programa para o Lixo — dito ANTES.
    ///
    /// Até a 0.7.0 esta frase avisava o contrário: o Lixo não removia nada, o
    /// processo seguia vivo de dentro do Lixo e a chave do console e as senhas
    /// ficavam no disco (medido pelo dono no Mac mini, 2026-09-05). O macOS não
    /// faz isso sozinho; desde a 0.8.0 o serviço faz (remocao.py).
    public static var avisoDoLixo: String {
        L10n.t("Arrastar o programa para o Lixo remove tudo: o serviço percebe, "
               + "para de vigiar, apaga a chave do console, as senhas e o histórico, "
               + "e se desregistra sozinho. Este botão faz o mesmo sem jogar o "
               + "programa fora.",
               "Dragging the app to the Trash removes everything: the service notices, "
               + "stops watching, erases the console key, the passwords and the "
               + "history, and unregisters itself. This button does the same without "
               + "throwing the app away.")
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
