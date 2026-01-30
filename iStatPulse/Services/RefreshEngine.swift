//
//  RefreshEngine.swift
//  iStatPulse
//
//  Centralized refresh engine: one timer, backpressure control,
//  dynamic refresh rates. All services update on the same tick without blocking main.
//

import Foundation
import Combine

#if os(macOS)

/// Services that can be driven by a single tick (no internal timer when engine-driven).
protocol Refreshable: AnyObject {
    func refresh()
}

/// One timer, configurable interval, serial queue for natural backpressure.
/// Ticks run off the main thread; only one tick is processed at a time.
/// Exposes a Combine publisher for tick-driven pipelines.
final class RefreshEngine: @unchecked Sendable {
    /// Default interval (seconds) when none specified.
    static let defaultInterval: TimeInterval = 10.0

    private let queue: DispatchQueue
    private var timer: DispatchSourceTimer?
    private var interval: TimeInterval
    private let onTick: () -> Void
    private var isRunning = false

    /// Emits () on each tick (on the engine queue). Use for Combine-based pipelines with backpressure.
    var tickPublisher: AnyPublisher<Void, Never> {
        tickSubject.receive(on: queue).eraseToAnyPublisher()
    }
    private let tickSubject = PassthroughSubject<Void, Never>()

    /// Minimum interval to avoid runaway (0.2s).
    private static let minInterval: TimeInterval = 0.2
    /// Maximum interval (60s).
    private static let maxInterval: TimeInterval = 60.0

    /// Create engine. `onTick` is called on a background serial queue each tick.
    /// Backpressure: the next tick is not delivered until `onTick` returns.
    init(
        interval: TimeInterval = RefreshEngine.defaultInterval,
        queue: DispatchQueue? = nil,
        onTick: @escaping () -> Void
    ) {
        self.interval = min(RefreshEngine.maxInterval, max(RefreshEngine.minInterval, interval))
        self.queue = queue ?? DispatchQueue(label: "com.istatpulse.refresh", qos: .userInitiated)
        self.onTick = onTick
    }

    /// Start the single timer. Safe to call when already running (no-op).
    func start() {
        queue.async { [weak self] in
            self?.startOnQueue()
        }
    }

    /// Stop the timer. Safe to call when already stopped.
    func stop() {
        queue.async { [weak self] in
            self?.stopOnQueue()
        }
    }

    /// Change interval; takes effect on next tick. If running, timer is rescheduled.
    func setInterval(_ newInterval: TimeInterval) {
        let clamped = min(RefreshEngine.maxInterval, max(RefreshEngine.minInterval, newInterval))
        queue.async { [weak self] in
            guard let self = self else { return }
            self.interval = clamped
            if self.isRunning {
                self.stopOnQueue()
                self.startOnQueue()
            }
        }
    }

    /// Current interval in seconds.
    var currentInterval: TimeInterval { interval }

    private func startOnQueue() {
        guard !isRunning else { return }
        isRunning = true
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now(), repeating: interval)
        t.setEventHandler { [weak self] in
            guard let self = self else { return }
            self.tickSubject.send(())
            self.onTick()
        }
        timer = t
        t.resume()
    }

    private func stopOnQueue() {
        timer?.cancel()
        timer = nil
        isRunning = false
    }
}

#endif
