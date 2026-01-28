//
//  FPSSampler.swift
//  iStatPulse
//
//  FPS sampling via CVDisplayLink (macOS display refresh sync).
//  Publishes current frame rate from display link callbacks.
//

import Foundation
import Combine

#if os(macOS)
import CoreVideo
import Darwin

/// Samples display refresh rate (FPS) via CVDisplayLink. Callbacks fire at display vsync.
final class FPSSampler: @unchecked Sendable {
    private let subject = CurrentValueSubject<Double?, Never>(nil)
    private var displayLink: CVDisplayLink?
    private var lastTimestamp: UInt64 = 0
    private let timebase: mach_timebase_info_data_t = {
        var t = mach_timebase_info_data_t()
        mach_timebase_info(&t)
        return t
    }()
    private let queue = DispatchQueue(label: "com.istatpulse.fps", qos: .userInitiated)

    var fpsPublisher: AnyPublisher<Double?, Never> {
        subject.eraseToAnyPublisher()
    }

    func start() {
        stop()
        var link: CVDisplayLink?
        guard CVDisplayLinkCreateWithActiveCGDisplays(&link) == kCVReturnSuccess,
              let displayLink = link else { return }
        self.displayLink = displayLink
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        CVDisplayLinkSetOutputCallback(displayLink, displayLinkCallback, selfPtr)
        CVDisplayLinkStart(displayLink)
    }

    func stop() {
        guard let link = displayLink else { return }
        CVDisplayLinkStop(link)
        self.displayLink = nil
        subject.send(nil)
    }

    func handleFrame(_ inOutputTime: UnsafePointer<CVTimeStamp>) {
        let ts = inOutputTime.pointee.hostTime
        if lastTimestamp != 0 {
            let delta = ts - lastTimestamp
            let nanos = Double(delta) * Double(timebase.numer) / Double(timebase.denom)
            let seconds = nanos / 1_000_000_000
            if seconds > 0 {
                let fps = 1.0 / seconds
                let clamped = min(240, max(24, fps))
                subject.send(clamped)
            }
        }
        lastTimestamp = ts
    }
}

private func displayLinkCallback(
    _ displayLink: CVDisplayLink,
    _ inNow: UnsafePointer<CVTimeStamp>,
    _ inOutputTime: UnsafePointer<CVTimeStamp>,
    _ flagsIn: CVOptionFlags,
    _ flagsOut: UnsafeMutablePointer<CVOptionFlags>,
    _ context: UnsafeMutableRawPointer?
) -> CVReturn {
    guard let ctx = context else { return kCVReturnError }
    let sampler = Unmanaged<FPSSampler>.fromOpaque(ctx).takeUnretainedValue()
    sampler.handleFrame(inOutputTime)
    return kCVReturnSuccess
}
#endif
