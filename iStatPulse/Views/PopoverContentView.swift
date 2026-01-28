//
//  PopoverContentView.swift
//  iStatPulse
//
//  Created by Hasnain Bukhari on 28/1/2569 BE.
//

import SwiftUI

#if os(macOS)

struct PopoverContentView: View {
    @StateObject private var viewModel = PopoverViewModel()

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            if let metrics = viewModel.metrics {
                globalSummaryBar(metrics)
                metricsSections(metrics)
            } else {
                ProgressView("Loading…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            Spacer(minLength: 8)
            footer
        }
        .frame(width: 280, height: 380)
        .padding(20)
        .background(AppPalette.panel)
        .onAppear { viewModel.onAppear() }
        .onDisappear { viewModel.onDisappear() }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider()
                .background(AppPalette.neutralGray.opacity(0.3))
            HStack {
                Image(systemName: "power")
                    .font(.caption)
                    .foregroundStyle(AppPalette.neutralGray)
                Toggle("Launch at login", isOn: Binding(
                    get: { viewModel.launchAtLoginEnabled },
                    set: { _ = viewModel.setLaunchAtLogin($0) }
                ))
                .toggleStyle(.switch)
                .controlSize(.small)
            }
            .font(.caption)
            if let hint = viewModel.sensorsUnavailableHint {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.caption2)
                        .foregroundStyle(AppPalette.warningOrange)
                    Text(hint)
                        .font(.caption2)
                        .foregroundStyle(AppPalette.neutralGray)
                }
            }
        }
    }

    private var header: some View {
        HStack {
            Image(systemName: "chart.bar.doc.horizontal")
                .font(.title2)
                .foregroundStyle(AppPalette.neutralGray)
            Text("iStat Pulse")
                .font(.headline)
                .foregroundStyle(.primary)
        }
        .padding(.bottom, 4)
    }

    /// Compact global summary bar (reference: iStat top bar – CPU %, ping, network).
    private func globalSummaryBar(_ metrics: SystemMetrics) -> some View {
        HStack(spacing: 10) {
            Text("CPU \(Int(metrics.cpu.usagePercent))%")
                .font(.caption)
                .foregroundStyle(AppPalette.cpuBlue)
            if let net = metrics.network {
                let total = net.receivedBytesPerSecond + net.sentBytesPerSecond
                Text("↓ \(viewModel.formattedBytes(net.receivedBytesPerSecond))/s ↑ \(viewModel.formattedBytes(net.sentBytesPerSecond))/s")
                    .font(.caption)
                    .foregroundStyle(AppPalette.networkPink)
                if let ping = net.pingMilliseconds, ping > 0 {
                    Text("\(Int(ping)) ms")
                        .font(.caption)
                        .foregroundStyle(AppPalette.neutralGray)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 10)
        .background(AppPalette.neutralGray.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private func metricsSections(_ metrics: SystemMetrics) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            cpuSection(metrics.cpu, graphSamples: viewModel.sampleBuffers.cpu.samples)
            Divider()
                .background(AppPalette.neutralGray.opacity(0.3))
            if let gpu = metrics.gpu {
                gpuSection(gpu, graphSamples: viewModel.sampleBuffers.gpu.samples)
                Divider()
                    .background(AppPalette.neutralGray.opacity(0.3))
            }
            memorySection(metrics.memory, graphSamples: viewModel.sampleBuffers.memory.samples)
            Divider()
                .background(AppPalette.neutralGray.opacity(0.3))
            diskSection(metrics.disk, graphSamples: viewModel.sampleBuffers.disk.samples)
            if let network = metrics.network {
                Divider()
                    .background(AppPalette.neutralGray.opacity(0.3))
                networkSection(network, graphSamples: viewModel.sampleBuffers.network.samples)
            }
            if let battery = metrics.battery {
                Divider()
                    .background(AppPalette.neutralGray.opacity(0.3))
                batterySection(battery, graphSamples: viewModel.sampleBuffers.battery.samples)
            }
            if let sensors = metrics.sensors, (!sensors.thermals.isEmpty || !sensors.fans.isEmpty) {
                Divider()
                    .background(AppPalette.neutralGray.opacity(0.3))
                sensorsSection(sensors)
            }
        }
    }

    private func batterySection(_ battery: BatteryMetrics, graphSamples: [Double] = []) -> some View {
        let level = AppTheme.thresholdLevel(cpuUsagePercent: battery.percentage)
        let color = AppTheme.semanticColor(metric: .battery, level: level)
        let subtitle = batterySubtitle(battery)
        return MetricRow(
            title: "Battery",
            icon: "battery.100",
            value: String(format: "%.0f%%", battery.percentage) + (battery.isCharging ? " ↑" : ""),
            subtitle: subtitle,
            progress: battery.percentage / 100,
            accentColor: color,
            graphSamples: graphSamples
        )
        .animation(AppTheme.stateChangeAnimation, value: level)
    }

    private func batterySubtitle(_ battery: BatteryMetrics) -> String {
        var parts: [String] = []
        if let h = battery.health, !h.isEmpty { parts.append(h) }
        if let c = battery.cycleCount { parts.append("\(c) cycles") }
        if battery.isCharging {
            if let m = battery.timeRemainingMinutes, m > 0 { parts.append("~\(m) min to full") }
        } else if let m = battery.timeRemainingMinutes, m > 0 { parts.append("~\(m) min left") }
        if let r = battery.chargeRate, r != 0 { parts.append(String(format: "%.0f A", r)) }
        return parts.isEmpty ? "—" : parts.joined(separator: " · ")
    }

    private func sensorsSection(_ sensors: SensorMetrics) -> some View {
        let color = AppTheme.semanticColor(metric: .gpu, level: .normal)
        let subtitle = sensorsSubtitle(sensors)
        let maxTemp = sensors.thermals.map(\.1).max() ?? 0
        let progress = maxTemp > 0 ? min(1.0, maxTemp / 100) : 0
        return MetricRow(
            title: "Sensors",
            icon: "sensor.fill",
            value: sensors.thermals.isEmpty ? "—" : String(format: "%.0f°C max", maxTemp),
            subtitle: subtitle,
            progress: progress,
            accentColor: color,
            graphSamples: []
        )
    }

    private func sensorsSubtitle(_ sensors: SensorMetrics) -> String {
        var parts: [String] = []
        if !sensors.thermals.isEmpty {
            parts.append(sensors.thermals.prefix(3).map { "\($0.0): \(Int($0.1))°C" }.joined(separator: ", "))
        }
        if !sensors.fans.isEmpty {
            parts.append(sensors.fans.prefix(2).map { "\($0.0): \(Int($0.1)) rpm" }.joined(separator: ", "))
        }
        return parts.isEmpty ? "—" : parts.joined(separator: " · ")
    }

    private func networkSection(_ network: NetworkMetrics, graphSamples: [Double] = []) -> some View {
        let color = AppTheme.semanticColor(metric: .network, level: .normal)
        let subtitle = networkSubtitle(network)
        let rx = network.receivedBytesPerSecond
        let tx = network.sentBytesPerSecond
        let total = rx + tx
        let progress = total > 0 ? min(1.0, Double(total) / 100_000_000) : 0
        let value = "↓ \(viewModel.formattedBytes(rx))/s ↑ \(viewModel.formattedBytes(tx))/s"
        return MetricRow(
            title: "Network",
            icon: "network",
            value: value,
            subtitle: subtitle,
            progress: progress,
            accentColor: color,
            graphSamples: graphSamples
        )
    }

    private func networkSubtitle(_ network: NetworkMetrics) -> String {
        var parts: [String] = []
        if let ping = network.pingMilliseconds, ping > 0 { parts.append("ping \(String(format: "%.0f", ping)) ms") }
        if !network.perInterface.isEmpty {
            let names = network.perInterface.map(\.name).joined(separator: ", ")
            parts.append(names)
        }
        if parts.isEmpty { return "—" }
        return parts.joined(separator: " · ")
    }

    private func gpuSection(_ gpu: GPUMetrics, graphSamples: [Double] = []) -> some View {
        let level: ThresholdLevel = if let temp = gpu.temperatureCelsius, temp > 0 {
            AppTheme.thresholdLevel(gpuTempCelsius: temp)
        } else {
            AppTheme.thresholdLevel(cpuUsagePercent: gpu.utilizationPercent)
        }
        let color = AppTheme.semanticColor(metric: .gpu, level: level)
        return MetricRow(
            title: "GPU",
            icon: "square.stack.3d.up",
            value: String(format: "%.0f%%", gpu.utilizationPercent),
            subtitle: gpu.summarySubtitle.isEmpty ? "—" : gpu.summarySubtitle,
            progress: gpu.utilizationPercent / 100,
            accentColor: color,
            graphSamples: graphSamples
        )
        .animation(AppTheme.stateChangeAnimation, value: level)
    }

    private func cpuSection(_ cpu: CPUMetrics, graphSamples: [Double] = []) -> some View {
        let level: ThresholdLevel = if let temp = cpu.temperatureCelsius, temp > 0 {
            AppTheme.thresholdLevel(cpuTempCelsius: temp)
        } else {
            AppTheme.thresholdLevel(cpuUsagePercent: cpu.usagePercent)
        }
        let color = AppTheme.semanticColor(metric: .cpu, level: level)
        return VStack(alignment: .leading, spacing: 6) {
            MetricRow(
                title: "CPU",
                icon: "cpu",
                value: String(format: "%.0f%%", cpu.usagePercent),
                subtitle: cpu.summarySubtitle,
                progress: cpu.usagePercent / 100,
                accentColor: color,
                graphSamples: graphSamples
            )
            if cpu.coreCountP > 0 || cpu.coreCountE > 0 {
                HStack(spacing: 12) {
                    if cpu.coreCountP > 0 {
                        HStack(spacing: 4) {
                            Circle().fill(AppPalette.cpuBlue).frame(width: 6, height: 6)
                            Text("P \(Int(cpu.pCoreUsagePercent))%").font(.caption2).foregroundStyle(AppPalette.neutralGray)
                        }
                    }
                    if cpu.coreCountE > 0 {
                        HStack(spacing: 4) {
                            Circle().fill(AppPalette.criticalRed).frame(width: 6, height: 6)
                            Text("E \(Int(cpu.eCoreUsagePercent))%").font(.caption2).foregroundStyle(AppPalette.neutralGray)
                        }
                    }
                }
            }
        }
        .animation(AppTheme.stateChangeAnimation, value: level)
    }

    private func memorySection(_ mem: MemoryMetrics, graphSamples: [Double] = []) -> some View {
        let level = AppTheme.thresholdLevel(memoryPercent: mem.pressurePercent)
        let color = AppTheme.semanticColor(metric: .memory, level: level)
        let subtitle = memorySubtitle(mem)
        return MetricRow(
            title: "Memory",
            icon: "memorychip",
            value: String(format: "%.0f%%", mem.pressurePercent),
            subtitle: subtitle,
            progress: mem.pressurePercent / 100,
            accentColor: color,
            graphSamples: graphSamples
        )
        .animation(AppTheme.stateChangeAnimation, value: level)
    }

    private func memorySubtitle(_ mem: MemoryMetrics) -> String {
        var parts: [String] = ["\(viewModel.formattedBytes(mem.usedBytes)) of \(viewModel.formattedBytes(mem.totalBytes))"]
        if mem.wiredBytes > 0 { parts.append("wired \(viewModel.formattedBytes(mem.wiredBytes))") }
        if mem.compressedBytes > 0 { parts.append("comp \(viewModel.formattedBytes(mem.compressedBytes))") }
        if mem.swapUsedBytes > 0 { parts.append("swap \(viewModel.formattedBytes(mem.swapUsedBytes))") }
        return parts.joined(separator: " · ")
    }

    private func diskSection(_ disk: DiskMetrics, graphSamples: [Double] = []) -> some View {
        let level = AppTheme.thresholdLevel(diskUsagePercent: disk.usagePercent)
        let color = AppTheme.semanticColor(metric: .disk, level: level)
        let subtitle = diskSubtitle(disk)
        return MetricRow(
            title: "Disk",
            icon: "internaldrive",
            value: String(format: "%.0f%%", disk.usagePercent),
            subtitle: subtitle,
            progress: disk.usagePercent / 100,
            accentColor: color,
            graphSamples: graphSamples
        )
        .animation(AppTheme.stateChangeAnimation, value: level)
    }

    private func diskSubtitle(_ disk: DiskMetrics) -> String {
        var parts: [String] = ["\(viewModel.formattedBytes(disk.usedBytes)) of \(viewModel.formattedBytes(disk.totalBytes))"]
        if disk.readBytesPerSecond > 0 || disk.writeBytesPerSecond > 0 {
            parts.append("↓ \(viewModel.formattedBytes(disk.readBytesPerSecond))/s ↑ \(viewModel.formattedBytes(disk.writeBytesPerSecond))/s")
        }
        return parts.joined(separator: " · ")
    }
}

private struct MetricRow: View {
    let title: String
    let icon: String
    let value: String
    let subtitle: String
    let progress: Double
    var accentColor: Color = AppPalette.neutralGray
    /// Optional sample history for mini graph (0...1); shown when non-empty.
    var graphSamples: [Double] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.body)
                    .foregroundStyle(AppPalette.neutralGray)
                    .frame(width: 20, alignment: .center)
                Text(title)
                    .font(.subheadline)
                    .foregroundStyle(AppPalette.neutralGray)
                Spacer(minLength: 4)
                CircularGauge(
                    value: progress,
                    accentColor: accentColor,
                    secondaryColor: accentColor.opacity(0.5),
                    lineWidth: AppTheme.metricGaugeLineWidth,
                    glowEnabled: true,
                    glowRadius: 4,
                    glowOpacity: 0.4
                )
                .frame(width: 28, height: 28)
                Text(value)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(accentColor)
                    .frame(minWidth: 44, alignment: .trailing)
            }
            if !graphSamples.isEmpty {
                MiniGraphView(samples: graphSamples, accentColor: accentColor, lineWidth: AppTheme.metricGraphLineWidth, fillOpacity: AppTheme.metricGraphFillOpacity)
                    .frame(height: 22)
            }
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(AppPalette.neutralGray.opacity(0.8))
        }
    }
}

#Preview {
    PopoverContentView()
}

#endif
