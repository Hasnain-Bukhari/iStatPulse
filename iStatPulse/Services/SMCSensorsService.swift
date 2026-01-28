//
//  SMCSensorsService.swift
//  iStatPulse
//
//  Thermal and fan sensors via AppleSMC (sp78 = temp, fpe2 = fan RPM).
//

import Foundation
import Combine

#if os(macOS)
import IOKit
import Darwin

private let smcBufferSize = 77
private let dataOffset = 45

/// Thermal key → display name; fan key → display name.
private let thermalKeys: [(key: String, name: String)] = [
    ("TC0P", "CPU"), ("TC0D", "CPU Diode"), ("TG0P", "GPU"), ("TG0D", "GPU Diode"),
    ("TB0T", "Battery"), ("TM0P", "Memory"), ("Th0H", "Northbridge"),
]
private let fanKeys: [(key: String, name: String)] = [
    ("F0Ac", "Fan 1"), ("F1Ac", "Fan 2"), ("F0Mn", "Fan 1 Min"), ("F1Mn", "Fan 2 Min"),
]

final class SMCSensorsService: @unchecked Sendable, Refreshable {
    private let subject = CurrentValueSubject<SensorMetrics, Never>(SensorMetrics(thermals: [], fans: []))
    private var timer: DispatchSourceTimer?
    private let queue = DispatchQueue(label: "com.istatpulse.smc.sensors", qos: .userInitiated)
    private let smcThermal = SMCThermalService()

    var metricsPublisher: AnyPublisher<SensorMetrics, Never> {
        subject.eraseToAnyPublisher()
    }

    func startPolling(interval: TimeInterval = 2.0) {
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
        var thermals: [(String, Double)] = []
        for (key, name) in thermalKeys {
            if let t = smcThermal.readTemperature(key: key), t > -10, t < 150 {
                thermals.append((name, t))
            }
        }
        var fans: [(String, Double)] = []
        for (key, name) in fanKeys {
            if let rpm = readFanRPM(key: key), rpm > 0 {
                fans.append((name, rpm))
            }
        }
        subject.send(SensorMetrics(thermals: thermals, fans: fans))
    }

    /// Read SMC key as fpe2 (16-bit / 4 = RPM).
    private func readFanRPM(key: String) -> Double? {
        var conn: io_connect_t = 0
        defer { if conn != 0 { _ = IOServiceClose(conn) } }
        let match = IOServiceMatching("AppleSMC")
        let service = IOServiceGetMatchingService(kIOMasterPortDefault, match)
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        guard IOServiceOpen(service, mach_task_self_, 0, &conn) == KERN_SUCCESS, conn != 0 else { return nil }
        var input = [UInt8](repeating: 0, count: smcBufferSize)
        let k = Array(key.utf8.prefix(4))
        guard k.count == 4 else { return nil }
        input[0] = k[0]; input[1] = k[1]; input[2] = k[2]; input[3] = k[3]
        input[26] = 32; input[27] = 0; input[28] = 0; input[29] = 0
        input[40] = 5
        var output = [UInt8](repeating: 0, count: smcBufferSize)
        var outSize = output.count
        let kr = input.withUnsafeMutableBytes { inp in
            output.withUnsafeMutableBytes { out in
                IOConnectCallStructMethod(conn, 2, inp.baseAddress, inp.count, out.baseAddress, &outSize)
            }
        }
        guard kr == KERN_SUCCESS, outSize >= dataOffset + 2 else { return nil }
        let b0 = output[dataOffset]
        let b1 = output[dataOffset + 1]
        let raw = (UInt16(b0) << 8) | UInt16(b1)
        return Double(raw) / 4.0
    }
}
#endif
