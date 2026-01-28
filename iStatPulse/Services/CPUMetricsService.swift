//
//  CPUMetricsService.swift
//  iStatPulse
//
//  SMC-level CPU monitoring: host_processor_info (per-core usage),
//  sysctl (P/E split, frequency), AppleSMC (thermal).
//

import Foundation
import Combine

#if os(macOS)
import Darwin

final class CPUMetricsService: @unchecked Sendable, Refreshable {
    private let subject = CurrentValueSubject<CPUMetrics, Never>(CPUMetrics(
        usagePercent: 0,
        userPercent: 0,
        systemPercent: 0,
        coreCount: 0,
        perCoreUsage: [],
        coreCountP: 0,
        coreCountE: 0,
        pCoreUsagePercent: 0,
        eCoreUsagePercent: 0,
        frequencyMHz: 0,
        temperatureCelsius: nil
    ))
    private var timer: DispatchSourceTimer?
    private let queue = DispatchQueue(label: "com.istatpulse.cpu", qos: .userInitiated)
    private let smcThermal = SMCThermalService()

    /// Previous tick counts per core: (user, system, idle, nice) for delta-based usage.
    private var previousTicks: [(Int64, Int64, Int64, Int64)] = []

    var metricsPublisher: AnyPublisher<CPUMetrics, Never> {
        subject.eraseToAnyPublisher()
    }

    /// Legacy: overall usage only (for backward compatibility during migration).
    var usagePublisher: AnyPublisher<Double, Never> {
        subject.map(\.usagePercent).eraseToAnyPublisher()
    }

    func startPolling(interval: TimeInterval = 1.0) {
        stopPolling()
        previousTicks = []
        timer = DispatchSource.makeTimerSource(queue: queue)
        timer?.schedule(deadline: .now(), repeating: interval)
        timer?.setEventHandler { [weak self] in
            self?.sampleCPU()
        }
        timer?.resume()
    }

    func stopPolling() {
        timer?.cancel()
        timer = nil
    }

    /// Called by RefreshEngine each tick (one timer for all services).
    func refresh() {
        sampleCPU()
    }

    private func sampleCPU() {
        var cpuInfo: processor_info_array_t!
        var numCPUInfo: mach_msg_type_number_t = 0
        var numCPUs: natural_t = 0
        let err = host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO, &numCPUs, &cpuInfo, &numCPUInfo)
        guard err == KERN_SUCCESS else {
            sendFallbackMetrics()
            return
        }
        defer { vm_deallocate(mach_task_self_, vm_address_t(bitPattern: cpuInfo), vm_size_t(Int(numCPUInfo) * MemoryLayout<integer_t>.size)) }

        let n = Int(numCPUs)
        var currentTicks: [(Int64, Int64, Int64, Int64)] = []
        for i in 0..<n {
            let offset = Int(CPU_STATE_MAX) * i
            let user = Int64(cpuInfo[offset + Int(CPU_STATE_USER)])
            let system = Int64(cpuInfo[offset + Int(CPU_STATE_SYSTEM)])
            let idle = Int64(cpuInfo[offset + Int(CPU_STATE_IDLE)])
            let nice = Int64(cpuInfo[offset + Int(CPU_STATE_NICE)])
            currentTicks.append((user, system, idle, nice))
        }

        let perCoreUsage: [Double]
        let usagePercent: Double
        var userPercent: Double = 0
        var systemPercent: Double = 0
        let pCoreUsagePercent: Double
        let eCoreUsagePercent: Double

        if previousTicks.count == n {
            var perCore: [Double] = []
            var totalUsed: Double = 0
            var totalTotal: Double = 0
            var pUsed: Double = 0
            var pTotal: Double = 0
            var eUsed: Double = 0
            var eTotal: Double = 0
            var sumUserDelta: Int64 = 0
            var sumSystemDelta: Int64 = 0
            var sumIdleDelta: Int64 = 0
            let (pCount, eCount) = SysctlCPUInfo.pCoreAndECoreCounts
            let pEnd = min(pCount, n)
            let eEnd = min(pCount + eCount, n)
            for i in 0..<n {
                let (pu, ps, pi, pn) = previousTicks[i]
                let (cu, cs, ci, cn) = currentTicks[i]
                let usedDelta = (cu - pu) + (cs - ps) + (cn - pn)
                let totalDelta = usedDelta + (ci - pi)
                sumUserDelta += (cu - pu)
                sumSystemDelta += (cs - ps)
                sumIdleDelta += (ci - pi)
                let coreUsage: Double = totalDelta > 0 ? min(100, max(0, (Double(usedDelta) / Double(totalDelta)) * 100)) : 0
                perCore.append(coreUsage)
                totalUsed += coreUsage
                totalTotal += 100
                if i < pEnd {
                    pUsed += coreUsage
                    pTotal += 100
                } else if i < eEnd {
                    eUsed += coreUsage
                    eTotal += 100
                }
            }
            let totalDelta = sumUserDelta + sumSystemDelta + sumIdleDelta
            if totalDelta > 0 {
                userPercent = min(100, max(0, (Double(sumUserDelta) / Double(totalDelta)) * 100))
                systemPercent = min(100, max(0, (Double(sumSystemDelta) / Double(totalDelta)) * 100))
            }
            let avg = totalTotal > 0 ? totalUsed / totalTotal * 100 : 0
            let pAvg = pTotal > 0 ? pUsed / pTotal * 100 : 0
            let eAvg = eTotal > 0 ? eUsed / eTotal * 100 : 0
            perCoreUsage = perCore
            usagePercent = min(100, max(0, avg))
            pCoreUsagePercent = min(100, max(0, pAvg))
            eCoreUsagePercent = min(100, max(0, eAvg))
        } else {
            // First sample or count changed: use instantaneous snapshot (no deltas).
            var perCore: [Double] = []
            var sum: Double = 0
            var sumUser: Int64 = 0
            var sumSystem: Int64 = 0
            var sumTotal: Int64 = 0
            for i in 0..<n {
                let (user, system, idle, nice) = currentTicks[i]
                let total = user + system + idle + nice
                let used = user + system + nice
                sumUser += user
                sumSystem += system
                sumTotal += total
                let coreUsage: Double = total > 0 ? (Double(used) / Double(total)) * 100 : 0
                perCore.append(coreUsage)
                sum += coreUsage
            }
            if sumTotal > 0 {
                userPercent = min(100, max(0, (Double(sumUser) / Double(sumTotal)) * 100))
                systemPercent = min(100, max(0, (Double(sumSystem) / Double(sumTotal)) * 100))
            }
            let avg = n > 0 ? sum / Double(n) : 0
            let (pCount, eCount) = SysctlCPUInfo.pCoreAndECoreCounts
            let pEnd = min(pCount, n)
            let eEnd = min(pCount + eCount, n)
            var pSum: Double = 0
            var eSum: Double = 0
            for i in 0..<pEnd { pSum += perCore[i] }
            for i in pEnd..<eEnd { eSum += perCore[i] }
            let pAvg = pEnd > 0 ? pSum / Double(pEnd) : 0
            let eAvg = (eEnd > pEnd) ? eSum / Double(eEnd - pEnd) : 0
            perCoreUsage = perCore
            usagePercent = min(100, max(0, avg))
            pCoreUsagePercent = min(100, max(0, pAvg))
            eCoreUsagePercent = min(100, max(0, eAvg))
        }

        previousTicks = currentTicks

        let coreCountP = SysctlCPUInfo.coreCountP
        let coreCountE = SysctlCPUInfo.coreCountE
        let frequencyMHz = SysctlCPUInfo.frequencyMHz
        let temperatureCelsius = smcThermal.readCPUTemperature()

        let metrics = CPUMetrics(
            usagePercent: usagePercent,
            userPercent: userPercent,
            systemPercent: systemPercent,
            coreCount: n,
            perCoreUsage: perCoreUsage,
            coreCountP: coreCountP,
            coreCountE: coreCountE,
            pCoreUsagePercent: pCoreUsagePercent,
            eCoreUsagePercent: eCoreUsagePercent,
            frequencyMHz: frequencyMHz,
            temperatureCelsius: temperatureCelsius
        )
        subject.send(metrics)
    }

    private func sendFallbackMetrics() {
        let n = SysctlCPUInfo.logicalCPUCount
        subject.send(CPUMetrics(
            usagePercent: 0,
            userPercent: 0,
            systemPercent: 0,
            coreCount: max(1, n),
            perCoreUsage: [],
            coreCountP: SysctlCPUInfo.coreCountP,
            coreCountE: SysctlCPUInfo.coreCountE,
            pCoreUsagePercent: 0,
            eCoreUsagePercent: 0,
            frequencyMHz: SysctlCPUInfo.frequencyMHz,
            temperatureCelsius: smcThermal.readCPUTemperature()
        ))
    }
}
#endif
