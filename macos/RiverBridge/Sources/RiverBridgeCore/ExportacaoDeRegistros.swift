// "Compartilhar…" os registros (0.9.0): o que vai no pacote, como ele se chama e
// como se comprime — a parte pura, testável sem rede e sem disco.
//
// O pacote leva três arquivos: `eventos.csv` e `amostras.csv` (o serviço os
// exporta pelas rotas `.csv`; ele é o dono do SQLite e das colunas) e
// `diario.log` (uma cópia do diário do serviço, quando legível). Compressão pelo
// `ditto -c -k` do macOS — é o que o Finder usa em "Comprimir", e o que qualquer
// Mac abre com dois cliques (ditto(1): "-c Create an archive"; "-k Create or
// extract from a PKZip archive"; "--sequesterRsrc" guarda os metadados numa
// pasta __MACOSX em vez de arquivos ._; "--keepParent" embrulha a pasta).

import Foundation

public enum ExportacaoDeRegistros {
    public static let caminhoDoDiario = "/Library/Logs/river-unifi-bridge.log"
    public static let nomeDosEventos = "eventos.csv"
    public static let nomeDasAmostras = "amostras.csv"
    public static let nomeDoDiario = "diario.log"

    /// `RiverBridge-registros-2026-09-06-1355` — o instante no fuso local, sem
    /// caracteres que o Finder ou um e-mail estranhem.
    public static func nomeDoPacote(agora: Date, calendario: Calendar = .current) -> String {
        let c = calendario.dateComponents([.year, .month, .day, .hour, .minute], from: agora)
        return String(format: "RiverBridge-registros-%04d-%02d-%02d-%02d%02d",
                      c.year ?? 0, c.month ?? 0, c.day ?? 0, c.hour ?? 0, c.minute ?? 0)
    }

    /// A linha de comando do `ditto` que transforma a pasta no `.zip`.
    public static func argvDoDitto(pasta: URL, zip: URL) -> [String] {
        ["/usr/bin/ditto", "-c", "-k", "--sequesterRsrc", "--keepParent", pasta.path, zip.path]
    }

    /// O que dizer quando o diário não entrou (ilegível, ou serviço instalado
    /// pela linha de comando noutra pasta). `nil` quando entrou.
    public static func rodape(diarioIncluido: Bool, emPortugues: Bool = L10n.cachedIsPT) -> String? {
        guard !diarioIncluido else { return nil }
        return emPortugues
            ? "O pacote foi sem o diário do serviço: o arquivo não está legível nesta conta."
            : "The package went without the service diary: the file is not readable from this account."
    }

    /// A faixa de tempo do recorte da barra de Eventos, como as rotas CSV a
    /// esperam. `nil` em `to` = até agora (o serviço decide).
    public static func faixa(from: Int?, to: Int?) -> (from: Int, to: Int?) {
        (from ?? 0, to)
    }
}
