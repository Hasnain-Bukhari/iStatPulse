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
    @AppStorage("appearanceMode") private var appearanceMode: String = "system"
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 14) {
                header
                if let metrics = viewModel.metrics {
                    sectionCard { globalSummaryBar(metrics) }
                    sectionCard { heroSection(metrics) }
                    sectionCard { gpuSectionWithHeader(metrics.gpu) }
                    sectionCard { pressureMemoryBatteryGrid(metrics) }
                    sectionCard { peCoresRow(metrics.cpu) }
                    sectionCard { diskRow(metrics.disk) }
                    sectionCard { cpuSectionWithDualGraph(metrics.cpu) }
                    if let gpu = metrics.gpu {
                        sectionCard { gpuRow(gpu, graphSamples: viewModel.sampleBuffers.gpu.samples) }
                    }
                    sectionCard { diskIOSection(metrics.disk) }
                    if let network = metrics.network {
                        sectionCard { networkSectionWithDualGraph(network) }
                    }
                    if let network = metrics.network {
                        sectionCard { pingBlock(network) }
                        sectionCard { publicIPBlock(network) }
                    }
                    if let battery = metrics.battery {
                        sectionCard { batteryBar(battery) }
                    }
                    if let sensors = metrics.sensors, (!sensors.thermals.isEmpty || !sensors.fans.isEmpty) {
                        sectionCard { sensorsRow(sensors) }
                    }
                } else {
                    ProgressView("Loading…")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 40)
                }
                footer
            }
            .padding(20)
        }
        .frame(width: 384, height: 784)
        .background(AppPalette.background)
        .environment(\.colorScheme, preferredColorScheme ?? colorScheme)
        .onAppear { viewModel.onAppear() }
        .onDisappear { viewModel.onDisappear() }
    }

    private var header: some View {
        sectionCard {
            HStack(spacing: 10) {
                Image(systemName: "chart.bar.doc.horizontal")
                    .font(.title2)
                    .foregroundStyle(primaryTextColor)
                VStack(alignment: .leading, spacing: 2) {
                    Text("iStat Pulse")
                        .font(.headline)
                        .foregroundStyle(primaryTextColor)
                    Text("System overview")
                        .font(.caption2)
                        .foregroundStyle(AppPalette.neutralGray)
                }
            }
        }
    }

    /// Summary bar: memory used, FPS, free disk, ping, CPU %, network ↓/↑.
    private func globalSummaryBar(_ metrics: SystemMetrics) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                summaryChip(icon: "memorychip", text: "\(viewModel.formattedBytes(metrics.memory.usedBytes)) used", color: AppPalette.memoryYellow)
                summaryChip(
                    icon: "internaldrive",
                    text: "\(viewModel.formattedBytes(metrics.disk.totalBytes > metrics.disk.usedBytes ? metrics.disk.totalBytes - metrics.disk.usedBytes : 0)) free",
                    color: AppPalette.diskPurple
                )
                summaryChip(icon: "cpu", text: "\(Int(metrics.cpu.usagePercent))% CPU", color: AppPalette.cpuBlue)
            }
            HStack(spacing: 6) {
                if let gpu = metrics.gpu, let fps = gpu.fps, fps > 0 {
                    summaryChip(icon: "speedometer", text: "\(Int(fps)) FPS", color: AppPalette.gpuCyan)
                }
                if let net = metrics.network, let ping = net.pingMilliseconds, ping > 0 {
                    summaryChip(icon: "dot.radiowaves.left.and.right", text: "\(Int(ping)) ms", color: AppPalette.neutralGray)
                }
                if let net = metrics.network {
                    summaryChip(icon: "arrow.up", text: "\(viewModel.formattedBytes(net.sentBytesPerSecond))/s", color: AppPalette.networkPink)
                    summaryChip(icon: "arrow.down", text: "\(viewModel.formattedBytes(net.receivedBytesPerSecond))/s", color: AppPalette.networkPink)
                }
                Spacer(minLength: 0)
            }
        }
    }

    private func summaryChip(icon: String, text: String, color: Color) -> some View {
        Label(text, systemImage: icon)
            .font(.caption2)
            .foregroundStyle(color)
            .lineLimit(1)
            .minimumScaleFactor(0.85)
            .padding(.vertical, 4)
            .padding(.horizontal, 6)
            .background(AppPalette.panelSecondary)
            .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    /// Hero: three large circular gauges — CPU, GPU, FANS.
    private func heroSection(_ metrics: SystemMetrics) -> some View {
        HStack(spacing: 16) {
            heroGauge(
                title: "CPU",
                value: metrics.cpu.temperatureCelsius.map { String(format: "%.0f°", $0) } ?? String(format: "%.2f GHz", metrics.cpu.frequencyMHz / 1000),
                subtitle: metrics.cpu.temperatureCelsius != nil ? String(format: "%.2f GHz", metrics.cpu.frequencyMHz / 1000) : nil,
                progress: metrics.cpu.usagePercent / 100,
                color: AppTheme.semanticColor(metric: .cpu, level: metrics.cpu.temperatureCelsius.map { AppTheme.thresholdLevel(cpuTempCelsius: $0) } ?? AppTheme.thresholdLevel(cpuUsagePercent: metrics.cpu.usagePercent))
            )
            if let gpu = metrics.gpu {
                heroGauge(
                    title: "GPU",
                    value: gpu.temperatureCelsius.map { String(format: "%.0f°", $0) } ?? String(format: "%.2f GHz", gpu.frequencyMHz / 1000),
                    subtitle: gpu.temperatureCelsius != nil ? String(format: "%.2f GHz", gpu.frequencyMHz / 1000) : nil,
                    progress: gpu.utilizationPercent / 100,
                    color: AppTheme.semanticColor(metric: .gpu, level: gpu.temperatureCelsius.map { AppTheme.thresholdLevel(gpuTempCelsius: $0) } ?? .normal)
                )
            }
            fansHeroGauge(metrics.sensors)
        }
        .padding(.vertical, 6)
    }

    private func heroGauge(title: String, value: String, subtitle: String?, progress: Double, color: Color) -> some View {
        VStack(spacing: 4) {
            gaugeWithCenterText(
                valueText: "\(Int(progress * 100))%",
                progress: progress,
                color: color,
                size: 68,
                lineWidth: 4,
                glowEnabled: true
            )
            Text(title)
                .font(.caption2)
                .foregroundStyle(AppPalette.neutralGray)
            Text(value)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundStyle(color)
            if let sub = subtitle, !sub.isEmpty {
                Text(sub)
                    .font(.caption2)
                    .foregroundStyle(AppPalette.neutralGray.opacity(0.8))
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func fansHeroGauge(_ sensors: SensorMetrics?) -> some View {
        let fansOn = (sensors?.fans.isEmpty == false) && (sensors?.fans.first?.1 ?? 0) > 0
        let progress = fansOn ? min(1, (sensors?.fans.first?.1 ?? 0) / 4000) : 0
        let color = AppPalette.neutralGray
        return VStack(spacing: 4) {
            gaugeWithCenterText(
                valueText: fansOn ? "\(Int(sensors?.fans.first?.1 ?? 0))" : "OFF",
                progress: progress,
                color: color,
                size: 68,
                lineWidth: 4,
                glowEnabled: false
            )
            Text("FANS")
                .font(.caption2)
                .foregroundStyle(AppPalette.neutralGray)
            Text(fansOn ? "\(Int(sensors?.fans.first?.1 ?? 0)) rpm" : "OFF")
                .font(.caption)
                .fontWeight(.medium)
                .foregroundStyle(AppPalette.neutralGray)
        }
        .frame(maxWidth: .infinity)
    }

    /// GPU section: header "GPU" / "X FPS" + 4 small gauges (Usage, MEM, TMP, Freq).
    private func gpuSectionWithHeader(_ gpu: GPUMetrics?) -> some View {
        Group {
            if let g = gpu {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("GPU")
                            .font(.subheadline)
                            .foregroundStyle(AppPalette.neutralGray)
                        Spacer()
                        if let fps = g.fps, fps > 0 {
                            Text("\(Int(fps)) FPS")
                                .font(.caption)
                                .foregroundStyle(AppPalette.gpuCyan)
                        }
                    }
                    HStack(spacing: 12) {
                        smallGaugeCell(title: "GPU", value: "\(Int(g.utilizationPercent))%", progress: g.utilizationPercent / 100, color: AppPalette.gpuCyan)
                        smallGaugeCell(title: "MEM", value: g.memoryPercent.map { "\(Int($0))%" } ?? "—", progress: (g.memoryPercent ?? 0) / 100, color: AppPalette.memoryYellow)
                        smallGaugeCell(title: "TMP", value: g.temperatureCelsius.map { "\(Int($0))°" } ?? "—", progress: (g.temperatureCelsius ?? 0) / 100, color: AppPalette.gpuCyan)
                        smallGaugeCell(title: "GHz", value: g.frequencyMHz > 0 ? String(format: "%.2f", g.frequencyMHz / 1000) : "—", progress: min(1, g.frequencyMHz / 1500), color: AppPalette.gpuCyan)
                    }
                }
            }
        }
    }

    private func smallGaugeCell(title: String, value: String, progress: Double, color: Color) -> some View {
        VStack(spacing: 2) {
            gaugeWithCenterText(
                valueText: value,
                progress: min(1, max(0, progress)),
                color: color,
                size: 44,
                lineWidth: 2,
                glowEnabled: true,
                textColor: color
            )
            Text(title)
                .font(.caption2)
                .foregroundStyle(AppPalette.neutralGray.opacity(0.8))
        }
        .frame(maxWidth: .infinity)
    }

    /// 2×2 grid: Pressure, Memory, Battery, Battery Health.
    private func pressureMemoryBatteryGrid(_ metrics: SystemMetrics) -> some View {
        let mem = metrics.memory
        let pressureColor = AppTheme.semanticColor(metric: .memory, level: AppTheme.thresholdLevel(memoryPercent: mem.pressurePercent))
        let memoryColor = AppTheme.semanticColor(metric: .memory, level: AppTheme.thresholdLevel(memoryPercent: mem.usagePercent))
        let battery = metrics.battery
        let batteryColor = battery.map { AppTheme.semanticColor(metric: .battery, level: AppTheme.thresholdLevel(cpuUsagePercent: $0.percentage)) } ?? AppPalette.neutralGray
        let healthPct = battery?.health.flatMap { _ in 100.0 } ?? 0
        return VStack(spacing: 8) {
            HStack(spacing: 8) {
                gridGauge(title: "PRESSURE", value: "\(Int(mem.pressurePercent))%", progress: mem.pressurePercent / 100, color: pressureColor)
                gridGauge(title: "MEMORY", value: "\(Int(mem.usagePercent))%", progress: mem.usagePercent / 100, color: memoryColor)
            }
            HStack(spacing: 8) {
                gridGauge(title: "BATTERY", value: battery.map { String(format: "%.0f%%", $0.percentage) + ($0.isCharging ? " ↑" : "") } ?? "—", progress: (battery?.percentage ?? 0) / 100, color: batteryColor)
                gridGauge(title: "HEALTH", value: battery?.health.map { "\($0)" } ?? "—", progress: healthPct / 100, color: AppPalette.networkPink)
            }
        }
    }

    private func gridGauge(title: String, value: String, progress: Double, color: Color) -> some View {
        VStack(spacing: 4) {
            gaugeWithCenterText(
                valueText: value,
                progress: min(1, max(0, progress)),
                color: color,
                size: 54,
                lineWidth: AppTheme.metricGaugeLineWidth,
                glowEnabled: true,
                textColor: color
            )
            Text(title)
                .font(.caption2)
                .foregroundStyle(AppPalette.neutralGray.opacity(0.8))
        }
        .frame(maxWidth: .infinity)
    }

    /// P/E cores: hollow circles + Efficiency (pink) / Performance (blue) labels.
    private func peCoresRow(_ cpu: CPUMetrics) -> some View {
        Group {
            if cpu.coreCountP > 0 || cpu.coreCountE > 0 {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 4) {
                        ForEach(0..<min(cpu.coreCount, 12), id: \.self) { _ in
                            Circle()
                                .stroke(AppPalette.neutralGray.opacity(0.5), lineWidth: 1)
                                .frame(width: 6, height: 6)
                        }
                    }
                    HStack(spacing: 16) {
                        HStack(spacing: 4) {
                            Circle().fill(AppPalette.networkPink).frame(width: 6, height: 6)
                            Text("Efficiency Cores")
                                .font(.caption2)
                                .foregroundStyle(AppPalette.neutralGray)
                        }
                        Text("\(Int(cpu.eCoreUsagePercent))%")
                            .font(.caption)
                            .foregroundStyle(AppPalette.networkPink)
                        HStack(spacing: 4) {
                            Circle().fill(AppPalette.cpuBlue).frame(width: 6, height: 6)
                            Text("Performance Cores")
                                .font(.caption2)
                                .foregroundStyle(AppPalette.neutralGray)
                        }
                        Text("\(Int(cpu.pCoreUsagePercent))%")
                            .font(.caption)
                            .foregroundStyle(AppPalette.cpuBlue)
                    }
                }
            }
        }
    }

    /// Disk row: volume name + "X GB available".
    private func diskRow(_ disk: DiskMetrics) -> some View {
        let available = disk.totalBytes > disk.usedBytes ? disk.totalBytes - disk.usedBytes : UInt64(0)
        let color = AppTheme.semanticColor(metric: .disk, level: AppTheme.thresholdLevel(diskUsagePercent: disk.usagePercent))
        return HStack(spacing: 8) {
            Image(systemName: "internaldrive")
                .font(.body)
                .foregroundStyle(AppPalette.neutralGray)
                .frame(width: 20, alignment: .center)
            Text(disk.volumeName.isEmpty ? "Macintosh HD" : disk.volumeName)
                .font(.subheadline)
                .foregroundStyle(AppPalette.neutralGray)
            Spacer()
            Text("\(viewModel.formattedBytes(available)) available")
                .font(.caption)
                .foregroundStyle(AppPalette.neutralGray.opacity(0.9))
            gaugeWithCenterText(
                valueText: "\(Int(disk.usagePercent))%",
                progress: disk.usagePercent / 100,
                color: color,
                size: 32,
                lineWidth: AppTheme.metricGaugeLineWidth,
                glowEnabled: true,
                textColor: color,
                textScale: 0.6
            )
        }
    }

    /// CPU section with User/System dual-series mini graph.
    private func cpuSectionWithDualGraph(_ cpu: CPUMetrics) -> some View {
        let level: ThresholdLevel = cpu.temperatureCelsius.map { AppTheme.thresholdLevel(cpuTempCelsius: $0) } ?? AppTheme.thresholdLevel(cpuUsagePercent: cpu.usagePercent)
        let color = AppTheme.semanticColor(metric: .cpu, level: level)
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("CPU")
                    .font(.subheadline)
                    .foregroundStyle(AppPalette.neutralGray)
                Spacer()
                Text(cpu.summarySubtitle)
                    .font(.caption)
                    .foregroundStyle(AppPalette.neutralGray)
            }
            if !viewModel.sampleBuffers.cpuUser.samples.isEmpty || !viewModel.sampleBuffers.cpuSystem.samples.isEmpty {
                DualSeriesMiniGraphView(
                    primarySamples: viewModel.sampleBuffers.cpuUser.samples,
                    secondarySamples: viewModel.sampleBuffers.cpuSystem.samples,
                    primaryColor: AppPalette.cpuBlue,
                    secondaryColor: AppPalette.networkPink
                )
                .frame(height: 30)
                HStack(spacing: 12) {
                    HStack(spacing: 4) {
                        Circle().fill(AppPalette.cpuBlue).frame(width: 5, height: 5)
                        Text("User \(Int(cpu.userPercent))%").font(.caption2).foregroundStyle(AppPalette.neutralGray)
                    }
                    HStack(spacing: 4) {
                        Circle().fill(AppPalette.networkPink).frame(width: 5, height: 5)
                        Text("System \(Int(cpu.systemPercent))%").font(.caption2).foregroundStyle(AppPalette.neutralGray)
                    }
                }
            }
        }
        .animation(AppTheme.stateChangeAnimation, value: level)
    }

    private func gpuRow(_ gpu: GPUMetrics, graphSamples: [Double]) -> some View {
        MetricRow(
            title: "GPU",
            icon: "square.stack.3d.up",
            value: String(format: "%.0f%%", gpu.utilizationPercent),
            subtitle: gpu.summarySubtitle.isEmpty ? "—" : gpu.summarySubtitle,
            progress: gpu.utilizationPercent / 100,
            accentColor: AppTheme.semanticColor(metric: .gpu, level: gpu.temperatureCelsius.map { AppTheme.thresholdLevel(gpuTempCelsius: $0) } ?? .normal),
            graphSamples: graphSamples
        )
    }

    /// Disk I/O: Read (pink) / Write (blue) dual-series + peak rates.
    private func diskIOSection(_ disk: DiskMetrics) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                HStack(spacing: 4) {
                    Circle().fill(AppPalette.networkPink).frame(width: 5, height: 5)
                    Text("\(viewModel.formattedBytes(disk.readBytesPerSecond))/s Read")
                        .font(.caption)
                        .foregroundStyle(AppPalette.networkPink)
                }
                Spacer()
                HStack(spacing: 4) {
                    Circle().fill(AppPalette.cpuBlue).frame(width: 5, height: 5)
                    Text("\(viewModel.formattedBytes(disk.writeBytesPerSecond))/s Write")
                        .font(.caption)
                        .foregroundStyle(AppPalette.cpuBlue)
                }
            }
            if !viewModel.sampleBuffers.diskRead.samples.isEmpty || !viewModel.sampleBuffers.diskWrite.samples.isEmpty {
                DualSeriesMiniGraphView(
                    primarySamples: viewModel.sampleBuffers.diskRead.samples,
                    secondarySamples: viewModel.sampleBuffers.diskWrite.samples,
                    primaryColor: AppPalette.networkPink,
                    secondaryColor: AppPalette.cpuBlue
                )
                .frame(height: 30)
            }
            HStack(spacing: 12) {
                Text("Read \(viewModel.formattedBytes(disk.readBytesPerSecond))/s")
                    .font(.caption2)
                    .foregroundStyle(AppPalette.neutralGray)
                Text("Write \(viewModel.formattedBytes(disk.writeBytesPerSecond))/s")
                    .font(.caption2)
                    .foregroundStyle(AppPalette.neutralGray)
            }
        }
    }

    /// Network: Upload (pink) / Download (blue) dual-series.
    private func networkSectionWithDualGraph(_ network: NetworkMetrics) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                HStack(spacing: 4) {
                    Circle().fill(AppPalette.networkPink).frame(width: 5, height: 5)
                    Text("\(viewModel.formattedBytes(network.sentBytesPerSecond))/s Upload")
                        .font(.caption)
                        .foregroundStyle(AppPalette.networkPink)
                }
                Spacer()
                HStack(spacing: 4) {
                    Circle().fill(AppPalette.cpuBlue).frame(width: 5, height: 5)
                    Text("\(viewModel.formattedBytes(network.receivedBytesPerSecond))/s Download")
                        .font(.caption)
                        .foregroundStyle(AppPalette.cpuBlue)
                }
            }
            if !viewModel.sampleBuffers.networkTx.samples.isEmpty || !viewModel.sampleBuffers.networkRx.samples.isEmpty {
                DualSeriesMiniGraphView(
                    primarySamples: viewModel.sampleBuffers.networkTx.samples,
                    secondarySamples: viewModel.sampleBuffers.networkRx.samples,
                    primaryColor: AppPalette.networkPink,
                    secondaryColor: AppPalette.cpuBlue
                )
                .frame(height: 30)
            }
        }
    }

    /// PING block: host + ms + green dot when active.
    private func pingBlock(_ network: NetworkMetrics) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("PING")
                .font(.caption2)
                .foregroundStyle(AppPalette.neutralGray)
            HStack(spacing: 6) {
                if let ping = network.pingMilliseconds, ping > 0 {
                    Circle().fill(AppPalette.batteryGreen).frame(width: 6, height: 6)
                }
                Text(network.pingHost ?? "—")
                    .font(.caption)
                    .foregroundStyle(primaryTextColor)
                if let ping = network.pingMilliseconds, ping > 0 {
                    Text("\(Int(ping))ms")
                        .font(.caption)
                        .foregroundStyle(primaryTextColor)
                }
            }
        }
        .padding(8)
        .background(AppPalette.panelSecondary)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    /// PUBLIC IP block.
    private func publicIPBlock(_ network: NetworkMetrics) -> some View {
        Group {
            if let ip = network.publicIP, !ip.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("PUBLIC IP ADDRESSES")
                        .font(.caption2)
                        .foregroundStyle(AppPalette.neutralGray.opacity(0.8))
                    Text(ip)
                        .font(.caption)
                        .foregroundStyle(.primary)
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(AppPalette.neutralGray.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }
        }
    }

    /// Battery bar at bottom: horizontal progress + "X:XX until full" / "X:XX left".
    private func batteryBar(_ battery: BatteryMetrics) -> some View {
        let color = AppTheme.semanticColor(metric: .battery, level: AppTheme.thresholdLevel(cpuUsagePercent: battery.percentage))
        let timeStr = viewModel.batteryTimeRemainingString(minutes: battery.timeRemainingMinutes, charging: battery.isCharging)
        return VStack(alignment: .leading, spacing: 6) {
            Text("BATTERY")
                .font(.caption2)
                .foregroundStyle(AppPalette.neutralGray.opacity(0.8))
            HStack(spacing: 8) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(AppPalette.neutralGray.opacity(0.2))
                            .frame(height: 8)
                        RoundedRectangle(cornerRadius: 4)
                            .fill(color)
                            .frame(width: geo.size.width * (battery.percentage / 100), height: 8)
                    }
                }
                .frame(height: 8)
                Text(batteryTimeLabel(isCharging: battery.isCharging, percentage: battery.percentage, timeString: timeStr))
                    .font(.caption)
                    .foregroundStyle(AppPalette.neutralGray)
            }
        }
    }

    private func sensorsRow(_ sensors: SensorMetrics) -> some View {
        let subtitle = [
            sensors.thermals.prefix(3).map { "\($0.0): \(Int($0.1))°C" }.joined(separator: ", "),
            sensors.fans.prefix(2).map { "\($0.0): \(Int($0.1)) rpm" }.joined(separator: ", ")
        ].filter { !$0.isEmpty }.joined(separator: " · ")
        return MetricRow(
            title: "Sensors",
            icon: "sensor.fill",
            value: sensors.thermals.isEmpty ? "—" : String(format: "%.0f°C max", sensors.thermals.map(\.1).max() ?? 0),
            subtitle: subtitle.isEmpty ? "—" : subtitle,
            progress: min(1, (sensors.thermals.map(\.1).max() ?? 0) / 100),
            accentColor: AppPalette.gpuCyan,
            graphSamples: []
        )
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider()
                .background(AppPalette.panelStroke)
            HStack(spacing: 8) {
                Image(systemName: "circle.lefthalf.filled")
                    .font(.caption)
                    .foregroundStyle(AppPalette.neutralGray)
                Text("Appearance")
                    .font(.caption)
                    .foregroundStyle(AppPalette.neutralGray)
                Spacer()
                Picker("", selection: $appearanceMode) {
                    Text("System").tag("system")
                    Text("Dark").tag("dark")
                    Text("Light").tag("light")
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(width: 170)
            }
            HStack {
                Image(systemName: "bolt.circle.fill")
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

    private var preferredColorScheme: ColorScheme? {
        switch appearanceMode {
        case "light":
            return .light
        case "dark":
            return .dark
        default:
            return nil
        }
    }

    private var primaryTextColor: Color {
        preferredColorScheme == .dark || (preferredColorScheme == nil && colorScheme == .dark) ? .white : .primary
    }

    private func batteryTimeLabel(isCharging: Bool, percentage: Double, timeString: String?) -> String {
        if isCharging {
            if percentage >= 99 {
                return "Full"
            }
            return timeString.map { "\($0) until full" } ?? "Charging"
        }
        return timeString.map { "\($0) left" } ?? "—"
    }

    private func gaugeWithCenterText(
        valueText: String,
        progress: Double,
        color: Color,
        size: CGFloat,
        lineWidth: CGFloat,
        glowEnabled: Bool,
        textColor: Color? = nil,
        textScale: CGFloat = 0.7
    ) -> some View {
        ZStack {
            CircularGauge(
                value: min(1, max(0, progress)),
                accentColor: color,
                secondaryColor: color.opacity(0.5),
                lineWidth: lineWidth,
                glowEnabled: glowEnabled,
                glowRadius: glowEnabled ? 4 : 0,
                glowOpacity: glowEnabled ? 0.35 : 0
            )
            Text(valueText)
                .font(.caption2)
                .fontWeight(.semibold)
                .foregroundStyle(textColor ?? primaryTextColor)
                .lineLimit(1)
                .minimumScaleFactor(textScale)
        }
        .frame(width: size, height: size)
    }

    private func sectionCard<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(AppPalette.panel)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(AppPalette.panelStroke, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

private struct MetricRow: View {
    let title: String
    let icon: String
    let value: String
    let subtitle: String
    let progress: Double
    var accentColor: Color = AppPalette.neutralGray
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
                MiniGraphView(samples: graphSamples, accentColor: accentColor)
                    .frame(height: 30)
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
