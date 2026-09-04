// janelas.swift — lista as janelas na tela de um aplicativo, por id, sem tocar
// no foco de ninguém. Existe porque a captura de validação NÃO PODE ativar o
// app: ativar rouba o teclado do dono (aconteceu duas vezes, 2026-09-03), e as
// teclas dele foram parar dentro do campo Nome.
//
// Uso: swift tools/janelas.swift "<nome do dono da janela>"
// Saída: uma linha por janela — id<TAB>largura<TAB>altura<TAB>título
import CoreGraphics
import Foundation

let dono = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "River Bridge"
let lista = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements],
                                       kCGNullWindowID) as? [[String: Any]] ?? []
for janela in lista {
    guard let nome = janela[kCGWindowOwnerName as String] as? String, nome == dono,
          let id = janela[kCGWindowNumber as String] as? Int,
          let caixa = janela[kCGWindowBounds as String] as? [String: Double],
          let largura = caixa["Width"], let altura = caixa["Height"],
          largura > 200, altura > 200 else { continue }
    let titulo = janela[kCGWindowName as String] as? String ?? ""
    print("\(id)\t\(Int(largura))\t\(Int(altura))\t\(titulo)")
}
