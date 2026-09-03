// A folha do computador ou servidor via SSH: a variante `.sshHost` da folha do
// motor SSH (SshDeviceSheet) — grupos Dispositivo, Máquina e chave,
// Desligamento (o comando vem de uma lista fechada do serviço, num seletor,
// nunca de um campo de texto) e Limiares. Sem MAC de religamento.

import RiverBridgeCore
import SwiftUI

struct SshHostSheet: View {
    let mode: DeviceSheetMode
    var store: TelemetryStore
    var hostSize: CGSize
    var onBack: (() -> Void)?
    var onClose: (_ createdID: String?) -> Void

    var body: some View {
        SshDeviceSheet(variant: .sshHost, mode: mode, store: store, hostSize: hostSize,
                       onBack: onBack, onClose: onClose)
    }
}
