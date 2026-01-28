//
//  PopoverViewModel.swift
//  iStatPulse
//
//  Created by Hasnain Bukhari on 28/1/2569 BE.
//

import Foundation
import Combine
import SwiftUI

#if os(macOS)

@MainActor
final class PopoverViewModel: ObservableObject {
    @Published private(set) var metrics: SystemMetrics?
    @Published private(set) var errorMessage: String?

    /// Sensor/feature availability (battery, SMC). Refreshed on appear.
    @Published private(set) var capabilities: SystemCapabilities?

    /// Launch at login; reflects SMAppService status. Toggle via setLaunchAtLogin(_:).
    var launchAtLoginEnabled: Bool { LaunchAtLogin.isEnabled }

    private let metricsService: SystemMetricsServiceProtocol
    private var cancellables = Set<AnyCancellable>()

    /// Fixed-size sample history per metric for mini graphs (60–120 samples).
    let sampleBuffers = SampleBuffers()

    init(metricsService: SystemMetricsServiceProtocol = SystemMetricsService()) {
        self.metricsService = metricsService
        metricsService.metricsPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] value in
                self?.sampleBuffers.push(value)
                self?.metrics = value
                self?.errorMessage = nil
            }
            .store(in: &cancellables)
    }

    func onAppear() {
        metricsService.startPolling()
        refreshCapabilities()
    }

    func onDisappear() {
        metricsService.stopPolling()
    }

    /// Re-detect battery/SMC availability (e.g. after permission change).
    func refreshCapabilities() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let caps = SystemCapabilities.detect()
            DispatchQueue.main.async { self?.capabilities = caps }
        }
    }

    /// Set launch at login. Returns true if the system state matches the request.
    @discardableResult
    func setLaunchAtLogin(_ enabled: Bool) -> Bool {
        let ok = LaunchAtLogin.setEnabled(enabled)
        objectWillChange.send()
        return ok
    }

    /// Hint when sensors (SMC) are unavailable; nil when available or not yet detected.
    var sensorsUnavailableHint: String? {
        guard let cap = capabilities, !cap.hasSMC else { return nil }
        return SystemCapabilities.smcUnavailableHint
    }

    func formattedBytes(_ bytes: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .memory)
    }

    /// Battery time remaining as "X:XX" (e.g. "1:11" for 1h 11m) or "~X min" when < 60 min.
    func batteryTimeRemainingString(minutes: Int?, charging: Bool) -> String? {
        guard let m = minutes, m > 0 else { return nil }
        if m >= 60 {
            let h = m / 60
            let min = m % 60
            return String(format: "%d:%02d", h, min)
        }
        return "~\(m) min"
    }
}

#endif
