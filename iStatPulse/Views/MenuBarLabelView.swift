//
//  MenuBarLabelView.swift
//  iStatPulse
//
//  Compact menu bar label with CPU + network throughput.
//

import SwiftUI
import Combine

#if os(macOS)

struct MenuBarLabelView: View {
    @StateObject private var viewModel = MenuBarLabelViewModel()

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "chart.bar.doc.horizontal")
                .font(.system(size: 12, weight: .medium))
            Text(viewModel.labelText)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
        }
        .onAppear { viewModel.start() }
        .onDisappear { viewModel.stop() }
    }
}

@MainActor
final class MenuBarLabelViewModel: ObservableObject {
    @Published private(set) var labelText: String = "Loading…"

    private let metricsService: SystemMetricsServiceProtocol
    private var cancellables = Set<AnyCancellable>()

    init(metricsService: SystemMetricsServiceProtocol = SystemMetricsService()) {
        self.metricsService = metricsService
        metricsService.metricsPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] metrics in
                self?.labelText = Self.formatLabel(metrics)
            }
            .store(in: &cancellables)
    }

    func start() {
        metricsService.startPolling()
    }

    func stop() {
        metricsService.stopPolling()
    }

    private static func formatLabel(_ metrics: SystemMetrics) -> String {
        let cpu = "CPU \(Int(metrics.cpu.usagePercent))%"
        let temp = metrics.cpu.temperatureCelsius.map { " \(Int($0))°" } ?? ""
        if let net = metrics.network {
            let up = formattedBytes(net.sentBytesPerSecond)
            let down = formattedBytes(net.receivedBytesPerSecond)
            return "\(cpu)\(temp)  ↑ \(up)/s ↓ \(down)/s"
        }
        return "\(cpu)\(temp)"
    }

    private static func formattedBytes(_ bytes: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }
}

#endif
