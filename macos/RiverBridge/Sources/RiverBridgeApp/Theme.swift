// Design tokens + atmosphere. The whole app breathes with the power state:
// the aurora background drifts mint on line power, amber on battery, red on
// low battery. Glass panels float above it (Liquid Glass, macOS 26).

import RiverBridgeCore
import SwiftUI

enum Theme {
    static let onlineColors = [
        Color(red: 0.20, green: 0.85, blue: 0.62),
        Color(red: 0.10, green: 0.60, blue: 0.95),
    ]
    static let batteryColors = [
        Color(red: 1.00, green: 0.72, blue: 0.25),
        Color(red: 1.00, green: 0.42, blue: 0.22),
    ]
    static let lowColors = [
        Color(red: 1.00, green: 0.36, blue: 0.36),
        Color(red: 0.80, green: 0.12, blue: 0.30),
    ]

    static func colors(onBattery: Bool, low: Bool) -> [Color] {
        low ? lowColors : (onBattery ? batteryColors : onlineColors)
    }

    static func accentGradient(onBattery: Bool, lowBattery: Bool) -> LinearGradient {
        LinearGradient(
            colors: colors(onBattery: onBattery, low: lowBattery),
            startPoint: .topLeading, endPoint: .bottomTrailing
        )
    }

    static func accentColor(onBattery: Bool, lowBattery: Bool) -> Color {
        colors(onBattery: onBattery, low: lowBattery)[0]
    }
}

// MARK: - Aurora atmosphere

/// Slow-drifting blurred light field behind the glass. Reduce Motion pins it.
struct AuroraBackground: View {
    var store: TelemetryStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        // Restraint pass (owner's critique 2026-08-31): the aurora is an
        // ACCENT at the window's edges, never a wash — the neutral system
        // ground stays dominant so the glass reads as glass on top of it.
        let palette = Theme.colors(onBattery: store.isOnBattery, low: store.isLowBattery)
        TimelineView(.animation(minimumInterval: 1 / 20, paused: reduceMotion)) { context in
            let t = reduceMotion ? 0 : context.date.timeIntervalSinceReferenceDate / 16
            Canvas { canvas, size in
                canvas.addFilter(.blur(radius: 95))
                blob(&canvas, size, palette[0].opacity(0.20),
                     cx: 0.12 + 0.06 * sin(t), cy: 0.10 + 0.05 * cos(t * 1.3), r: 0.38)
                blob(&canvas, size, palette[1].opacity(0.14),
                     cx: 0.92 + 0.05 * cos(t * 0.8), cy: 0.85 + 0.06 * sin(t * 1.1), r: 0.42)
                blob(&canvas, size, palette[0].opacity(0.09),
                     cx: 0.85 + 0.07 * sin(t * 0.6 + 2), cy: 0.10 + 0.04 * cos(t + 1), r: 0.26)
            }
            // Tint, not opaque paint: the window's material shows through
            // (translucent app — owner 2026-08-31); the near-black/near-white
            // identity survives as a wash over the blurred desktop.
            .background(
                scheme == .dark
                    ? Color(white: 0.045).opacity(0.35)
                    : Color(white: 0.94).opacity(0.35)
            )
        }
        .animation(.easeInOut(duration: 1.2), value: store.isOnBattery)
        .ignoresSafeArea()
    }

    private func blob(_ canvas: inout GraphicsContext, _ size: CGSize, _ color: Color,
                      cx: Double, cy: Double, r: Double) {
        let radius = size.width * r
        let rect = CGRect(
            x: size.width * cx - radius / 2, y: size.height * cy - radius / 2,
            width: radius, height: radius
        )
        canvas.fill(Path(ellipseIn: rect), with: .color(color))
    }
}

// MARK: - Hover

/// The house hover: a gentle lift with a colored halo. Reduce Motion keeps
/// the halo but drops the scale.
struct HoverLift: ViewModifier {
    var glow: Color = .white
    var scale: CGFloat = 1.02
    @State private var hovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .scaleEffect(hovering && !reduceMotion ? scale : 1)
            .shadow(color: glow.opacity(hovering ? 0.30 : 0), radius: 14)
            .animation(.spring(duration: 0.25), value: hovering)
            // Whole-bounds hit target: without this, transparent areas of a
            // card ignore the cursor (owner's report — hover dead on empty
            // space). Class fix for every hoverLift user.
            .contentShape(Rectangle())
            .onHover { hovering = $0 }
    }
}

extension View {
    func hoverLift(glow: Color = .white, scale: CGFloat = 1.02) -> some View {
        modifier(HoverLift(glow: glow, scale: scale))
    }
}

// MARK: - Type voice

extension Text {
    /// Uppercase tracked caption — the label voice of the whole app.
    func eyebrow() -> some View {
        self.font(.caption2.weight(.semibold))
            .textCase(.uppercase)
            .kerning(1.4)
            .foregroundStyle(.secondary)
    }
}

struct HeroNumber: ViewModifier {
    let value: String

    func body(content: Content) -> some View {
        content
            .font(.system(size: 46, weight: .semibold, design: .rounded))
            .monospacedDigit()
            .contentTransition(.numericText())
    }
}

/// A cor de cada FAMÍLIA de evento de dispositivo. Mora aqui, e não no Core,
/// porque `Color` é SwiftUI — o Core declara o tom, a camada de tela o pinta.
/// Escolhas: a família é roxa como antes; o desfecho que importa é vermelho;
/// o que foi barrado é laranja; ligar/desligar é índigo e o religamento é menta.
/// Mudança declarada: na TIMELINE, ARMED/DISARMED passam de roxo a índigo e o
/// WoL a menta — iguais à legenda do gráfico, que até aqui divergia da lista.
/// **A paleta. O único lugar do programa que nomeia uma tinta.**
///
/// Fora daqui, nada diz "laranja" nem "vermelho": a tela pede um PAPEL
/// (`Cor.atencao`, `Cor.perigo`) e esta tabela decide com que tinta ele é
/// pintado. Antes eram 57 nomes de cor espalhados por 12 arquivos, e a mesma
/// ideia saía de uma cor num lugar e de outra noutro — sem nada com que
/// comparar. A cena S55 do portão reprova nome de cor fora deste arquivo.
enum Cor {
    /// Sem nada a dizer — desligado, ausente, apoio de texto.
    static let neutro = Color.secondary
    /// Está bem: no ar, provado, feito.
    static let bom = Color.green
    /// Ligado em ensaio: avisa e não age.
    static let ensaio = Color.blue
    /// Falta uma condição sua, ou algo foi barrado.
    static let atencao = Color.orange
    /// O desfecho que importa: desligou, falhou, está armado de verdade.
    static let perigo = Color.red
    /// Barrado por uma cerca da configuração — a família da proteção.
    static let bloqueio = Color.purple
    /// Ligar e desligar, como um interruptor.
    static let alternancia = Color.indigo
    /// Religar pela rede.
    static let religamento = Color.mint
    /// Bateria baixa, na legenda do gráfico.
    static let bateriaBaixa = Color.yellow
}

/// A cor de cada FAMÍLIA de evento de dispositivo — pelo papel, na paleta acima.
///
/// Escolhas declaradas: a família é a do bloqueio; o desfecho que importa é
/// perigo; o barrado é atenção; ligar/desligar é alternância e o religamento é o
/// dele. Na TIMELINE, ARMED/DISARMED passam de roxo a índigo e o WoL a menta —
/// iguais à legenda do gráfico, que até aqui divergia da lista.
extension DeviceEventTone {
    var color: Color {
        switch self {
        case .family: Cor.bloqueio
        case .danger: Cor.perigo
        case .warning: Cor.atencao
        case .toggle: Cor.alternancia
        case .wake: Cor.religamento
        }
    }
}

/// E o tom de um ESTADO de dispositivo, na mesma paleta.
extension DeviceStateText.Tom {
    var color: Color {
        switch self {
        case .neutro: Cor.neutro
        case .ensaio: Cor.ensaio
        case .atencao: Cor.atencao
        case .perigo: Cor.perigo
        case .bloqueio: Cor.bloqueio
        }
    }
}
