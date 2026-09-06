// O botão "Compartilhar…" da barra de Eventos (0.9.0): monta um .zip com
// eventos.csv, amostras.csv e o diário do serviço, e então — só então — abre
// Salvar como… ou o painel de compartilhar do macOS.
//
// Ordem fixa, porque o painel precisa do arquivo pronto: clique → "Preparando…"
// (baixa os dois CSV do serviço, copia o diário, roda o ditto) → o painel. O
// `ShareLink` do SwiftUI não serve aqui: ele exige o item no momento em que é
// desenhado, e o pacote só existe depois do clique. `NSSharingServicePicker`
// (AppKit) é o mesmo painel do ícone de partilha do Finder, aberto na hora, com
// o arquivo pronto (doc: "NSSharingServicePicker — an object that presents a
// list of sharing services to the user").

import AppKit
import RiverBridgeCore
import SwiftUI

struct CompartilharRegistros: View {
    var store: TelemetryStore
    var period: EventPeriod
    var customFrom: Date
    var customTo: Date
    var narrow = false

    @State private var preparando = false
    @State private var aviso: String?
    @State private var ancora = AncoraDoPainel.Holder()

    var body: some View {
        VStack(alignment: .trailing, spacing: Espaco.micro) {
            Menu {
                Button(L10n.t("Salvar como…", "Save As…")) { Task { await exportar(.salvar) } }
                Button(L10n.t("Compartilhar…", "Share…")) { Task { await exportar(.compartilhar) } }
            } label: {
                HStack(spacing: Espaco.mini) {
                    if preparando {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "square.and.arrow.up")
                    }
                    if !narrow {
                        Text(preparando ? L10n.t("Preparando…", "Preparing…") : L10n.t("Compartilhar…", "Share…"))
                            .fixedSize()
                    }
                }
                .font(.callout)
                .padding(.horizontal, Espaco.medio)
                .padding(.vertical, Espaco.micro)
            }
            .menuStyle(.button)
            .buttonStyle(.glass)
            .disabled(preparando)
            .help(L10n.t("Salva ou compartilha os registros do recorte (eventos, amostras e o diário do serviço) num .zip",
                         "Saves or shares this range's records (events, samples and the service diary) as a .zip"))
            .background(AncoraDoPainel(holder: ancora))
            if let aviso {
                Text(aviso).font(.caption).foregroundStyle(Cor.atencao)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private enum Destino { case salvar, compartilhar }

    /// A faixa do recorte, a mesma que a lista de eventos mostra.
    private var faixa: (from: Int, to: Int?) {
        var from = period.fromTS()
        var to: Int?
        if period == .personalizado {
            from = Int(Calendar.current.startOfDay(for: customFrom).timeIntervalSince1970)
            to = Int(Calendar.current.startOfDay(for: customTo).addingTimeInterval(86400).timeIntervalSince1970) - 1
        }
        return ExportacaoDeRegistros.faixa(from: from, to: to)
    }

    @MainActor
    private func exportar(_ destino: Destino) async {
        guard let endpoint = ApiEndpoint.discover() else {
            aviso = L10n.t("Histórico indisponível — o programa não alcança o serviço.",
                           "History unavailable — the app can’t reach the service.")
            return
        }
        preparando = true
        aviso = nil
        defer { preparando = false }
        do {
            let (zip, diarioIncluido) = try await montarPacote(APIClient(endpoint: endpoint))
            aviso = ExportacaoDeRegistros.rodape(diarioIncluido: diarioIncluido)
            switch destino {
            case .salvar: salvar(zip)
            case .compartilhar: compartilhar(zip)
            }
        } catch {
            aviso = L10n.t("Histórico indisponível — o programa não alcança o serviço.",
                           "History unavailable — the app can’t reach the service.")
        }
    }

    /// Baixa, copia, comprime. Devolve o .zip e se o diário entrou.
    private func montarPacote(_ client: APIClient) async throws -> (URL, Bool) {
        let faixa = self.faixa
        let eventos = try await client.eventsLogCSV(from: faixa.from, to: faixa.to)
        let amostras = try await client.samplesCSV(from: faixa.from, to: faixa.to)
        let nome = ExportacaoDeRegistros.nomeDoPacote(agora: .now)
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("river-bridge-registros-\(UUID().uuidString)", isDirectory: true)
        let pasta = base.appendingPathComponent(nome, isDirectory: true)
        try FileManager.default.createDirectory(at: pasta, withIntermediateDirectories: true)
        try eventos.write(to: pasta.appendingPathComponent(ExportacaoDeRegistros.nomeDosEventos))
        try amostras.write(to: pasta.appendingPathComponent(ExportacaoDeRegistros.nomeDasAmostras))
        let diario = URL(fileURLWithPath: ExportacaoDeRegistros.caminhoDoDiario)
        var diarioIncluido = false
        if FileManager.default.isReadableFile(atPath: diario.path) {
            try? FileManager.default.copyItem(at: diario, to: pasta.appendingPathComponent(ExportacaoDeRegistros.nomeDoDiario))
            diarioIncluido = FileManager.default.fileExists(atPath: pasta.appendingPathComponent(ExportacaoDeRegistros.nomeDoDiario).path)
        }
        let zip = base.appendingPathComponent("\(nome).zip")
        let argv = ExportacaoDeRegistros.argvDoDitto(pasta: pasta, zip: zip)
        try await Task.detached {
            let processo = Process()
            processo.executableURL = URL(fileURLWithPath: argv[0])
            processo.arguments = Array(argv.dropFirst())
            try processo.run()
            processo.waitUntilExit()
            guard processo.terminationStatus == 0 else { throw APIError.notConnected }
        }.value
        return (zip, diarioIncluido)
    }

    @MainActor
    private func salvar(_ zip: URL) {
        let painel = NSSavePanel()
        painel.nameFieldStringValue = zip.lastPathComponent
        painel.canCreateDirectories = true
        painel.begin { resposta in
            guard resposta == .OK, let destino = painel.url else { return }
            try? FileManager.default.removeItem(at: destino)
            do {
                try FileManager.default.copyItem(at: zip, to: destino)
            } catch {
                aviso = L10n.t("Não foi possível salvar o pacote nessa pasta.", "The package could not be saved to that folder.")
            }
        }
    }

    @MainActor
    private func compartilhar(_ zip: URL) {
        let picker = NSSharingServicePicker(items: [zip])
        guard let view = ancora.view else { return }
        picker.show(relativeTo: view.bounds, of: view, preferredEdge: .minY)
    }
}

/// Uma vista AppKit vazia atrás do botão: o painel de compartilhar do macOS é
/// ancorado a uma NSView, e esta é a do botão.
private struct AncoraDoPainel: NSViewRepresentable {
    final class Holder { weak var view: NSView? }
    let holder: Holder

    func makeNSView(context: Context) -> NSView {
        let v = NSView(frame: .zero)
        holder.view = v
        return v
    }

    func updateNSView(_ nsView: NSView, context: Context) { holder.view = nsView }
}
