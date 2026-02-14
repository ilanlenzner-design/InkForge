import Foundation
import AppKit
import WacomAPI

class TabletManager {

    private var contextID: UInt32 = 0
    var tabletName: String = "No tablet"
    var isConnected: Bool = false

    func setup() {
        let tabletCount = WacomTabletDriver.tabletCount()
        guard tabletCount > 0 else {
            print("[TabletManager] No Wacom tablets found")
            return
        }

        isConnected = true
        print("[TabletManager] Found \(tabletCount) tablet(s)")

        // Create a blank context (don't override user's control panel settings)
        contextID = WacomTabletDriver.createContext(forTablet: 1, type: pContextTypeBlank)
        if contextID != 0 {
            print("[TabletManager] Created context: \(contextID)")
        }

        // Query tablet name
        if let routing = WacomTabletDriver.routingTable(forTablet: 1) {
            if let nameDesc = WacomTabletDriver.data(forAttribute: DescType(pName),
                                                       ofType: typeUTF8Text,
                                                       routingTable: routing) {
                tabletName = nameDesc.stringValue ?? "Wacom Tablet"
                print("[TabletManager] Tablet: \(tabletName)")
            }
        }

        // Listen for hardware notifications
        let center = DistributedNotificationCenter.default()
        center.addObserver(self,
                           selector: #selector(tabletControlNotification(_:)),
                           name: NSNotification.Name("com.wacom.tabletdriver.hardware.controldata"),
                           object: "com.wacom.tabletdriver.hardware")
    }

    func teardown() {
        if contextID != 0 {
            WacomTabletDriver.destroyContext(contextID)
            contextID = 0
            print("[TabletManager] Context destroyed")
        }
        DistributedNotificationCenter.default().removeObserver(self)
    }

    @objc private func tabletControlNotification(_ notification: Notification) {
        guard let info = notification.userInfo else { return }
        print("[TabletManager] Control event: \(info)")
    }

    deinit {
        teardown()
    }
}
