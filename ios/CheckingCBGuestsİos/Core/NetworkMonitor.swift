import Foundation
import Network
import Observation

/// Ağ bağlantısı izleyicisi (Android `NetworkConnectivity` eşleniği).
@MainActor
@Observable
final class NetworkMonitor {

    static let shared = NetworkMonitor()

    private(set) var isConnected = true

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "com.checkingcbguests.network-monitor")

    private init() {
        monitor.pathUpdateHandler = { path in
            let connected = path.status == .satisfied
            Task { @MainActor in
                NetworkMonitor.shared.isConnected = connected
            }
        }
        monitor.start(queue: queue)
    }
}
