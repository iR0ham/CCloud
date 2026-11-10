import Foundation
import Network
import Combine

// MARK: - Connectivity watch
//
// One path monitor for the whole app. The player uses it to tell "the link is dead" from "the
// network went away", and to rejoin the stream on its own when the connection comes back.

@MainActor
final class ConnectionWatch: ObservableObject {

    static let shared = ConnectionWatch()

    @Published private(set) var isConnected = true

    private let monitor = NWPathMonitor()
    private var started = false
    private var simulated = false

    private init() {}

    func start() {
        guard !started else { return }
        started = true
        let queue = DispatchQueue(label: "ir.ccloud.macapp.connection")
        monitor.pathUpdateHandler = { [weak self] path in
            let connected = path.status == .satisfied
            Task { @MainActor [weak self] in
                guard let self, !self.simulated else { return }
                self.isConnected = connected
            }
        }
        monitor.start(queue: queue)
    }

    /// The player harness cannot unplug a cable, so it drives this instead. Takes the real
    /// monitor out of the loop for the rest of the process.
    func simulate(connected: Bool) {
        simulated = true
        isConnected = connected
    }
}
