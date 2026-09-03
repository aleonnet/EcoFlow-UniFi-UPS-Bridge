// A folha do Console UniFi (UDR7): a variante `.udr7` da folha do motor SSH
// (SshDeviceSheet) — os grupos comuns mais o MAC de religamento. Desde
// 2026-09-03 é folha de INSTÂNCIA: lê e grava por /v1/devices/{id}, e a série
// esperada e o corte do River saíram daqui para o grupo "River" de Ajustes.

import RiverBridgeCore
import SwiftUI

struct Udr7SettingsSheet: View {
    let mode: DeviceSheetMode
    var store: TelemetryStore
    var hostSize: CGSize
    var onClose: () -> Void

    var body: some View {
        SshDeviceSheet(variant: .udr7, mode: mode, store: store, hostSize: hostSize, onClose: onClose)
    }
}
