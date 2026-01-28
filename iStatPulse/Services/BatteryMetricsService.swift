//
//  BatteryMetricsService.swift
//  iStatPulse
//
//  Publishes battery metrics from IOPowerSources (percentage, health, charge rate, time remaining).
//

import Foundation
import Combine

#if os(macOS)

final class BatteryMetricsService: @unchecked Sendable, Refreshable {
    private let subject = CurrentValueSubject<BatteryMetrics?, Never>(nil)
    private var timer: DispatchSourceTimer?
    private let queue = DispatchQueue(label: "com.istatpulse.battery", qos: .userInitiated)

    var metricsPublisher: AnyPublisher<BatteryMetrics?, Never> {
        subject.eraseToAnyPublisher()
    }

    func startPolling(interval: TimeInterval = 5.0) {
        stopPolling()
        timer = DispatchSource.makeTimerSource(queue: queue)
        timer?.schedule(deadline: .now(), repeating: interval)
        timer?.setEventHandler { [weak self] in
            self?.sample()
        }
        timer?.resume()
    }

    func stopPolling() {
        timer?.cancel()
        timer = nil
    }

    /// Called by RefreshEngine each tick.
    func refresh() {
        sample()
    }

    private func sample() {
        subject.send(BatteryService.read())
    }
}
#endif
