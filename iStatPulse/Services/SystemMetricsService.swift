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
/// Uses dual RefreshEngines: fast (3s) for CPU/Memory/Network/GPU, slow (10s) for Battery/Sensors.
final class SystemMetricsService: @unchecked Sendable, SystemMetricsServiceProtocol {
    private let cpuService: CPUMetricsService
    private let memoryService: MemoryMetricsService
    private let diskService: DiskMetricsService
    private let gpuService: GPUMetricsService
    private let fpsSampler: FPSSampler
    private let networkService: NetworkMetricsService
    private let publicIPService: PublicIPService
    private let batteryService: BatteryMetricsService
    private let sensorsService: SMCSensorsService

    private let fastEngine: RefreshEngine  // For CPU, Memory, Network, GPU (3s)
    private let slowEngine: RefreshEngine  // For Battery, Sensors (10s)
    private let subject = PassthroughSubject<SystemMetrics, Never>()
    private var cancellables = Set<AnyCancellable>()
    private let queue = DispatchQueue(label: "com.istatpulse.metrics", qos: .userInitiated)

    var metricsPublisher: AnyPublisher<SystemMetrics, Never> {
        subject.eraseToAnyPublisher()
    }

    /// Fast refresh interval in seconds; can be changed at runtime.
    var fastRefreshInterval: TimeInterval {
        get { fastEngine.currentInterval }
        set { fastEngine.setInterval(newValue) }
    }
    
    /// Slow refresh interval in seconds; can be changed at runtime.
    var slowRefreshInterval: TimeInterval {
        get { slowEngine.currentInterval }
        set { slowEngine.setInterval(newValue) }
    }
    
    /// Legacy: maintains backward compatibility by setting fast interval.
    var refreshInterval: TimeInterval {
        get { fastEngine.currentInterval }
        set { fastEngine.setInterval(newValue) }
    }

    init(
        cpuService: CPUMetricsService = CPUMetricsService(),
        memoryService: MemoryMetricsService = MemoryMetricsService(),
        diskService: DiskMetricsService = DiskMetricsService(),
        gpuService: GPUMetricsService = GPUMetricsService(),
        fpsSampler: FPSSampler = FPSSampler(),
        networkService: NetworkMetricsService = NetworkMetricsService(),
        publicIPService: PublicIPService = PublicIPService(),
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
        self.publicIPService = publicIPService
        self.batteryService = batteryService
        self.sensorsService = sensorsService
        
        // Fast tier: CPU, Memory, Disk, GPU, Network (update every 3s for responsive UI)
        let fastRefreshables: [Refreshable] = [cpuService, memoryService, diskService, gpuService, networkService]
        self.fastEngine = RefreshEngine(interval: refreshInterval) {
            fastRefreshables.forEach { $0.refresh() }
        }
        
        // Slow tier: Battery, Sensors (update every 10s, they change slowly)
        let slowRefreshables: [Refreshable] = [batteryService, sensorsService]
        self.slowEngine = RefreshEngine(interval: RefreshEngine.slowInterval) {
            slowRefreshables.forEach { $0.refresh() }
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
            publicIPService: PublicIPService(),
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
                memoryPercent: gpu.memoryPercent,
                frequencyMHz: gpu.frequencyMHz,
                temperatureCelsius: gpu.temperatureCelsius,
                fps: fps
            )
        }

        let networkWithPublicIP = Publishers.CombineLatest(
            networkService.metricsPublisher,
            publicIPService.publicIPPublisher
        )
        .map { net, publicIP in
            NetworkMetrics(
                receivedBytesPerSecond: net.receivedBytesPerSecond,
                sentBytesPerSecond: net.sentBytesPerSecond,
                perInterface: net.perInterface,
                pingHost: net.pingHost,
                pingMilliseconds: net.pingMilliseconds,
                publicIP: publicIP
            )
        }

        let fiveWay = Publishers.CombineLatest(
            Publishers.CombineLatest3(
                cpuService.metricsPublisher,
                memoryService.metricsPublisher,
                diskService.metricsPublisher
            ),
            Publishers.CombineLatest(gpuWithFPS, networkWithPublicIP)
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

    /// Start both refresh engines (fast + slow), FPS sampler, and network services.
    func startPolling() {
        fastEngine.start()
        slowEngine.start()
        fpsSampler.start()
        publicIPService.start()
        networkService.startPingTimer()
    }

    /// Stop both engines, FPS sampler, and network services.
    func stopPolling() {
        fastEngine.stop()
        slowEngine.stop()
        fpsSampler.stop()
        publicIPService.stop()
        networkService.stopPingTimer()
    }
}

#endif
