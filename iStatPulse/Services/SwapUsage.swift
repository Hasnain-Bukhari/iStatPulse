//
//  SwapUsage.swift
//  iStatPulse
//
//  Reads swap usage via sysctl (vm.swapusage) for memory pressure.
//

import Foundation

#if os(macOS)
import Darwin

enum SwapUsage {
    /// Swap used and total in bytes. Returns (0, 0) when unavailable.
    static func read() -> (used: UInt64, total: UInt64) {
        var name = "vm.swapusage"
        var size = 32
        var buf = [UInt8](repeating: 0, count: size)
        guard name.withCString({ sysctlbyname($0, &buf, &size, nil, 0) == 0 }) else {
            return (0, 0)
        }
        guard size >= 16 else { return (0, 0) }
        let used = buf.withUnsafeBytes { $0.load(fromByteOffset: 0, as: UInt64.self) }
        let total = buf.withUnsafeBytes { $0.load(fromByteOffset: 8, as: UInt64.self) }
        return (used, total)
    }
}
#endif
