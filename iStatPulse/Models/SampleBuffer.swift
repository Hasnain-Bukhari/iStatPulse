//
//  SampleBuffer.swift
//  iStatPulse
//
//  Fixed-size ring buffer for mini graph history (60–120 samples).
//  Low memory: single array, no allocations on append after warm-up.
//

import Foundation

#if os(macOS)

/// Fixed-capacity ring buffer for real-time sample history. Thread-unsafe; use on main.
final class SampleBuffer: @unchecked Sendable {
    /// Maximum number of samples (60–120 typical).
    let capacity: Int
    private var buffer: [Double]
    private var head: Int
    private var count: Int

    init(capacity: Int = 120) {
        self.capacity = max(1, min(1024, capacity))
        self.buffer = Array(repeating: 0, count: self.capacity)
        self.head = 0
        self.count = 0
    }

    /// Append one sample (0...1). Drops oldest when full.
    func append(_ value: Double) {
        let v = min(1, max(0, value))
        if count < capacity {
            buffer[count] = v
            count += 1
        } else {
            buffer[head] = v
            head = (head + 1) % capacity
        }
    }

    /// Ordered samples oldest → newest for drawing. Copy of current window.
    var samples: [Double] {
        guard count > 0 else { return [] }
        if count < capacity {
            return Array(buffer[0..<count])
        }
        return (0..<capacity).map { buffer[(head + $0) % capacity] }
    }
}

/// Holds one SampleBuffer per metric; push from SystemMetrics each tick.
/// Includes dual-series buffers for CPU (user/system), disk (read/write), network (rx/tx).
final class SampleBuffers {
    let cpu = SampleBuffer(capacity: 120)
    let memory = SampleBuffer(capacity: 120)
    let disk = SampleBuffer(capacity: 120)
    let gpu = SampleBuffer(capacity: 120)
    let network = SampleBuffer(capacity: 120)
    let battery = SampleBuffer(capacity: 120)

    /// For CPU mini graph: user (blue) and system (pink).
    let cpuUser = SampleBuffer(capacity: 120)
    let cpuSystem = SampleBuffer(capacity: 120)
    /// For disk I/O: read and write (normalized 0...1).
    let diskRead = SampleBuffer(capacity: 120)
    let diskWrite = SampleBuffer(capacity: 120)
    /// For network: download and upload.
    let networkRx = SampleBuffer(capacity: 120)
    let networkTx = SampleBuffer(capacity: 120)

    func push(_ metrics: SystemMetrics) {
        cpu.append(metrics.cpu.usagePercent / 100)
        cpuUser.append(metrics.cpu.userPercent / 100)
        cpuSystem.append(metrics.cpu.systemPercent / 100)
        memory.append(metrics.memory.pressurePercent / 100)
        disk.append(metrics.disk.usagePercent / 100)
        let readNorm = metrics.disk.readBytesPerSecond > 0 ? min(1, Double(metrics.disk.readBytesPerSecond) / 500_000_000) : 0
        let writeNorm = metrics.disk.writeBytesPerSecond > 0 ? min(1, Double(metrics.disk.writeBytesPerSecond) / 500_000_000) : 0
        diskRead.append(readNorm)
        diskWrite.append(writeNorm)
        if let g = metrics.gpu {
            gpu.append(g.utilizationPercent / 100)
        }
        if let n = metrics.network {
            let total = n.receivedBytesPerSecond + n.sentBytesPerSecond
            let p = total > 0 ? min(1, Double(total) / 100_000_000) : 0
            network.append(p)
            let rxNorm = n.receivedBytesPerSecond > 0 ? min(1, Double(n.receivedBytesPerSecond) / 100_000_000) : 0
            let txNorm = n.sentBytesPerSecond > 0 ? min(1, Double(n.sentBytesPerSecond) / 100_000_000) : 0
            networkRx.append(rxNorm)
            networkTx.append(txNorm)
        }
        if let b = metrics.battery {
            battery.append(b.percentage / 100)
        }
    }
}

#endif
