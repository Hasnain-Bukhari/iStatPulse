//
//  AppTheme.swift
//  iStatPulse
//
//  Centralized color theme: state-driven semantics, consistent hue logic,
//  threshold mapping, and smooth animated transitions.
//

import SwiftUI
import AppKit

#if os(macOS)

// MARK: - Base Palette (Dark Mode First)

enum AppPalette {
    static let cpuBlue        = Color(hex: "4C8DFF")
    static let gpuCyan        = Color(hex: "2EE6FF")
    static let memoryYellow   = Color(hex: "FFB84D")
    static let diskPurple     = Color(hex: "9B7BFF")
    static let networkPink    = Color(hex: "FF6FB7")
    static let batteryGreen   = Color(hex: "5BE37D")
    static let warningOrange  = Color(hex: "FF9F43")
    static let criticalRed    = Color(hex: "FF453A")
    static let neutralGray = dynamicColor(
        light: NSColor(hex: "4B4F57"),
        dark: NSColor(hex: "B7BCC4")
    )
    static let background = dynamicColor(
        light: NSColor(hex: "FFFFFF"),
        dark: NSColor(hex: "0A0C10")
    )
    static let panel = dynamicColor(
        light: NSColor(hex: "F5F6F8"),
        dark: NSColor(hex: "12161D")
    )
    static let panelSecondary = dynamicColor(
        light: NSColor(hex: "E9ECF1"),
        dark: NSColor(hex: "1A1F27")
    )
    static let panelStroke = dynamicColor(
        light: NSColor(hex: "D5D9E0"),
        dark: NSColor(hex: "2A3240")
    )
    private static func dynamicColor(light: NSColor, dark: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
        })
    }
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

    /// Battery percent: 0–20 critical (red), 21–40 warning (yellow), 41–100 normal (green).
    static func thresholdLevel(batteryPercent: Double) -> ThresholdLevel {
        if batteryPercent <= 20 { return .critical }
        if batteryPercent <= 40 { return .warning }
        return .normal
    }

    /// Animation used when state/color changes.
    static let stateChangeAnimation: Animation = .easeInOut(duration: 0.35)

    // MARK: - Gauge & Graph (iStat parity)

    /// Stroke thickness for circular gauges in metric rows (consistent across all rings).
    static let metricGaugeLineWidth: CGFloat = 4
    /// Mini graph line width and fill opacity.
    static let metricGraphLineWidth: CGFloat = 2
    static let metricGraphFillOpacity: Double = 0.18
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

extension NSColor {
    convenience init(hex: String) {
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
            red: CGFloat(r) / 255,
            green: CGFloat(g) / 255,
            blue: CGFloat(b) / 255,
            alpha: CGFloat(a) / 255
        )
    }
}

#endif
