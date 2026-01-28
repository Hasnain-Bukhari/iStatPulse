//
//  DiskMetricsService.swift
//  iStatPulse
//
//  Disk IO and free space: getfsstat for volume space, IOKit for per-disk IO.
//  Rolling read/write throughput over 1-second windows.
//

import Foundation
import Combine

#if os(macOS)

final class DiskMetricsService: @unchecked Sendable, Refreshable {
    private let subject = CurrentValueSubject<DiskMetrics, Never>(
        DiskMetrics(usedBytes: 0, totalBytes: 0, usagePercent: 0, volumeName: "", readBytesPerSecond: 0, writeBytesPerSecond: 0)
    )
    private var timer: DispatchSourceTimer?
    private let queue = DispatchQueue(label: "com.istatpulse.disk", qos: .userInitiated)

    /// Previous cumulative IO for 1-second delta (rolling throughput).
    private var previousIO: (read: UInt64, write: UInt64)?

    var metricsPublisher: AnyPublisher<DiskMetrics, Never> {
        subject.eraseToAnyPublisher()
    }

    func startPolling(interval: TimeInterval = 1.0) {
        stopPolling()
        previousIO = nil
        timer = DispatchSource.makeTimerSource(queue: queue)
        timer?.schedule(deadline: .now(), repeating: interval)
        timer?.setEventHandler { [weak self] in
            self?.sampleDisk()
        }
        timer?.resume()
    }

    func stopPolling() {
        timer?.cancel()
        timer = nil
    }

    /// Called by RefreshEngine each tick.
    func refresh() {
        sampleDisk()
    }

    private func sampleDisk() {
        // Free space from getfsstat (root volume).
        let (total, available) = VolumeSpace.rootVolumeBytes()
        let used = total > available ? total - available : 0
        let usagePercent = total > 0 ? (Double(used) / Double(total)) * 100.0 : 0
        let volumeName = (FileManager.default.displayName(atPath: "/")).trimmingCharacters(in: .whitespacesAndNewlines)
        let displayName = volumeName.isEmpty ? "Macintosh HD" : volumeName

        // Rolling 1-second throughput from IOKit cumulative bytes.
        let (cumulativeRead, cumulativeWrite) = DiskIOStats.cumulativeBytes()
        var readBps: UInt64 = 0
        var writeBps: UInt64 = 0
        if let prev = previousIO {
            readBps = cumulativeRead >= prev.read ? cumulativeRead - prev.read : 0
            writeBps = cumulativeWrite >= prev.write ? cumulativeWrite - prev.write : 0
        }
        previousIO = (cumulativeRead, cumulativeWrite)

        subject.send(DiskMetrics(
            usedBytes: used,
            totalBytes: total,
            usagePercent: min(100, usagePercent),
            volumeName: displayName,
            readBytesPerSecond: readBps,
            writeBytesPerSecond: writeBps
        ))
    }
}

#endif
