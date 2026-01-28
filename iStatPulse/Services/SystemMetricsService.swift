//
//  SystemMetricsService.swift
//  iStatPulse
//
//  Created by Hasnain Bukhari on 28/1/2569 BE.
//

import Foundation
import Combine

#if os(macOS)

/// Protocol for system metrics providers; ViewModels depend on this abstraction.
protocol SystemMetricsServiceProtocol: Sendable {
    var metricsPublisher: AnyPublisher<SystemMetrics, Never> { get }
    func startPolling()
    func stopPolling()
}

/// Aggregates CPU, Memory, Disk, GPU, Network, Battery, and Sensors services.
/// Uses a single RefreshEngine (one timer, backpressure, dynamic interval).
final class SystemMetricsService: @unchecked Sendable, SystemMetricsServiceProtocol {
    private let cpuService: CPUMetricsService
    private let memoryService: MemoryMetricsService
    private let diskService: DiskMetricsService
    private let gpuService: GPUMetricsService
    private let fpsSampler: FPSSampler
    private let networkService: NetworkMetricsService
    private let batteryService: BatteryMetricsService
    private let sensorsService: SMCSensorsService

    private let engine: RefreshEngine
    private let subject = PassthroughSubject<SystemMetrics, Never>()
    private var cancellables = Set<AnyCancellable>()
    private let queue = DispatchQueue(label: "com.istatpulse.metrics", qos: .userInitiated)

    var metricsPublisher: AnyPublisher<SystemMetrics, Never> {
        subject.eraseToAnyPublisher()
    }

    /// Refresh interval in seconds; can be changed at runtime.
    var refreshInterval: TimeInterval {
        get { engine.currentInterval }
        set { engine.setInterval(newValue) }
    }

    init(
        cpuService: CPUMetricsService = CPUMetricsService(),
        memoryService: MemoryMetricsService = MemoryMetricsService(),
        diskService: DiskMetricsService = DiskMetricsService(),
        gpuService: GPUMetricsService = GPUMetricsService(),
        fpsSampler: FPSSampler = FPSSampler(),
        networkService: NetworkMetricsService = NetworkMetricsService(),
        batteryService: BatteryMetricsService = BatteryMetricsService(),
        sensorsService: SMCSensorsService = SMCSensorsService(),
        refreshInterval: TimeInterval = RefreshEngine.defaultInterval
    ) {
        self.cpuService = cpuService
        self.memoryService = memoryService
        self.diskService = diskService
        self.gpuService = gpuService
        self.fpsSampler = fpsSampler
        self.networkService = networkService
        self.batteryService = batteryService
        self.sensorsService = sensorsService
        let refreshables: [Refreshable] = [cpuService, memoryService, diskService, gpuService, networkService, batteryService, sensorsService]
        self.engine = RefreshEngine(interval: refreshInterval) {
            refreshables.forEach { $0.refresh() }
        }
        combineLatest()
    }

    /// Convenience init for call sites that only pass CPU, memory, and disk (preserves linker symbol for 3-arg init).
    convenience init(
        cpuService: CPUMetricsService = CPUMetricsService(),
        memoryService: MemoryMetricsService = MemoryMetricsService(),
        diskService: DiskMetricsService = DiskMetricsService()
    ) {
        self.init(
            cpuService: cpuService,
            memoryService: memoryService,
            diskService: diskService,
            gpuService: GPUMetricsService(),
            fpsSampler: FPSSampler(),
            networkService: NetworkMetricsService(),
            batteryService: BatteryMetricsService(),
            sensorsService: SMCSensorsService()
        )
    }

    private func combineLatest() {
        let gpuWithFPS = Publishers.CombineLatest(
            gpuService.metricsPublisher,
            fpsSampler.fpsPublisher
        )
        .map { gpu, fps in
            GPUMetrics(
                utilizationPercent: gpu.utilizationPercent,
                frequencyMHz: gpu.frequencyMHz,
                temperatureCelsius: gpu.temperatureCelsius,
                fps: fps
            )
        }

        let fiveWay = Publishers.CombineLatest(
            Publishers.CombineLatest3(
                cpuService.metricsPublisher,
                memoryService.metricsPublisher,
                diskService.metricsPublisher
            ),
            Publishers.CombineLatest(gpuWithFPS, networkService.metricsPublisher)
        )
        .map { ($0.0, $0.1.0, $0.1.1) }

        let withBatteryAndSensors = Publishers.CombineLatest3(
            fiveWay,
            batteryService.metricsPublisher,
            sensorsService.metricsPublisher
        )
        .receive(on: queue)
        withBatteryAndSensors
        .map { (value: (((CPUMetrics, MemoryMetrics, DiskMetrics), GPUMetrics, NetworkMetrics), BatteryMetrics?, SensorMetrics)) -> SystemMetrics in
            let (args, battery, sensors) = (value.0, value.1, value.2)
            return SystemMetrics(
                cpu: args.0.0,
                memory: args.0.1,
                disk: args.0.2,
                gpu: args.1,
                network: args.2,
                battery: battery,
                sensors: sensors
            )
        }
        .sink { [weak subject] metrics in
            subject?.send(metrics)
        }
        .store(in: &cancellables)
    }

    /// Start the single refresh engine (and FPS sampler). Services are driven by engine ticks.
    func startPolling() {
        engine.start()
        fpsSampler.start()
    }

    /// Stop the engine and FPS sampler.
    func stopPolling() {
        engine.stop()
        fpsSampler.stop()
    }
}

#endif
