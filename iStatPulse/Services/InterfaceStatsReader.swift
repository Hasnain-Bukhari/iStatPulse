//
//  InterfaceStatsReader.swift
//  iStatPulse
//
//  Per-interface cumulative bytes using getifaddrs (AF_LINK → if_data).
//

import Foundation

#if os(macOS)
import Darwin

enum InterfaceStatsReader {
    /// Cumulative bytes in/out per interface from getifaddrs (AF_LINK if_data).
    /// Returns [(interfaceName, receivedBytes, sentBytes)]. Skips loopback if desired.
    static func cumulativeBytesPerInterface() -> [(name: String, received: UInt64, sent: UInt64)] {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let start = ifaddr else { return [] }
        defer { freeifaddrs(ifaddr) }
        var result: [String: (received: UInt64, sent: UInt64)] = [:]
        var ptr = start
        while true {
            let family = ptr.pointee.ifa_addr.pointee.sa_family
            if family == UInt8(AF_LINK), let data = ptr.pointee.ifa_data {
                let name = String(cString: ptr.pointee.ifa_name)
                let ifData = data.assumingMemoryBound(to: if_data.self).pointee
                let rx = UInt64(ifData.ifi_ibytes)
                let tx = UInt64(ifData.ifi_obytes)
                result[name] = (rx, tx)
            }
            guard let next = ptr.pointee.ifa_next else { break }
            ptr = next
        }
        return result.map { (name: $0.key, received: $0.value.received, sent: $0.value.sent) }
    }
}
#endif
