//
//  AppTheme.swift
//  iStatPulse
//
//  Centralized color theme: state-driven semantics, consistent hue logic,
//  threshold mapping, and smooth animated transitions.
//

import SwiftUI

#if os(macOS)

// MARK: - Base Palette (Dark Mode First)

enum AppPalette {
    static let cpuBlue       = Color(hex: "3DA9FC")
    static let gpuCyan      = Color(hex: "2ED1C1")
    static let memoryYellow = Color(hex: "F5C542")
    static let diskPurple   = Color(hex: "9B6BFF")
    static let networkPink  = Color(hex: "FF5DA2")
    static let batteryGreen = Color(hex: "3DDC84")
    static let warningOrange = Color(hex: "FF9F43")
    static let criticalRed   = Color(hex: "FF453A")
    static let neutralGray   = Color(hex: "8E8E93")
    static let background   = Color(hex: "0E0E11")
    static let panel        = Color(hex: "15151A")
}

// MARK: - Threshold Level (Shared Hue Logic)

enum ThresholdLevel: Equatable {
    case normal
    case warning
    case critical
}

// MARK: - Metric Kind → Base Hue

enum MetricKind {
    case cpu
    case memory
    case disk
    case network
    case gpu
    case battery
}

// MARK: - Semantic Color Mapping

/// Colors communicate state, not decoration. All metrics share consistent
/// threshold colors (warning orange, critical red); normal uses metric hue.
enum AppTheme {

    /// Semantic color for a metric at a given threshold level.
    static func semanticColor(metric: MetricKind, level: ThresholdLevel) -> Color {
        switch level {
        case .normal:
            return baseColor(for: metric)
        case .warning:
            return AppPalette.warningOrange
        case .critical:
            return AppPalette.criticalRed
        }
    }

    private static func baseColor(for metric: MetricKind) -> Color {
        switch metric {
        case .cpu:     return AppPalette.cpuBlue
        case .memory:  return AppPalette.memoryYellow
        case .disk:    return AppPalette.diskPurple
        case .network: return AppPalette.networkPink
        case .gpu:     return AppPalette.gpuCyan
        case .battery: return AppPalette.batteryGreen
        }
    }

    // MARK: - Threshold Mapping (Spec-Aligned)

    /// CPU temperature: <75°C normal, 75–90°C warning, >90°C critical.
    static func thresholdLevel(cpuTempCelsius: Double) -> ThresholdLevel {
        if cpuTempCelsius >= 90 { return .critical }
        if cpuTempCelsius >= 75 { return .warning }
        return .normal
    }

    /// Memory pressure: <60% normal, 60–80% warning, >80% critical.
    static func thresholdLevel(memoryPercent: Double) -> ThresholdLevel {
        if memoryPercent >= 80 { return .critical }
        if memoryPercent >= 60 { return .warning }
        return .normal
    }

    /// GPU temperature: <80°C normal, 80–95°C warning, >95°C critical.
    static func thresholdLevel(gpuTempCelsius: Double) -> ThresholdLevel {
        if gpuTempCelsius >= 95 { return .critical }
        if gpuTempCelsius >= 80 { return .warning }
        return .normal
    }

    /// Disk usage percent: same bands as memory for consistency.
    static func thresholdLevel(diskUsagePercent: Double) -> ThresholdLevel {
        if diskUsagePercent >= 80 { return .critical }
        if diskUsagePercent >= 60 { return .warning }
        return .normal
    }

    /// CPU usage percent (when temp not available): same bands.
    static func thresholdLevel(cpuUsagePercent: Double) -> ThresholdLevel {
        if cpuUsagePercent >= 80 { return .critical }
        if cpuUsagePercent >= 60 { return .warning }
        return .normal
    }

    /// Animation used when state/color changes.
    static let stateChangeAnimation: Animation = .easeInOut(duration: 0.35)

    // MARK: - Gauge & Graph (iStat parity)

    /// Stroke thickness for circular gauges in metric rows (consistent across all rings).
    static let metricGaugeLineWidth: CGFloat = 3
    /// Mini graph line width and fill opacity.
    static let metricGraphLineWidth: CGFloat = 1.5
    static let metricGraphFillOpacity: Double = 0.12
}

// MARK: - Color Hex Helper

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

#endif
