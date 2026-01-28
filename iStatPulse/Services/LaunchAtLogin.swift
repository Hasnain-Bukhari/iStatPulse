//
//  LaunchAtLogin.swift
//  iStatPulse
//
//  Launch at login using SMAppService (macOS 13+). User-controlled; off by default.
//

import Foundation

#if os(macOS)
import ServiceManagement
import AppKit
#endif

#if os(macOS)

enum LaunchAtLogin {
    /// Whether the app is currently registered as a login item.
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// Register as a login item. User will see it in System Settings → General → Login Items.
    static func enable() throws {
        try SMAppService.mainApp.register()
    }

    /// Remove from login items.
    static func disable() throws {
        try SMAppService.mainApp.unregister()
    }

    /// Toggle and return new state. Catches errors and returns false on failure.
    @discardableResult
    static func setEnabled(_ enabled: Bool) -> Bool {
        do {
            if enabled {
                try enable()
            } else {
                try disable()
            }
            return isEnabled == enabled
        } catch {
            return false
        }
    }
}

#endif
