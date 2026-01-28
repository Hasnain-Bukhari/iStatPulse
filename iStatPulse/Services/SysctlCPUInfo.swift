//
//  SysctlCPUInfo.swift
//  iStatPulse
//
//  sysctl-based CPU topology: P/E core counts (Apple Silicon), frequency (Intel).
//

import Foundation

#if os(macOS)
import Darwin

enum SysctlCPUInfo {

    /// Total logical CPUs (hw.ncpu).
    static var logicalCPUCount: Int {
        var count: Int = 0
        var size = MemoryLayout<Int>.size
        sysctlbyname("hw.ncpu", &count, &size, nil, 0)
        return max(0, count)
    }

    /// Number of performance levels (2 on Apple Silicon = P + E; 1 on Intel).
    static var perfLevelCount: Int {
        var n: Int32 = 0
        var size = MemoryLayout<Int32>.size
        guard sysctlbyname("hw.nperflevels", &n, &size, nil, 0) == 0 else { return 1 }
        return Int(max(1, n))
    }

    /// Logical CPU count at performance level 0 (P-cores on Apple Silicon).
    static var perfLevel0LogicalCPU: Int {
        var n: Int32 = 0
        var size = MemoryLayout<Int32>.size
        guard sysctlbyname("hw.perflevel0.logicalcpu", &n, &size, nil, 0) == 0 else { return 0 }
        return Int(max(0, n))
    }

    /// Logical CPU count at performance level 1 (E-cores on Apple Silicon).
    static var perfLevel1LogicalCPU: Int {
        var n: Int32 = 0
        var size = MemoryLayout<Int32>.size
        guard sysctlbyname("hw.perflevel1.logicalcpu", &n, &size, nil, 0) == 0 else { return 0 }
        return Int(max(0, n))
    }

    /// P-core count (perflevel0). 0 on Intel.
    static var coreCountP: Int { perfLevel0LogicalCPU }

    /// E-core count (perflevel1). 0 on Intel.
    static var coreCountE: Int { perfLevel1LogicalCPU }

    /// CPU frequency in Hz (Intel: hw.cpufrequency; often 0 on Apple Silicon).
    static var frequencyHz: UInt64 {
        var freq: UInt64 = 0
        var size = MemoryLayout<UInt64>.size
        if sysctlbyname("hw.cpufrequency", &freq, &size, nil, 0) == 0 {
            return freq
        }
        if sysctlbyname("hw.cpufrequency_max", &freq, &size, nil, 0) == 0 {
            return freq
        }
        return 0
    }

    /// CPU frequency in MHz.
    static var frequencyMHz: Double {
        Double(frequencyHz) / 1_000_000
    }

    /// Indices [0..<pCount] are P-cores, [pCount..<total] are E-cores. Returns (pCount, eCount).
    static var pCoreAndECoreCounts: (p: Int, e: Int) {
        let p = coreCountP
        let e = coreCountE
        if p > 0 || e > 0 { return (p, e) }
        return (0, 0)
    }
}
#endif
