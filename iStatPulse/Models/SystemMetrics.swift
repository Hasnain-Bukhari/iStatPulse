//
//  SystemMetrics.swift
//  iStatPulse
//
//  Created by Hasnain Bukhari on 28/1/2569 BE.
//

import Foundation

#if os(macOS)

/// Aggregate system metrics exposed to the UI.
struct SystemMetrics: Sendable {
    var cpu: CPUMetrics
    var memory: MemoryMetrics
    var disk: DiskMetrics
    var gpu: GPUMetrics?
    var network: NetworkMetrics?
    var battery: BatteryMetrics?
    var sensors: SensorMetrics?
}

/// Battery metrics from IOPowerSources: percentage, health, charge rate, time remaining.
struct BatteryMetrics: Sendable {
    /// Current charge 0–100.
    let percentage: Double
    /// Health description (e.g. "Good", "Fair") or nil.
    let health: String?
    /// Cycle count; nil when unavailable.
    let cycleCount: Int?
    /// True when charging.
    let isCharging: Bool
    /// Charge rate (positive = charging, negative = discharging); nil when unknown. Unit is relative or watts depending on source.
    let chargeRate: Double?
    /// Time remaining in minutes. nil when on AC, charging to full, or unknown.
    let timeRemainingMinutes: Int?
}

/// Thermal and fan sensors from AppleSMC.
struct SensorMetrics: Sendable {
    /// Named thermal readings in °C (e.g. "CPU", "GPU", "Battery").
    let thermals: [(name: String, celsius: Double)]
    /// Named fan speeds in RPM.
    let fans: [(name: String, rpm: Double)]
}

/// Per-interface stats (name, receive B/s, send B/s).
struct InterfaceStats: Sendable {
    let name: String
    let receivedBytesPerSecond: UInt64
    let sentBytesPerSecond: UInt64
}

/// Network metrics: ifaddrs-based throughput (delta) and optional ping RTT.
struct NetworkMetrics: Sendable {
    /// Aggregate receive throughput (bytes/s) across interfaces.
    let receivedBytesPerSecond: UInt64
    /// Aggregate send throughput (bytes/s) across interfaces.
    let sentBytesPerSecond: UInt64
    /// Per-interface stats (e.g. en0, bridge0).
    let perInterface: [InterfaceStats]
    /// ICMP ping RTT in ms. nil when not measured or failed.
    let pingMilliseconds: Double?
}

/// GPU metrics: utilization (IORegistry/Metal), clocks, thermal, FPS.
struct GPUMetrics: Sendable {
    /// GPU utilization 0–100 (from IORegistry PerformanceStatistics or Metal).
    let utilizationPercent: Double
    /// Current GPU frequency in MHz. 0 when unavailable.
    let frequencyMHz: Double
    /// GPU temperature in °C (SMC or IORegistry). nil when unavailable.
    let temperatureCelsius: Double?
    /// Sampled FPS from display link (display refresh or app frame rate). nil when not sampling.
    let fps: Double?

    var summarySubtitle: String {
        var parts: [String] = []
        if frequencyMHz > 0 { parts.append(String(format: "%.0f MHz", frequencyMHz)) }
        if let t = temperatureCelsius, t > 0 { parts.append(String(format: "%.0f°C", t)) }
        if let f = fps, f > 0 { parts.append(String(format: "%.0f FPS", f)) }
        return parts.joined(separator: " · ")
    }
}

/// SMC-level CPU metrics: per-core usage, P/E split, frequency, thermal.
struct CPUMetrics: Sendable {
    /// Overall CPU usage (0–100).
    let usagePercent: Double
    /// Total logical cores.
    let coreCount: Int
    /// Per-core usage (0–100), one element per logical core. Empty until deltas available.
    let perCoreUsage: [Double]
    /// Performance-core count (Apple Silicon); 0 if unknown or Intel.
    let coreCountP: Int
    /// Efficiency-core count (Apple Silicon); 0 if unknown or Intel.
    let coreCountE: Int
    /// P-core aggregate usage (0–100). 0 when no P/E split.
    let pCoreUsagePercent: Double
    /// E-core aggregate usage (0–100). 0 when no P/E split.
    let eCoreUsagePercent: Double
    /// CPU frequency in MHz. 0 when not available (e.g. Apple Silicon).
    let frequencyMHz: Double
    /// Package/CPU temperature in °C from SMC. nil when unavailable.
    let temperatureCelsius: Double?

    /// Subtitle for UI: e.g. "8P + 2E · 2.4 GHz" or "10 cores".
    var summarySubtitle: String {
        var parts: [String] = []
        if coreCountP > 0 || coreCountE > 0 {
            if coreCountP > 0 { parts.append("\(coreCountP)P") }
            if coreCountE > 0 { parts.append("\(coreCountE)E") }
        } else {
            parts.append("\(coreCount) cores")
        }
        if frequencyMHz > 0 {
            parts.append(String(format: "%.1f GHz", frequencyMHz / 1000))
        }
        if let temp = temperatureCelsius, temp > 0 {
            parts.append(String(format: "%.0f°C", temp))
        }
        return parts.joined(separator: " · ")
    }
}

/// Memory metrics from vm_statistics64 + swap; pressure matches Activity Monitor semantics.
struct MemoryMetrics: Sendable {
    /// Total physical memory in use (active + inactive + wired + compressed).
    let usedBytes: UInt64
    /// Total physical memory (used + free).
    let totalBytes: UInt64
    /// Physical usage 0–100 (usedBytes / totalBytes).
    let usagePercent: Double
    /// Wired memory (cannot be paged out), in bytes.
    let wiredBytes: UInt64
    /// Compressed memory (compressor), in bytes.
    let compressedBytes: UInt64
    /// Swap used, in bytes.
    let swapUsedBytes: UInt64
    /// Apple-style memory pressure 0–100 (factors in physical + swap; matches Activity Monitor).
    let pressurePercent: Double
    /// Semantic level from pressurePercent (<60 normal, 60–80 warning, >80 critical).
    let pressureLevel: MemoryPressureLevel
}

enum MemoryPressureLevel: String, Sendable {
    case normal
    case warning
    case critical
}

/// Disk metrics: free space (getfsstat) and rolling read/write throughput over 1s (IOKit).
struct DiskMetrics: Sendable {
    let usedBytes: UInt64
    let totalBytes: UInt64
    let usagePercent: Double
    /// Read throughput in bytes per second (rolling 1-second window).
    let readBytesPerSecond: UInt64
    /// Write throughput in bytes per second (rolling 1-second window).
    let writeBytesPerSecond: UInt64
}

#endif
