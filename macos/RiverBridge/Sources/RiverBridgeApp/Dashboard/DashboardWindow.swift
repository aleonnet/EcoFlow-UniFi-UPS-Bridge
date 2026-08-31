// Main window: left = the ring + power flow (the "am I protected?" glance);
// right = tiles, charts with scrub, event timeline. Health and Settings live
// in tabs — one window, no maze.

import RiverBridgeCore
import SwiftUI

struct DashboardWindow: View {
    var store: TelemetryStore

    var body: some View {
        TabView {
            DashboardView(store: store)
                .tabItem { Label("Energia", systemImage: "bolt.fill") }
            HealthView(store: store)
                .tabItem { Label("Saúde", systemImage: "waveform.path.ecg") }
            SettingsView(store: store)
                .tabItem { Label("Ajustes", systemImage: "slider.horizontal.3") }
        }
        .background(.background)
    }
}

struct DashboardView: View {
    var store: TelemetryStore

    var body: some View {
        HStack(alignment: .top, spacing: 24) {
            VStack(spacing: 20) {
                EnergyRing(store: store)
                    .frame(width: 240, height: 240)
                    .padding(.top, 12)
                PowerFlowView(store: store)
                Spacer(minLength: 0)
            }
            .frame(width: 280)

            VStack(alignment: .leading, spacing: 16) {
                if case .serviceDown(let reason) = store.phase {
                    ConnectionBanner(reason: reason)
                }
                StatsGrid(store: store)
                ChartsView(store: store)
                EventsTimeline(store: store)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(20)
    }
}

struct ConnectionBanner: View {
    let reason: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 1) {
                Text("Serviço parado").font(.headline)
                Text(reason).font(.callout).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(12)
        .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
    }
}

struct StatsGrid: View {
    var store: TelemetryStore

    var body: some View {
        Grid(horizontalSpacing: 12, verticalSpacing: 12) {
            GridRow {
                StatTile(label: "Carga", value: store.powerText, symbol: "bolt.fill")
                StatTile(label: "Uso", value: store.loadText, symbol: "gauge.with.needle")
                StatTile(label: "Saída", value: store.outputVoltageText, symbol: "powerplug.fill")
            }
        }
    }
}

struct StatTile: View {
    let label: String
    let value: String
    let symbol: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                Image(systemName: symbol)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(label).eyebrow()
            }
            Text(value)
                .font(.system(.title2, design: .rounded).weight(.semibold))
                .monospacedDigit()
                .contentTransition(.numericText())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
    }
}
