//
//  PublicIPService.swift
//  iStatPulse
//
//  Fetches public IP via ipify; used to merge into NetworkMetrics for UI.
//

import Foundation
import Combine

#if os(macOS)

final class PublicIPService: @unchecked Sendable {
    private let subject = CurrentValueSubject<String?, Never>(nil)
    private var timer: DispatchSourceTimer?
    private let queue = DispatchQueue(label: "com.istatpulse.publicip", qos: .utility)
    private let interval: TimeInterval = 300

    var publicIPPublisher: AnyPublisher<String?, Never> { subject.eraseToAnyPublisher() }

    func start() {
        stop()
        fetch()
        timer = DispatchSource.makeTimerSource(queue: queue)
        timer?.schedule(deadline: .now() + interval, repeating: interval)
        timer?.setEventHandler { [weak self] in self?.fetch() }
        timer?.resume()
    }

    func stop() {
        timer?.cancel()
        timer = nil
    }

    private func fetch() {
        guard let url = URL(string: "https://api.ipify.org") else { return }
        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        URLSession.shared.dataTask(with: request) { [weak subject] data, _, _ in
            guard let data = data,
                  let ip = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !ip.isEmpty else { return }
            subject?.send(ip)
        }.resume()
    }
}

#endif
