//
//  GPUMetricsService.swift
//  iStatPulse
//
//  GPU monitoring via IORegistry (IOAccelerator/AGXAccelerator) and SMC thermal.
//  Reads utilization, optional frequency, temperature; FPS supplied by FPSSampler.
//

import Foundation
import Combine

#if os(macOS)
import IOKit
import CoreFoundation
import Darwin

/// Service names to try (Apple Silicon uses AGXAccelerator; Intel/AMD use IOAccelerator).
private let kIOAcceleratorClassName = "IOAccelerator"
private let kAGXAcceleratorClassName = "AGXAccelerator"

/// IORegistry property keys for GPU stats (names vary by driver).
private let kPerformanceStatistics = "PerformanceStatistics"
private let kDeviceUtilization = "Device Utilization %"
private let kGPUActivity = "GPU Activity(%)"
private let kRendererUtilization = "Renderer Utilization %"
private let kTilerUtilization = "Tiler Utilization %"

final class GPUMetricsService: @unchecked Sendable, Refreshable {
    private let subject = CurrentValueSubject<GPUMetrics, Never>(GPUMetrics(
        utilizationPercent: 0,
        frequencyMHz: 0,
        temperatureCelsius: nil,
        fps: nil
    ))
    private var timer: DispatchSourceTimer?
    private let queue = DispatchQueue(label: "com.istatpulse.gpu", qos: .userInitiated)
    private let smcThermal = SMCThermalService()

    var metricsPublisher: AnyPublisher<GPUMetrics, Never> {
        subject.eraseToAnyPublisher()
    }

    func startPolling(interval: TimeInterval = 1.0) {
        stopPolling()
        timer = DispatchSource.makeTimerSource(queue: queue)
        timer?.schedule(deadline: .now(), repeating: interval)
        timer?.setEventHandler { [weak self] in
            self?.sampleGPU()
        }
        timer?.resume()
    }

    func stopPolling() {
        timer?.cancel()
        timer = nil
    }

    /// Called by RefreshEngine each tick.
    func refresh() {
        sampleGPU()
    }

    private func sampleGPU() {
        let utilization = readUtilizationFromIORegistry()
        let frequencyMHz = readFrequencyFromIORegistry()
        let temperature = readGPUTemperature()

        let metrics = GPUMetrics(
            utilizationPercent: utilization,
            frequencyMHz: frequencyMHz,
            temperatureCelsius: temperature,
            fps: nil
        )
        subject.send(metrics)
    }

    /// Read GPU utilization from IORegistry PerformanceStatistics.
    private func readUtilizationFromIORegistry() -> Double {
        for className in [kAGXAcceleratorClassName, kIOAcceleratorClassName] {
            if let util = readUtilizationFromClass(className) {
                return util
            }
        }
        return 0
    }

    private func readUtilizationFromClass(_ className: String) -> Double? {
        return className.withCString { cStr in
            let match = IOServiceMatching(cStr)
            var iterator: io_iterator_t = 0
            defer { if iterator != 0 { IOObjectRelease(iterator) } }
            guard IOServiceGetMatchingServices(kIOMasterPortDefault, match, &iterator) == KERN_SUCCESS else { return nil }
            var service = IOIteratorNext(iterator)
            defer { if service != 0 { IOObjectRelease(service) } }
            while service != 0 {
                defer { IOObjectRelease(service); service = IOIteratorNext(iterator) }
                if let stats = getPerformanceStatistics(service: service),
                   let util = numberFrom(stats, keys: [kDeviceUtilization, kGPUActivity, kRendererUtilization, kTilerUtilization]) {
                    return min(100, max(0, util))
                }
            }
            return nil
        }
    }

    private func getPerformanceStatistics(service: io_service_t) -> [String: Any]? {
        var props: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(service, &props, kCFAllocatorDefault, 0) == KERN_SUCCESS,
              let cf = props?.takeRetainedValue(),
              let dict = cf as? [String: Any] else { return nil }
        if let stats = dict[kPerformanceStatistics] as? [String: Any] { return stats }
        return dict
    }

    private func numberFrom(_ dict: [String: Any], keys: [String]) -> Double? {
        for key in keys {
            if let v = dict[key] {
                if let n = v as? Int { return Double(n) }
                if let n = v as? Int64 { return Double(n) }
                if let n = v as? Double { return n }
                if let n = v as? Float { return Double(n) }
                if let cf = v as? NSNumber { return cf.doubleValue }
            }
        }
        return nil
    }

    /// Read GPU frequency from IORegistry if exposed (e.g. Core Clock, GPU Clock).
    private func readFrequencyFromIORegistry() -> Double {
        for className in [kAGXAcceleratorClassName, kIOAcceleratorClassName] {
            if let mhz = readFrequencyFromClass(className) {
                return mhz
            }
        }
        return 0
    }

    private func readFrequencyFromClass(_ className: String) -> Double? {
        return className.withCString { cStr in
            let match = IOServiceMatching(cStr)
            var iterator: io_iterator_t = 0
            defer { if iterator != 0 { IOObjectRelease(iterator) } }
            guard IOServiceGetMatchingServices(kIOMasterPortDefault, match, &iterator) == KERN_SUCCESS else { return nil }
            let clockKeys = ["Core Clock (MHz)", "GPU Clock (MHz)", "Current Clock (MHz)", "CoreClock", "GPUClock", "Frequency (MHz)"]
            var service = IOIteratorNext(iterator)
            defer { if service != 0 { IOObjectRelease(service) } }
            while service != 0 {
                defer { IOObjectRelease(service); service = IOIteratorNext(iterator) }
                if let stats = getPerformanceStatistics(service: service),
                   let mhz = numberFrom(stats, keys: clockKeys), mhz > 0 { return mhz }
                if let dict = getPropertiesDict(service: service),
                   let mhz = numberFrom(dict, keys: clockKeys), mhz > 0 { return mhz }
            }
            return nil
        }
    }

    private func getPropertiesDict(service: io_service_t) -> [String: Any]? {
        var props: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(service, &props, kCFAllocatorDefault, 0) == KERN_SUCCESS,
              let cf = props?.takeRetainedValue(),
              let dict = cf as? [String: Any] else { return nil }
        return dict
    }

    /// GPU temperature from SMC (TG0P, TG0D, etc.).
    private func readGPUTemperature() -> Double? {
        for key in ["TG0P", "TG0D", "TG0E", "TG1P", "TG1D"] {
            if let t = smcThermal.readTemperature(key: key), t > 0, t < 120 { return t }
        }
        return nil
    }
}
#endif
