import Cocoa
import CoreBluetooth

// MARK: - BLE Battery Service UUIDs
let batteryServiceUUID = CBUUID(string: "180F")
let batteryLevelCharUUID = CBUUID(string: "2A19")


// MARK: - Battery Manager
class BatteryManager: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    static let shared = BatteryManager()

    var centralManager: CBCentralManager!
    var cornixPeripheral: CBPeripheral?
    var leftBattery: Int?
    var rightBattery: Int?
    var onUpdate: (() -> Void)?

    var discoveredBatteryServices: [CBService] = []

    override init() {
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: nil)
    }

    // MARK: - Central Manager Delegate
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state == .poweredOn {
            connectToCornix()
        }
    }

    func connectToCornix() {
        cornixPeripheral = nil
        leftBattery = nil
        rightBattery = nil
        discoveredBatteryServices = []

        // First, try to find already-connected peripherals (Cornix is paired to macOS)
        let connected = centralManager.retrieveConnectedPeripherals(withServices: [batteryServiceUUID])
        for peripheral in connected {
            let name = peripheral.name ?? ""
            if name.lowercased().contains("cornix") {
                cornixPeripheral = peripheral
                peripheral.delegate = self
                centralManager.connect(peripheral, options: nil)
                return
            }
        }

        // Fallback: scan for new peripherals
        centralManager.scanForPeripherals(withServices: [batteryServiceUUID], options: nil)
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                         advertisementData: [String: Any], rssi RSSI: NSNumber) {
        let name = peripheral.name ?? ""
        if name.lowercased().contains("cornix") {
            centralManager.stopScan()
            cornixPeripheral = peripheral
            peripheral.delegate = self
            centralManager.connect(peripheral, options: nil)
        }
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        peripheral.discoverServices([batteryServiceUUID])
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        leftBattery = nil
        rightBattery = nil
        onUpdate?()
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            self?.connectToCornix()
        }
    }

    // MARK: - Peripheral Delegate
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let services = peripheral.services else { return }
        discoveredBatteryServices = services.filter { $0.uuid == batteryServiceUUID }

        for service in discoveredBatteryServices {
            peripheral.discoverCharacteristics([batteryLevelCharUUID], for: service)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard let chars = service.characteristics else { return }
        for char in chars where char.uuid == batteryLevelCharUUID {
            peripheral.readValue(for: char)
            peripheral.setNotifyValue(true, for: char)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard characteristic.uuid == batteryLevelCharUUID,
              let data = characteristic.value,
              let level = data.first else { return }

        let batteryLevel = Int(level)

        if let service = characteristic.service,
           let index = discoveredBatteryServices.firstIndex(of: service) {
            DispatchQueue.main.async {
                if index == 0 {
                    self.leftBattery = batteryLevel
                } else {
                    self.rightBattery = batteryLevel
                }
                self.onUpdate?()
            }
        }
    }

    // Periodic refresh
    func startPeriodicRead() {
        Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            guard let self = self, let peripheral = self.cornixPeripheral else { return }
            for service in self.discoveredBatteryServices {
                if let chars = service.characteristics {
                    for char in chars where char.uuid == batteryLevelCharUUID {
                        peripheral.readValue(for: char)
                    }
                }
            }
        }
    }
}

// MARK: - App Delegate (Menubar App)
class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    var batteryManager: BatteryManager!

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        updateMenubarTitle()
        setupMenu()

        batteryManager = BatteryManager.shared
        batteryManager.onUpdate = { [weak self] in
            self?.updateMenubarTitle()
        }
        batteryManager.startPeriodicRead()
    }

    func updateMenubarTitle() {
        let mgr = BatteryManager.shared
        let left = mgr.leftBattery.map { "\($0)%" } ?? "--"
        let right = mgr.rightBattery.map { "\($0)%" } ?? "--"
        statusItem.button?.title = "L:\(left) R:\(right)"
    }

    func setupMenu() {
        let menu = NSMenu()

        let refreshItem = NSMenuItem(title: "Refresh", action: #selector(refresh), keyEquivalent: "r")
        refreshItem.target = self
        menu.addItem(refreshItem)

        let reconnectItem = NSMenuItem(title: "Reconnect", action: #selector(reconnect), keyEquivalent: "")
        reconnectItem.target = self
        menu.addItem(reconnectItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    @objc func refresh() {
        guard let peripheral = batteryManager.cornixPeripheral else { return }
        for service in batteryManager.discoveredBatteryServices {
            if let chars = service.characteristics {
                for char in chars where char.uuid == batteryLevelCharUUID {
                    peripheral.readValue(for: char)
                }
            }
        }
    }

    @objc func reconnect() {
        if let peripheral = batteryManager.cornixPeripheral {
            batteryManager.centralManager.cancelPeripheralConnection(peripheral)
        }
        batteryManager.connectToCornix()
    }

    @objc func quit() {
        NSApp.terminate(nil)
    }
}

// MARK: - Main
let app = NSApplication.shared
app.setActivationPolicy(.accessory) // No dock icon
let delegate = AppDelegate()
app.delegate = delegate
app.run()
