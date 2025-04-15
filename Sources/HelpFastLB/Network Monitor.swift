import Foundation
import Network

class NetworkMonitor: ObservableObject {
    static var shared = NetworkMonitor()
    let monitor = NWPathMonitor()
    let queue = DispatchQueue(label: "monitor")
    @Published var isActive = false
    @Published var isExpansive = false
    @Published var isConstrained = false
    @Published var connectionType = NWInterface.InterfaceType.other
    @Published var showInternetALert = false
    
    private var wasDisconnected = false
    
    init() {
        monitor.pathUpdateHandler = { path in
            DispatchQueue.main.async {
                let wasConnected = self.isActive
                
                self.isActive = path.status == .satisfied
                self.isExpansive = path.isExpensive
                self.isConstrained = path.isConstrained
                
                let connectionTypes: [NWInterface.InterfaceType] = [.cellular, .wifi, .wiredEthernet]
                self.connectionType = connectionTypes.first(where: path.usesInterfaceType) ?? .other
                
                if !wasConnected && self.isActive {
                    NotificationCenter.default.post(name: .internetConnectionRestored, object: nil)
                }
                
                self.wasDisconnected = !self.isActive
            }
        }
        
        monitor.start(queue: queue)
    }
}
