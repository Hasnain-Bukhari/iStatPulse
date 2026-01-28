//
//  CircularGauge.swift
//  iStatPulse
//
//  Reusable SwiftUI circular gauge: rounded line cap, gradient stroke,
//  subtle glow, threshold color, and animated value transitions.
//

import SwiftUI

#if os(macOS)

// MARK: - Circular Gauge (Primary API)

/// iStat-quality circular gauge with gradient stroke, glow, and smooth animations.
struct CircularGauge: View {
    /// Progress 0...1 (animated).
    var value: Double
    /// Accent color (or gradient start when using gradient stroke).
    var accentColor: Color
    /// Optional second color for gradient; if nil, uses single-color stroke.
    var secondaryColor: Color?
    /// Track (background) ring color.
    var trackColor: Color = AppPalette.neutralGray.opacity(0.25)
    /// Stroke line width.
    var lineWidth: CGFloat = 4
    /// Enable subtle glow behind the stroke.
    var glowEnabled: Bool = true
    /// Glow radius (blur).
    var glowRadius: CGFloat = 5
    /// Glow opacity.
    var glowOpacity: Double = 0.5
    /// Rotation: 0 = top, -90° = right (start from right).
    var startAngle: Angle = .degrees(-90)

    private var clampedValue: Double { min(1, max(0, value)) }

    var body: some View {
        ZStack {
            // Track (full ring)
            Circle()
                .trim(from: 0, to: 1)
                .stroke(
                    trackColor,
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round)
                )
                .rotationEffect(startAngle)

            // Glow layer (same trim, blurred)
            if glowEnabled && clampedValue > 0.01 {
                Circle()
                    .trim(from: 0, to: clampedValue)
                    .stroke(
                        accentColor.opacity(glowOpacity),
                        style: StrokeStyle(lineWidth: lineWidth + 2, lineCap: .round, lineJoin: .round)
                    )
                    .blur(radius: glowRadius)
                    .rotationEffect(startAngle)
            }

            // Main stroke: gradient, rounded cap
            Circle()
                .trim(from: 0, to: clampedValue)
                .stroke(
                    strokeGradient,
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round)
                )
                .rotationEffect(startAngle)
        }
        .drawingGroup() // Reduces aliasing; smooth rasterization on retina
        .animation(AppTheme.stateChangeAnimation, value: value)
        .animation(AppTheme.stateChangeAnimation, value: accentColor)
    }

    private var strokeGradient: some ShapeStyle {
        if let secondary = secondaryColor {
            return AnyShapeStyle(
                AngularGradient(
                    colors: [secondary, accentColor],
                    center: .center
                )
            )
        }
        return AnyShapeStyle(
            LinearGradient(
                colors: [accentColor.opacity(0.55), accentColor],
                startPoint: .leading,
                endPoint: .trailing
            )
        )
    }
}

// MARK: - Convenience: Gauge with threshold level

/// Circular gauge that derives stroke color from a threshold level (normal/warning/critical).
struct ThresholdCircularGauge: View {
    var value: Double
    var metric: MetricKind
    var level: ThresholdLevel
    var lineWidth: CGFloat = 4
    var glowEnabled: Bool = true
    var size: CGFloat = 32

    var body: some View {
        CircularGauge(
            value: value,
            accentColor: AppTheme.semanticColor(metric: metric, level: level),
            secondaryColor: AppTheme.semanticColor(metric: metric, level: level).opacity(0.5),
            lineWidth: lineWidth,
            glowEnabled: glowEnabled
        )
        .frame(width: size, height: size)
    }
}

// MARK: - Preview

#Preview("CircularGauge") {
    VStack(spacing: 24) {
        HStack(spacing: 20) {
            CircularGauge(value: 0.35, accentColor: AppPalette.cpuBlue)
                .frame(width: 44, height: 44)
            CircularGauge(value: 0.72, accentColor: AppPalette.memoryYellow, glowEnabled: true)
                .frame(width: 44, height: 44)
            CircularGauge(value: 0.95, accentColor: AppPalette.criticalRed, secondaryColor: AppPalette.warningOrange)
                .frame(width: 44, height: 44)
        }
        .padding()
        .background(AppPalette.panel)
    }
    .frame(width: 280, height: 120)
}

#endif
