// O computador ou servidor via SSH como plugin de TELA: a folha da instância
// (variante do motor SSH com o comando de desligamento de lista fechada), o
// detalhe honesto do cartão de saúde e os estados do motor, na voz "máquina".

import RiverBridgeCore
import SwiftUI

struct SshHostPlugin: DevicePluginUI {
    var type: DeviceTypeDescriptor { .sshHost }

    func settingsSheet(mode: DeviceSheetMode, store: TelemetryStore, hostSize: CGSize,
                       onBack: (() -> Void)?, onClose: @escaping (_ createdID: String?) -> Void) -> AnyView {
        AnyView(SshHostSheet(mode: mode, store: store, hostSize: hostSize, onBack: onBack, onClose: onClose))
    }

    func healthDetail(detail: DeviceDetail?, chainPresent: Bool) -> String? {
        SshEngineText.healthDetail(detail: detail, chainPresent: chainPresent)
    }

    func badge(state: String?) -> (String, Color)? {
        SshEngineText.badge(state: state, console: false)
    }
}
