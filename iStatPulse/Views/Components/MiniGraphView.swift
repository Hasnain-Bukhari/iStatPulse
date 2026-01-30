//
//  MiniGraphView.swift
//  iStatPulse
//
//  Lightweight real-time line graph using SwiftUI Canvas (GPU-accelerated)
//  with a fixed sample buffer for historical data (60–120 samples).
//

import SwiftUI

#if os(macOS)

// MARK: - Mini Graph (Canvas)

/// Real-time bar graph drawn with SwiftUI Canvas. Samples are 0...1 (normalized).
/// Low memory: pass a fixed-size array; Canvas is GPU-accelerated.
struct MiniGraphView: View {
    /// Ordered samples oldest → newest; values in 0...1 (1 = top).
    var samples: [Double]
    var accentColor: Color = AppPalette.cpuBlue
    /// Bar spacing (points) between bars.
    var barSpacing: CGFloat = 1
    /// Corner radius for optional rounded rect clip (0 = no clip).
    var cornerRadius: CGFloat = 2

    var body: some View {
        Canvas { context, size in
            let count = samples.count
            guard count > 1, size.width > 0, size.height > 0 else { return }

            let w = size.width
            let h = size.height
            let barWidth = max(1, (w - (CGFloat(count - 1) * barSpacing)) / CGFloat(count))
            for i in 0..<count {
                let value = CGFloat(min(1, max(0, samples[i])))
                let barHeight = h * value
                let x = CGFloat(i) * (barWidth + barSpacing)
                let rect = CGRect(x: x, y: h - barHeight, width: barWidth, height: barHeight)
                context.fill(Path(roundedRect: rect, cornerRadius: 1), with: .color(accentColor))
            }
        }
        .drawingGroup() // Smooth left-to-right graph; reduces aliasing
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
    }
}

// MARK: - Dual-Series Mini Graph (e.g. User/System, Read/Write, Upload/Download)

/// Two series drawn as stacked bars; primary (e.g. user/read/upload) on top of secondary.
struct DualSeriesMiniGraphView: View {
    var primarySamples: [Double]
    var secondarySamples: [Double]
    var primaryColor: Color = AppPalette.cpuBlue
    var secondaryColor: Color = AppPalette.networkPink
    var barSpacing: CGFloat = 1
    var cornerRadius: CGFloat = 2

    var body: some View {
        Canvas { context, size in
            let count = max(primarySamples.count, secondarySamples.count)
            guard count > 1, size.width > 0, size.height > 0 else { return }
            let w = size.width
            let h = size.height
            let barWidth = max(1, (w - (CGFloat(count - 1) * barSpacing)) / CGFloat(count))
            for i in 0..<count {
                let primaryValue = i < primarySamples.count ? CGFloat(min(1, max(0, primarySamples[i]))) : 0
                let secondaryValue = i < secondarySamples.count ? CGFloat(min(1, max(0, secondarySamples[i]))) : 0
                let combined = min(1, primaryValue + secondaryValue)
                let secondaryHeight = h * min(1, secondaryValue)
                let primaryHeight = h * min(1, primaryValue)
                let x = CGFloat(i) * (barWidth + barSpacing)

                if secondaryHeight > 0 {
                    let rect = CGRect(x: x, y: h - secondaryHeight, width: barWidth, height: secondaryHeight)
                    context.fill(Path(roundedRect: rect, cornerRadius: 1), with: .color(secondaryColor))
                }
                if primaryHeight > 0 {
                    let y = h - secondaryHeight - primaryHeight
                    let rect = CGRect(x: x, y: max(0, y), width: barWidth, height: min(primaryHeight, h - secondaryHeight))
                    context.fill(Path(roundedRect: rect, cornerRadius: 1), with: .color(primaryColor))
                }
                if combined < 1 {
                    let gapY = h - (h * combined)
                    if gapY > 0 {
                        let rect = CGRect(x: x, y: 0, width: barWidth, height: gapY)
                        context.fill(Path(rect), with: .color(.clear))
                    }
                }
            }
        }
        .drawingGroup()
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
    }
}

// MARK: - Preview

#Preview("MiniGraph") {
    let samples = (0..<60).map { _ in Double.random(in: 0.2...0.9) }
    return MiniGraphView(samples: samples, accentColor: AppPalette.cpuBlue)
        .frame(height: 28)
        .padding()
        .background(AppPalette.panel)
        .frame(width: 200)
}

#endif
