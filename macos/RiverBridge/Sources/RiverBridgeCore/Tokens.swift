// Os tokens de espaço e raio da casa — UMA escala para o app e para o widget.
//
// Moravam em DesignSystem.swift (alvo do app); vieram para o Core na 0.10.0
// porque o widget é outro alvo e outro processo, e uma segunda escala divergiria
// sozinha (a mesma razão que criou a escala: treze valores em treze momentos,
// medidos em 2026-09-05). Os valores são os mesmos — TokensTests os fixa um a um.
// A grade de 2 pt e o que NÃO entra aqui estão explicados em DesignSystem.swift.

import Foundation

public enum Espaco {
    /// Colado.
    public static let nenhum: CGFloat = 0
    /// Entre uma linha e a legenda dela.
    public static let fio: CGFloat = 2
    /// Entre um ícone e o texto dele.
    public static let micro: CGFloat = 4
    /// Entre elementos de um mesmo selo.
    public static let mini: CGFloat = 6
    /// Entre linhas irmãs.
    public static let pequeno: CGFloat = 8
    /// O padrão de uma linha de ajuste.
    public static let medio: CGFloat = 10
    /// Entre blocos de uma folha.
    public static let confortavel: CGFloat = 12
    /// Dentro de um cartão.
    public static let cartao: CGFloat = 14
    /// Entre cartões.
    public static let largo: CGFloat = 16
    /// Entre grupos de uma tela.
    public static let secao: CGFloat = 18
    /// Margem de janela.
    public static let janela: CGFloat = 20
    /// Respiro de uma folha inteira.
    public static let respiro: CGFloat = 24
}

/// Raio de canto, na mesma grade.
public enum Raio {
    /// Um fio — divisória arredondada.
    public static let fio: CGFloat = 1
    public static let mini: CGFloat = 6
    public static let selo: CGFloat = 8
    public static let cartao: CGFloat = 12
    public static let largo: CGFloat = 14
    public static let painel: CGFloat = 16
    public static let janela: CGFloat = 18
}

