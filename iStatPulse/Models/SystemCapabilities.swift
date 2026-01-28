//
//  SystemCapabilities.swift
//  iStatPulse
//
//  Sensor and feature availability detection (battery, SMC). Graceful failure hints.
//

import Foundation

#if os(macOS)
import IOKit
import IOKit.ps
import CoreFoundation
#endif

#if os(macOS)

/// Detects which system features are available (battery, SMC). Used for UI hints and graceful failures.
struct SystemCapabilities: Sendable {
    /// True if the machine has a battery (IOPowerSources list non-empty).
    let hasBattery: Bool
    /// True if AppleSMC is available (thermals/fans); false in sandbox or VM.
    let hasSMC: Bool

    /// Run detection on a background queue; call from main to update UI.
    static func detect() -> SystemCapabilities {
        let battery = detectBattery()
        let smc = detectSMC()
        return SystemCapabilities(hasBattery: battery, hasSMC: smc)
    }

    private static func detectBattery() -> Bool {
        guard let infoRef = IOPSCopyPowerSourcesInfo() else { return false }
        let info = infoRef.takeRetainedValue()
        guard let listRef = IOPSCopyPowerSourcesList(info) else { return false }
        let list = listRef.takeRetainedValue() as [CFTypeRef]
        return !list.isEmpty
    }

    private static func detectSMC() -> Bool {
        let match = IOServiceMatching("AppleSMC")
        let service = IOServiceGetMatchingService(kIOMasterPortDefault, match)
        guard service != 0 else { return false }
        IOObjectRelease(service)
        return true
    }

    /// Short message when SMC is unavailable (permissions or VM).
    static let smcUnavailableHint = "Sensors unavailable (may need to disable App Sandbox or grant Full Disk Access)."
    /// Short message when battery section is hidden (desktop).
    static let noBatteryHint = "No battery (desktop)."
}

#endif
