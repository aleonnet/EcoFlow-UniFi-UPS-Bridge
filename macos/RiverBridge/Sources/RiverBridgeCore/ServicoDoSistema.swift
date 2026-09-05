// O serviço que mora DENTRO do aplicativo: instalar, aprovar e remover.
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
//
// E os estados que ele devolve:
//
//   .notRegistered    "The service hasn't registered with the Service
//                      Management framework…"
//   .enabled          "The service has been successfully registered and is
//                      eligible to run."
//   .requiresApproval "The service has been successfully registered, but the
//                      user needs to take action in System Preferences."
//   .notFound         "An error occurred and the framework couldn't find this
//                      service."
//
// Ou seja: `register()` não termina o trabalho — ele o COMEÇA, e o estado fica
// esperando aprovação até o dono ir aos Ajustes do Sistema. Uma tela que
// dissesse "instalado" ali estaria mentindo, e o dono descobriria isso na
// próxima queda de energia.
//
// E `unregister()`: "Unregisters the service so the system no longer launches
// it" — e "if the service … is currently running it, the system terminates it".
//
// Este arquivo é a parte testável: os estados, as frases e as regras de quando
// cada botão pode ser tocado. Quem fala com o `ServiceManagement` de verdade é
// a camada de tela, que não entra em teste.

import Foundation

/// Em que pé está o serviço, na língua do dono.
public enum EstadoDoServico: String, Sendable, CaseIterable {
    /// Nunca foi registrado nesta máquina.
    case naoInstalado
    /// Registrado, e esperando o dono aprovar nos Ajustes do Sistema.
    case esperandoAprovacao
    /// Registrado e no ar.
    case noAr
    /// O dono desligou nos Ajustes do Sistema (ou o sistema o desabilitou).
    case desligadoPeloSistema
    /// Existe uma instalação pela LINHA DE COMANDO nesta máquina.
    case instaladoPelaLinhaDeComando

    public var titulo: String {
        switch self {
        case .naoInstalado: return "O serviço ainda não foi instalado"
        case .esperandoAprovacao: return "Falta aprovar nos Ajustes do Sistema"
        case .noAr: return "O serviço está no ar"
        case .desligadoPeloSistema: return "O serviço está desligado"
        case .instaladoPelaLinhaDeComando: return "O serviço já está instalado por fora"
        }
    }

    public var explicacao: String {
        switch self {
        case .naoInstalado:
            return "Enquanto ele não estiver no ar, ninguém está vigiando a energia. "
                 + "Instalar leva um toque e uma aprovação sua."
        case .esperandoAprovacao:
            return "O macOS pede que você autorize um serviço novo. Abra os Ajustes do "
                 + "Sistema, em Geral › Itens de Início de Sessão, e ligue o River Bridge. "
                 + "Até lá, a energia não está sendo vigiada."
        case .noAr:
            return "Ele sobe sozinho quando o computador liga, mesmo sem ninguém entrar "
                 + "na conta."
        case .desligadoPeloSistema:
            return "Alguém o desligou nos Ajustes do Sistema. Ligue-o de volta em "
                 + "Geral › Itens de Início de Sessão, ou remova-o por completo aqui."
        case .instaladoPelaLinhaDeComando:
            return "Esta máquina já tem o serviço instalado pelo comando de uma linha. "
                 + "Dois serviços disputando o mesmo cabo e a mesma porta é o pior "
                 + "desfecho possível — remova aquele antes (o desinstalador dele está "
                 + "em /usr/local/river-unifi-bridge/scripts) e volte aqui."
        }
    }

    /// Dá para instalar por aqui agora?
    public var podeInstalar: Bool {
        switch self {
        case .naoInstalado, .desligadoPeloSistema: return true
        case .esperandoAprovacao, .noAr, .instaladoPelaLinhaDeComando: return false
        }
    }

    /// Dá para remover por aqui agora?
    public var podeRemover: Bool {
        switch self {
        case .esperandoAprovacao, .noAr, .desligadoPeloSistema: return true
        case .naoInstalado, .instaladoPelaLinhaDeComando: return false
        }
    }

    /// A tela oferece o atalho para os Ajustes do Sistema?
    public var mostraAjustesDoSistema: Bool {
        self == .esperandoAprovacao || self == .desligadoPeloSistema
    }
}

/// O que "Remover completamente" apaga — a lista que a confirmação mostra.
///
/// Arrastar o programa para o Lixo NÃO faz nada disto: o serviço continua
/// registrado, e o estado (chave do console, senhas, histórico) continua no
/// disco. O dono pediu que existisse um caminho que limpasse de verdade.
public struct RemocaoCompleta: Sendable, Equatable {
    public var itens: [String]

    public init(estadoExiste: Bool, configuracaoDoNutExiste: Bool) {
        var lista = ["o registro do serviço no sistema (ele para de subir no boot)"]
        if estadoExiste {
            lista.append("a chave que o serviço criou para o console, e a identidade dele")
            lista.append("as senhas das contas do no-break")
            lista.append("o histórico e a lista de dispositivos protegidos")
        }
        if configuracaoDoNutExiste {
            lista.append("o trecho que o serviço escreveu na configuração do no-break")
        }
        self.itens = lista
    }

    public var pergunta: String {
        "Remover o River Bridge por completo?"
    }

    public var aviso: String {
        "Isto apaga, sem volta:\n" + itens.map { "• \($0)" }.joined(separator: "\n")
            + "\n\nO programa em si continua em Aplicativos — arraste-o para o Lixo "
            + "depois, se quiser."
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
