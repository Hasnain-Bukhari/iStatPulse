//
//  NetworkMetricsService.swift
//  iStatPulse
//
//  Network throughput from getifaddrs; delta-based speeds over 1s.
//  Optional ICMP ping with timeout.
//

import Foundation
import Combine

#if os(macOS)

final class NetworkMetricsService: @unchecked Sendable, Refreshable {
    private let subject = CurrentValueSubject<NetworkMetrics, Never>(NetworkMetrics(
        receivedBytesPerSecond: 0,
        sentBytesPerSecond: 0,
        perInterface: [],
        pingHost: nil,
        pingMilliseconds: nil,
        publicIP: nil
    ))
    private var timer: DispatchSourceTimer?
    private var pingTimer: DispatchSourceTimer?
    private let queue = DispatchQueue(label: "com.istatpulse.network", qos: .userInitiated)
    private let pingQueue = DispatchQueue(label: "com.istatpulse.ping", qos: .utility)

    /// Previous cumulative bytes per interface for delta (rolling 1s).
    private var previousPerInterface: [String: (received: UInt64, sent: UInt64)] = [:]

    /// Ping target; nil disables ping.
    var pingHost: String? = "1.1.1.1"
    var pingInterval: TimeInterval = 10.0
    var pingTimeout: TimeInterval = 2.0

    var metricsPublisher: AnyPublisher<NetworkMetrics, Never> {
        subject.eraseToAnyPublisher()
    }

    func startPolling(interval: TimeInterval = 1.0) {
        stopPolling()
        previousPerInterface = [:]
        timer = DispatchSource.makeTimerSource(queue: queue)
        timer?.schedule(deadline: .now(), repeating: interval)
        timer?.setEventHandler { [weak self] in
            self?.sampleNetwork()
        }
        timer?.resume()
        startPingTimer()
    }

    func stopPolling() {
        timer?.cancel()
        timer = nil
        stopPingTimer()
    }

    /// Called by RefreshEngine each tick (throughput only; ping uses its own timer when startPolling is used).
    func refresh() {
        sampleNetwork()
        startPingTimer()
    }

    /// Starts ping timer only (used with RefreshEngine-driven polling).
    func startPingTimer() {
        guard pingTimer == nil, let host = pingHost else { return }
        pingTimer = DispatchSource.makeTimerSource(queue: pingQueue)
        pingTimer?.schedule(deadline: .now(), repeating: pingInterval)
        pingTimer?.setEventHandler { [weak self] in
            self?.samplePing(host: host)
        }
        pingTimer?.resume()
    }

    func stopPingTimer() {
        pingTimer?.cancel()
        pingTimer = nil
    }

    private func sampleNetwork() {
        let current = InterfaceStatsReader.cumulativeBytesPerInterface()
        var perInterface: [InterfaceStats] = []
        var totalRxBps: UInt64 = 0
        var totalTxBps: UInt64 = 0
        for item in current {
            let (rxBps, txBps): (UInt64, UInt64)
            if let prev = previousPerInterface[item.name] {
                rxBps = item.received >= prev.received ? item.received - prev.received : 0
                txBps = item.sent >= prev.sent ? item.sent - prev.sent : 0
            } else {
                rxBps = 0
                txBps = 0
            }
            previousPerInterface[item.name] = (item.received, item.sent)
            perInterface.append(InterfaceStats(
                name: item.name,
                receivedBytesPerSecond: rxBps,
                sentBytesPerSecond: txBps
            ))
            totalRxBps = totalRxBps &+ rxBps
            totalTxBps = totalTxBps &+ txBps
        }
        let existing = subject.value
        subject.send(NetworkMetrics(
            receivedBytesPerSecond: totalRxBps,
            sentBytesPerSecond: totalTxBps,
            perInterface: perInterface,
            pingHost: pingHost,
            pingMilliseconds: existing.pingMilliseconds,
            publicIP: existing.publicIP
        ))
    }

    private func samplePing(host: String) {
        guard let rtt = PingService.ping(host: host, timeout: pingTimeout) else { return }
        queue.async { [weak self] in
            guard let self = self else { return }
            let current = self.subject.value
            self.subject.send(NetworkMetrics(
                receivedBytesPerSecond: current.receivedBytesPerSecond,
                sentBytesPerSecond: current.sentBytesPerSecond,
                perInterface: current.perInterface,
                pingHost: self.pingHost,
                pingMilliseconds: rtt,
                publicIP: current.publicIP
            ))
        }
    }
}
#endif
