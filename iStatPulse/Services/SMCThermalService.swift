//
//  SMCThermalService.swift
//  iStatPulse
//
//  Reads CPU/package temperature from AppleSMC via IOKit.
//  Keys: TC0P (package), TC0D (diode), etc. Returns °C.
//

import Foundation
import Combine

#if os(macOS)
import IOKit
import Darwin

/// Reads thermal sensors from AppleSMC. Returns nil when unavailable (e.g. sandbox, Apple Silicon key differences).
final class SMCThermalService: @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.istatpulse.smc", qos: .userInitiated)

    /// SMC read buffer: key (4) + pad (22) + dataSize (4) + pad (10) + cmd (1) + pad (4) + data (32) = 77 bytes.
    private static let smcBufferSize = 77
    private static let dataOffset = 45

    private static func keyBytes(_ s: String) -> [UInt8] {
        Array(s.utf8.prefix(4))
    }

    /// Read one SMC key and parse as temperature (°C). Tries TC0P (package), then TC0D.
    func readCPUTemperature() -> Double? {
        withConnection { conn in
            for keyName in ["TC0P", "TC0D", "TC0E", "TC0F"] {
                if let temp = readKey(conn: conn, key: keyName) { return temp }
            }
            return nil
        }
    }

    /// Read temperature for any 4-char SMC key (e.g. TG0P for GPU). Returns °C or nil.
    func readTemperature(key keyName: String) -> Double? {
        withConnection { conn in readKey(conn: conn, key: keyName) }
    }

    private func withConnection<T>(_ body: (io_connect_t) -> T?) -> T? {
        var conn: io_connect_t = 0
        defer { if conn != 0 { _ = IOServiceClose(conn) } }
        let match = IOServiceMatching("AppleSMC")
        let service = IOServiceGetMatchingService(kIOMasterPortDefault, match)
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        guard IOServiceOpen(service, mach_task_self_, 0, &conn) == KERN_SUCCESS, conn != 0 else { return nil }
        return body(conn)
    }

    private func readKey(conn: io_connect_t, key keyName: String) -> Double? {
        var input = [UInt8](repeating: 0, count: Self.smcBufferSize)
        let k = Self.keyBytes(keyName)
        guard k.count == 4 else { return nil }
        input[0] = k[0]; input[1] = k[1]; input[2] = k[2]; input[3] = k[3]
        input[26] = 32
        input[27] = 0
        input[28] = 0
        input[29] = 0
        input[40] = 5

        var output = [UInt8](repeating: 0, count: Self.smcBufferSize)
        var outSize = output.count
        let kr = input.withUnsafeMutableBytes { inp in
            output.withUnsafeMutableBytes { out in
                IOConnectCallStructMethod(
                    conn,
                    2,
                    inp.baseAddress, inp.count,
                    out.baseAddress, &outSize
                )
            }
        }
        guard kr == KERN_SUCCESS, outSize >= Self.dataOffset + 2 else { return nil }
        let b0 = output[Self.dataOffset]
        let b1 = output[Self.dataOffset + 1]
        let raw = Int16(bitPattern: (UInt16(b0) << 8) | UInt16(b1))
        let celsius = Double(raw) / 256.0
        guard celsius > -10, celsius < 150 else { return nil }
        return celsius
    }
}
#endif
