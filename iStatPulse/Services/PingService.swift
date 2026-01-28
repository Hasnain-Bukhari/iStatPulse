//
//  PingService.swift
//  iStatPulse
//
//  Low-overhead ICMP ping using SOCK_DGRAM IPPROTO_ICMP with timeout.
//

import Foundation

#if os(macOS)
import Darwin

private let ICMP_ECHO: UInt8 = 8
private let ICMP_ECHOREPLY: UInt8 = 0

/// ICMP echo header (type, code, checksum, id, sequence).
private struct ICMPHeader {
    var type: UInt8
    var code: UInt8
    var checksum: UInt16
    var identifier: UInt16
    var sequence: UInt16
}

enum PingService {
    /// Send one ICMP echo to host (IP or hostname) with timeout in seconds. Returns RTT in ms or nil.
    static func ping(host: String, timeout: TimeInterval = 2.0) -> Double? {
        guard let resolved = resolve(host: host) else { return nil }
        var addr = resolved
        let fd = socket(AF_INET, SOCK_DGRAM, IPPROTO_ICMP)
        guard fd >= 0 else { return nil }
        defer { close(fd) }
        var tv = timeval()
        tv.tv_sec = __darwin_time_t(timeout)
        tv.tv_usec = __darwin_suseconds_t((timeout - floor(timeout)) * 1_000_000)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
        let id = UInt16(arc4random() & 0xFFFF)
        let seq: UInt16 = 1
        var header = ICMPHeader(type: ICMP_ECHO, code: 0, checksum: 0, identifier: id, sequence: seq)
        header.checksum = checksum(bytes: UnsafeRawBufferPointer(start: &header, count: MemoryLayout<ICMPHeader>.size))
        let start = CFAbsoluteTimeGetCurrent()
        var addrLen = socklen_t(MemoryLayout<sockaddr_in>.size)
        let sent = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                sendto(fd, &header, MemoryLayout<ICMPHeader>.size, 0, sa, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard sent == MemoryLayout<ICMPHeader>.size else { return nil }
        var buf = [UInt8](repeating: 0, count: 256)
        var from = sockaddr_in()
        let received = withUnsafeMutablePointer(to: &from) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                recvfrom(fd, &buf, buf.count, 0, sa, &addrLen)
            }
        }
        guard received >= MemoryLayout<ICMPHeader>.size else { return nil }
        let offset = (buf[0] == ICMP_ECHOREPLY) ? 0 : 20
        guard offset + 8 <= received else { return nil }
        let replyType = buf[offset]
        guard replyType == ICMP_ECHOREPLY else { return nil }
        let replyId = (UInt16(buf[offset + 4]) << 8) | UInt16(buf[offset + 5])
        let replySeq = (UInt16(buf[offset + 6]) << 8) | UInt16(buf[offset + 7])
        guard replyId == id, replySeq == seq else { return nil }
        let end = CFAbsoluteTimeGetCurrent()
        return (end - start) * 1000.0
    }

    private static func resolve(host: String) -> sockaddr_in? {
        var hints = addrinfo()
        hints.ai_family = AF_INET
        hints.ai_socktype = SOCK_DGRAM
        hints.ai_protocol = IPPROTO_ICMP
        var res: UnsafeMutablePointer<addrinfo>?
        defer { if let r = res { freeaddrinfo(r) } }
        guard getaddrinfo(host, nil, &hints, &res) == 0,
              let info = res,
              info.pointee.ai_family == AF_INET,
              info.pointee.ai_addr.pointee.sa_family == AF_INET else { return nil }
        return info.pointee.ai_addr.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { $0.pointee }
    }

    private static func checksum(bytes: UnsafeRawBufferPointer) -> UInt16 {
        var sum: UInt32 = 0
        var i = 0
        while i < bytes.count - 1 {
            sum &+= UInt32(bytes.load(fromByteOffset: i, as: UInt16.self).bigEndian)
            i += 2
        }
        if i < bytes.count { sum &+= UInt32(bytes[i]) << 8 }
        while sum > 0xFFFF { sum = (sum & 0xFFFF) + (sum >> 16) }
        return UInt16(truncatingIfNeeded: ~sum)
    }
}
#endif
