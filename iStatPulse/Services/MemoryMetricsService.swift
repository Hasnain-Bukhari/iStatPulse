//
//  MemoryMetricsService.swift
//  iStatPulse
//
//  Created by Hasnain Bukhari on 28/1/2569 BE.
//

import Foundation
import Combine

#if os(macOS)
import Darwin

final class MemoryMetricsService: @unchecked Sendable, Refreshable {
    private let subject = CurrentValueSubject<MemoryMetrics, Never>(
        MemoryMetrics(usedBytes: 0, totalBytes: 0, usagePercent: 0, wiredBytes: 0, compressedBytes: 0, swapUsedBytes: 0, pressurePercent: 0, pressureLevel: .normal)
    )
    private var timer: DispatchSourceTimer?
    private let queue = DispatchQueue(label: "com.istatpulse.memory", qos: .userInitiated)

    var metricsPublisher: AnyPublisher<MemoryMetrics, Never> {
        subject.eraseToAnyPublisher()
    }

    func startPolling(interval: TimeInterval = 1.0) {
        stopPolling()
        timer = DispatchSource.makeTimerSource(queue: queue)
        timer?.schedule(deadline: .now(), repeating: interval)
        timer?.setEventHandler { [weak self] in
            self?.sampleMemory()
        }
        timer?.resume()
    }

    func stopPolling() {
        timer?.cancel()
        timer = nil
    }

    /// Called by RefreshEngine each tick.
    func refresh() {
        sampleMemory()
    }

    private func sendFallback() {
        subject.send(MemoryMetrics(
            usedBytes: 0,
            totalBytes: 0,
            usagePercent: 0,
            wiredBytes: 0,
            compressedBytes: 0,
            swapUsedBytes: 0,
            pressurePercent: 0,
            pressureLevel: .normal
        ))
    }

    private func sampleMemory() {
        var stats = vm_statistics64_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else {
            sendFallback()
            return
        }

        let pageSize = UInt64(vm_kernel_page_size)
        let free = UInt64(stats.free_count) * pageSize
        let active = UInt64(stats.active_count) * pageSize
        let inactive = UInt64(stats.inactive_count) * pageSize
        let wired = UInt64(stats.wire_count) * pageSize
        let compressed = UInt64(stats.compressor_page_count) * pageSize
        let used = active + inactive + wired + compressed
        let total = used + free
        let usagePercent = total > 0 ? (Double(used) / Double(total)) * 100.0 : 0

        let (swapUsed, _) = SwapUsage.read()
        // Apple-style memory pressure: physical used + swap contribute; matches Activity Monitor semantics.
        let pressurePercent: Double = total > 0
            ? min(100, (Double(used) + Double(swapUsed)) / Double(total) * 100.0)
            : 0

        // Spec: <60% normal, 60–80% warning, >80% critical (from pressure percent)
        var pressure: MemoryPressureLevel = .normal
        if pressurePercent >= 80 { pressure = .critical }
        else if pressurePercent >= 60 { pressure = .warning }

        subject.send(MemoryMetrics(
            usedBytes: used,
            totalBytes: total,
            usagePercent: min(100, usagePercent),
            wiredBytes: wired,
            compressedBytes: compressed,
            swapUsedBytes: swapUsed,
            pressurePercent: pressurePercent,
            pressureLevel: pressure
        ))
    }
}
#endif
