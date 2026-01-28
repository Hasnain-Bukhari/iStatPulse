//
//  VolumeSpace.swift
//  iStatPulse
//
//  Volume free/total space using getfsstat and statfs.
//

import Foundation

#if os(macOS)
import Darwin

enum VolumeSpace {
    /// Total and available bytes for the root volume ("/"). Returns (0, 0) on failure.
    static func rootVolumeBytes() -> (total: UInt64, available: UInt64) {
        var stat = statfs()
        guard statfs("/", &stat) == 0 else { return (0, 0) }
        let blockSize = UInt64(stat.f_bsize)
        let total = UInt64(stat.f_blocks) * blockSize
        let available = UInt64(stat.f_bavail) * blockSize
        return (total, available)
    }

    /// All mounted filesystems: (mountPath, totalBytes, availableBytes).
    static func allVolumes() -> [(path: String, total: UInt64, available: UInt64)] {
        var count = getfsstat(nil, 0, MNT_NOWAIT)
        guard count > 0 else { return [] }
        let size = Int32(count) * Int32(MemoryLayout<statfs>.size)
        let buf = UnsafeMutablePointer<statfs>.allocate(capacity: Int(count))
        defer { buf.deallocate() }
        count = getfsstat(buf, size, MNT_NOWAIT)
        guard count > 0 else { return [] }
        var result: [(String, UInt64, UInt64)] = []
        for i in 0..<Int(count) {
            var s = buf[i]
            let blockSize = UInt64(s.f_bsize)
            let total = UInt64(s.f_blocks) * blockSize
            let available = UInt64(s.f_bavail) * blockSize
            let path = withUnsafePointer(to: &s.f_mntonname) {
                $0.withMemoryRebound(to: CChar.self, capacity: Int(MAXPATHLEN)) {
                    String(cString: $0)
                }
            }
            result.append((path, total, available))
        }
        return result
    }
}
#endif
