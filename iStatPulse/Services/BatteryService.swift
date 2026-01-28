//
//  BatteryService.swift
//  iStatPulse
//
//  Battery percentage, health, charge rate, time remaining via IOPowerSources.
//

import Foundation
import Combine

#if os(macOS)
import IOKit
import IOKit.ps
import CoreFoundation

enum BatteryService {
    /// Extract battery metrics from IOPowerSources. Returns nil when no battery, sandbox, or API failure.
    /// Do not call CFRelease: takeRetainedValue() transfers ownership to Swift; ARC manages the references.
    static func read() -> BatteryMetrics? {
        guard let infoRef = IOPSCopyPowerSourcesInfo() else { return nil }
        let info = infoRef.takeRetainedValue()
        guard let listRef = IOPSCopyPowerSourcesList(info) else { return nil }
        let list = listRef.takeRetainedValue() as [CFTypeRef]
        guard let source = list.first else { return nil }
        guard let descRef = IOPSGetPowerSourceDescription(info, source),
              let desc = descRef.takeUnretainedValue() as? [String: Any] else { return nil }
        return parse(desc)
    }

    private static func parse(_ d: [String: Any]) -> BatteryMetrics? {
        let current = (d["Current Capacity"] as? Int).flatMap { Double($0) }
        let maxCap = (d["Max Capacity"] as? Int).flatMap { Double($0) }
        let percentage: Double = {
            guard let cur = current, let cap = maxCap, cap > 0 else { return 0 }
            return min(100, max(0, (cur / cap) * 100))
        }()
        let isCharging = (d["Is Charging"] as? Bool) ?? false
        let timeToEmpty = d["Time to Empty"] as? Int
        let timeToFull = d["Time to Full Charge"] as? Int
        let timeRemaining: Int? = isCharging ? timeToFull : timeToEmpty
        let health = d["Battery Health"] as? String
            ?? (d["Battery Health Condition"] as? String)
        let cycleCount = d["Cycle Count"] as? Int
        let amperage = d["Amperage"] as? Int
        let chargeRate: Double? = amperage.map { Double($0) }
        return BatteryMetrics(
            percentage: percentage,
            health: health,
            cycleCount: cycleCount,
            isCharging: isCharging,
            chargeRate: chargeRate,
            timeRemainingMinutes: timeRemaining
        )
    }
}
#endif
