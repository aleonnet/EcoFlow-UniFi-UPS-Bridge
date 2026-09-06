// A paleta do estado de energia — as seis triplas RGB que o app (Theme.swift) e
// o widget pintam. Sem SwiftUI de propósito: o Core não sabe o que é `Color`; quem
// desenha constrói a cor daqui. Uma fonte: o widget de baterias com a cor de
// "na bateria" diferente da do painel seria um segundo vocabulário.

import Foundation

public enum Paleta {
    public struct RGB: Equatable, Sendable {
        public let r: Double
        public let g: Double
        public let b: Double
        public init(_ r: Double, _ g: Double, _ b: Double) { self.r = r; self.g = g; self.b = b }
    }

    /// Na tomada: verde-água → azul.
    public static let tomada: [RGB] = [RGB(0.20, 0.85, 0.62), RGB(0.10, 0.60, 0.95)]
    /// Na bateria: âmbar → laranja.
    public static let bateria: [RGB] = [RGB(1.00, 0.72, 0.25), RGB(1.00, 0.42, 0.22)]
    /// Bateria baixa: vermelho → vinho.
    public static let baixa: [RGB] = [RGB(1.00, 0.36, 0.36), RGB(0.80, 0.12, 0.30)]

    public static func doEstado(naBateria: Bool, baixa: Bool) -> [RGB] {
        baixa ? Self.baixa : (naBateria ? bateria : tomada)
    }
}
