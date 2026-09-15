import Combine
import Foundation
import GlanceCore

final class ProcessStore: ObservableObject {
    @Published private(set) var snapshot = ProcessSnapshot()
    @Published private(set) var refreshing = false
    private let reader = ProcessReader()
    private let queue = DispatchQueue(label: "Glance.processes", qos: .utility)
    private var timer: Timer?
    private var generation = UUID()
    var active: Bool { timer != nil }

    func setActive(_ enabled: Bool) {
        guard enabled != active else { return }
        generation = UUID()
        timer?.invalidate(); timer = nil
        refreshing = false
        queue.async { [reader] in reader.reset() }
        if enabled {
            snapshot = ProcessSnapshot()
            timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in self?.sample() }
            timer?.tolerance = 0.3
            sample()
        }
    }
    private func sample() {
        guard !refreshing else { return }
        refreshing = true
        let token = generation
        queue.async { [weak self] in
            guard let self else { return }
            let sample = reader.read()
            DispatchQueue.main.async {
                guard self.generation == token, self.active else { return }
                self.snapshot = sample; self.refreshing = false
            }
        }
    }
    deinit { timer?.invalidate() }
}
