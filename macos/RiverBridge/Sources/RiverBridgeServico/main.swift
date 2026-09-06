// river-bridge-servico — a mão do serviço sobre o próprio registro no macOS.
//
// Por que existe: o registro do serviço (Itens de Início de Sessão) só é
// desfeito por `SMAppService.unregister()`, e a Apple é literal: "Unregisters
// the service so the system no longer launches it. … If the service is
// currently running it, the system terminates it." Um `launchctl bootout` para
// o processo, mas o registro fica — foi o que o dono viu no Mac mini em
// 2026-09-06: o programa no Lixo e o interruptor ainda ligado nos Ajustes do
// Sistema. E `unregister()` só pode ser chamado por um processo DESTE pacote
// ("The property list name must correspond to a property list in the calling
// app's Contents/Library/LaunchDaemons directory"). O serviço em Python não é;
// este executável, dentro de Contents/MacOS, é.
//
// Uso: river-bridge-servico [status|unregister]   (padrão: status)
// Saída: linhas `chave=valor`, para o diário do serviço. Código 0 = ok.

import Foundation
import ServiceManagement

let servico = SMAppService.daemon(plistName: "com.river.unifi-bridge.plist")

func nome(_ estado: SMAppService.Status) -> String {
    switch estado {
    case .notRegistered: return "notRegistered"
    case .enabled: return "enabled"
    case .requiresApproval: return "requiresApproval"
    case .notFound: return "notFound"
    @unknown default: return "desconhecido(\(estado.rawValue))"
    }
}

setvbuf(stdout, nil, _IONBF, 0)   // sem buffer: quem lê é um cano, não um terminal
print("pacote=\(Bundle.main.bundleURL.path)")
print("status=\(nome(servico.status))")

switch CommandLine.arguments.dropFirst().first ?? "status" {
case "status":
    exit(0)
case "unregister":
    do {
        try servico.unregister()
        print("unregister=ok")
        print("status_depois=\(nome(servico.status))")
        exit(0)
    } catch {
        print("unregister=erro: \(error.localizedDescription)")
        exit(1)
    }
default:
    print("uso: river-bridge-servico [status|unregister]")
    exit(2)
}
