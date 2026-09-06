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

    /// O prefixo das pastas de trabalho no diretório temporário. Cada exportação
    /// apaga as anteriores antes de criar a sua: o painel de compartilhar lê o
    /// arquivo depois que a função devolve, então apagar na hora não é seguro;
    /// apagar na exportação seguinte é.
    public static let prefixoDaPastaDeTrabalho = "river-bridge-registros-"

    public struct Pacote: Equatable, Sendable {
        public let zip: URL
        public let diarioIncluido: Bool
    }

    /// Monta o pacote: baixa os dois CSV, copia o diário quando legível, escreve
    /// tudo numa pasta nova e comprime. As dependências entram como funções para
    /// o caminho de falha ser testável sem rede e sem serviço: se um dos CSV não
    /// vier, a função lança ANTES de escrever qualquer arquivo — nunca um zip
    /// parcial.
    ///
    /// - `baixa`: devolve o CSV de um dos dois nomes (`nomeDosEventos`,
    ///   `nomeDasAmostras`) ou lança.
    /// - `diario`: o caminho do diário do serviço, ou `nil` para não incluir.
    /// - `comprime`: roda o argv do ditto (o app usa `Process`); lança se falhar.
    public static func montarPacote(
        em temporario: URL,
        agora: Date = .now,
        baixa: @Sendable (String) async throws -> Data,
        diario: URL?,
        comprime: @Sendable ([String]) async throws -> Void,
        fm: FileManager = .default
    ) async throws -> Pacote {
        // Primeiro o que pode falhar; só depois o disco.
        let eventos = try await baixa(nomeDosEventos)
        let amostras = try await baixa(nomeDasAmostras)

        apagarPacotesAnteriores(em: temporario, fm: fm)
        let nome = nomeDoPacote(agora: agora)
        let base = temporario.appendingPathComponent(prefixoDaPastaDeTrabalho + UUID().uuidString, isDirectory: true)
        let pasta = base.appendingPathComponent(nome, isDirectory: true)
        try fm.createDirectory(at: pasta, withIntermediateDirectories: true)
        try eventos.write(to: pasta.appendingPathComponent(nomeDosEventos))
        try amostras.write(to: pasta.appendingPathComponent(nomeDasAmostras))

        var diarioIncluido = false
        if let diario, fm.isReadableFile(atPath: diario.path) {
            let destino = pasta.appendingPathComponent(nomeDoDiario)
            try? fm.copyItem(at: diario, to: destino)
            diarioIncluido = fm.fileExists(atPath: destino.path)
        }

        let zip = base.appendingPathComponent("\(nome).zip")
        try await comprime(argvDoDitto(pasta: pasta, zip: zip))
        return Pacote(zip: zip, diarioIncluido: diarioIncluido)
    }

    /// Apaga as pastas de trabalho de exportações anteriores (só as nossas, pelo
    /// prefixo). Erro aqui não impede a exportação de agora.
    public static func apagarPacotesAnteriores(em temporario: URL, fm: FileManager = .default) {
        guard let itens = try? fm.contentsOfDirectory(at: temporario, includingPropertiesForKeys: nil) else { return }
        for item in itens where item.lastPathComponent.hasPrefix(prefixoDaPastaDeTrabalho) {
            try? fm.removeItem(at: item)
        }
    }
}
