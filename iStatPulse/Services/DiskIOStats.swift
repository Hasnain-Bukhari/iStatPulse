//
//  DiskIOStats.swift
//  iStatPulse
//
//  Per-disk cumulative read/write bytes from IOKit IOBlockStorageDriver.
//  Used to compute rolling throughput over 1-second windows.
//

import Foundation

#if os(macOS)
import IOKit
import CoreFoundation
import Darwin

private let kIOBlockStorageDriverClass = "IOBlockStorageDriver"
private let kStatisticsKey = "Statistics"
private let kBytesReadKey = "Bytes (Read)"
private let kBytesWrittenKey = "Bytes (Written)"

enum DiskIOStats {
    /// Sum of cumulative bytes read and written across all IOBlockStorageDriver instances.
    /// Returns (bytesRead, bytesWritten); (0, 0) when unavailable.
    static func cumulativeBytes() -> (read: UInt64, write: UInt64) {
        var totalRead: UInt64 = 0
        var totalWrite: UInt64 = 0
        let match = kIOBlockStorageDriverClass.withCString { IOServiceMatching($0) }
        var iterator: io_iterator_t = 0
        defer { if iterator != 0 { IOObjectRelease(iterator) } }
        guard IOServiceGetMatchingServices(kIOMasterPortDefault, match, &iterator) == KERN_SUCCESS else {
            return (0, 0)
        }
        var service = IOIteratorNext(iterator)
        defer { if service != 0 { IOObjectRelease(service) } }
        while service != 0 {
            defer { IOObjectRelease(service); service = IOIteratorNext(iterator) }
            var statsDict: Unmanaged<CFMutableDictionary>?
            guard IORegistryEntryCreateCFProperties(service, &statsDict, kCFAllocatorDefault, 0) == KERN_SUCCESS,
                  let cf = statsDict?.takeRetainedValue() as? [String: Any],
                  let stats = cf[kStatisticsKey] as? [String: Any] else { continue }
            if let r = numberFrom(stats, keys: [kBytesReadKey, "Bytes(Read)"]) { totalRead = totalRead &+ r }
            if let w = numberFrom(stats, keys: [kBytesWrittenKey, "Bytes(Written)"]) { totalWrite = totalWrite &+ w }
        }
        return (totalRead, totalWrite)
    }

    private static func numberFrom(_ dict: [String: Any], keys: [String]) -> UInt64? {
        for key in keys {
            if let v = dict[key] {
                if let n = v as? Int { return UInt64(bitPattern: Int64(n)) }
                if let n = v as? Int64 { return UInt64(bitPattern: n) }
                if let n = v as? UInt64 { return n }
                if let n = v as? NSNumber { return n.uint64Value }
            }
        }
        return nil
    }
}
#endif
