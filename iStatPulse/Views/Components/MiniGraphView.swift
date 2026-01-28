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

/// Real-time sparkline drawn with SwiftUI Canvas. Samples are 0...1 (normalized).
/// Low memory: pass a fixed-size array; Canvas is GPU-accelerated.
struct MiniGraphView: View {
    /// Ordered samples oldest → newest; values in 0...1 (1 = top).
    var samples: [Double]
    var accentColor: Color = AppPalette.cpuBlue
    /// Line width for the stroke.
    var lineWidth: CGFloat = 1.5
    /// Fill area under the line (opacity).
    var fillOpacity: Double = 0.15
    /// Corner radius for optional rounded rect clip (0 = no clip).
    var cornerRadius: CGFloat = 2

    var body: some View {
        Canvas { context, size in
            let count = samples.count
            guard count > 1, size.width > 0, size.height > 0 else { return }

            let w = size.width
            let h = size.height
            let stepX = (count > 1) ? w / CGFloat(count - 1) : w

            // Path: (0,h) → (x0,y0) → … → (xLast,yLast) → (w,h) → close for fill
            var fillPath = Path()
            fillPath.move(to: CGPoint(x: 0, y: h))

            var linePath = Path()
            let y0 = h * (1 - CGFloat(min(1, max(0, samples[0]))))
            linePath.move(to: CGPoint(x: 0, y: y0))

            for i in 1..<count {
                let x = CGFloat(i) * stepX
                let y = h * (1 - CGFloat(min(1, max(0, samples[i]))))
                fillPath.addLine(to: CGPoint(x: x, y: y))
                linePath.addLine(to: CGPoint(x: x, y: y))
            }
            fillPath.addLine(to: CGPoint(x: w, y: h))
            fillPath.closeSubpath()

            // Fill under line
            if fillOpacity > 0 {
                context.fill(
                    fillPath,
                    with: .color(accentColor.opacity(fillOpacity))
                )
            }
            // Stroke line (round cap/join for smooth look)
            context.stroke(
                linePath,
                with: .color(accentColor),
                style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round)
            )
        }
        .drawingGroup() // Smooth left-to-right graph; reduces aliasing
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
    }
}

// MARK: - Dual-Series Mini Graph (e.g. User/System, Read/Write, Upload/Download)

/// Two series drawn with different colors; primary (e.g. user/read/upload) and secondary (system/write/download).
struct DualSeriesMiniGraphView: View {
    var primarySamples: [Double]
    var secondarySamples: [Double]
    var primaryColor: Color = AppPalette.cpuBlue
    var secondaryColor: Color = AppPalette.networkPink
    var lineWidth: CGFloat = 1.5
    var fillOpacity: Double = 0.12
    var cornerRadius: CGFloat = 2

    var body: some View {
        Canvas { context, size in
            let count = max(primarySamples.count, secondarySamples.count)
            guard count > 1, size.width > 0, size.height > 0 else { return }
            let w = size.width
            let h = size.height
            let stepX = w / CGFloat(count - 1)

            func path(for samples: [Double]) -> Path {
                var p = Path()
                guard !samples.isEmpty else { return p }
                let y0 = h * (1 - CGFloat(min(1, max(0, samples[0]))))
                p.move(to: CGPoint(x: 0, y: y0))
                for i in 1..<samples.count {
                    let x = CGFloat(i) * stepX
                    let y = h * (1 - CGFloat(min(1, max(0, samples[i]))))
                    p.addLine(to: CGPoint(x: x, y: y))
                }
                return p
            }

            if primarySamples.count > 1 {
                let fillPath = path(for: primarySamples)
                var closed = fillPath
                closed.addLine(to: CGPoint(x: CGFloat(primarySamples.count - 1) * stepX, y: h))
                closed.addLine(to: CGPoint(x: 0, y: h))
                closed.closeSubpath()
                context.fill(closed, with: .color(primaryColor.opacity(fillOpacity)))
                context.stroke(fillPath, with: .color(primaryColor), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
            }
            if secondarySamples.count > 1 {
                let fillPath = path(for: secondarySamples)
                var closed = fillPath
                closed.addLine(to: CGPoint(x: CGFloat(secondarySamples.count - 1) * stepX, y: h))
                closed.addLine(to: CGPoint(x: 0, y: h))
                closed.closeSubpath()
                context.fill(closed, with: .color(secondaryColor.opacity(fillOpacity)))
                context.stroke(fillPath, with: .color(secondaryColor), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
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
