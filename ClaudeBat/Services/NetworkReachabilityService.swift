import Foundation
import Network

public final class NetworkReachabilityService: NetworkReachabilityChecking, @unchecked Sendable {
    private let monitor: NWPathMonitor
    private let queue = DispatchQueue(label: "claudebat.reachability")
    private let lock = NSLock()
    private var status: NetworkReachabilityStatus = .unknown

    public init() {
        monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] path in
            guard let self else { return }
            self.lock.lock()
            self.status = path.status == .satisfied ? .reachable : .unreachable
            self.lock.unlock()
        }
        monitor.start(queue: queue)
    }

    deinit {
        monitor.cancel()
    }

    public func currentStatus() -> NetworkReachabilityStatus {
        lock.lock()
        defer { lock.unlock() }
        return status
    }
}
