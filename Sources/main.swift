import Cocoa
import CoreBluetooth
import UserNotifications

// MARK: - BLE Battery Service UUIDs
let batteryServiceUUID = CBUUID(string: "180F")
let batteryLevelCharUUID = CBUUID(string: "2A19")
// Custom RMK charging state characteristics (defined in our rmk fork)
let chargingCentralCharUUID = CBUUID(string: "A8B40001-C0E0-4B1E-A1A4-1C0C0C0C0001")
let chargingPeripheralCharUUID = CBUUID(string: "A8B40001-C0E0-4B1E-A1A4-1C0C0C0C0002")

// MARK: - Notification Helper
enum ConnectionState {
    case unknown, connected, disconnected
}

func sendNotification(title: String, body: String) {
    let content = UNMutableNotificationContent()
    content.title = title
    content.body = body
    content.sound = .default

    let request = UNNotificationRequest(
        identifier: UUID().uuidString,
        content: content,
        trigger: nil
    )
    UNUserNotificationCenter.current().add(request)
}


// MARK: - Battery Manager
class BatteryManager: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    static let shared = BatteryManager()

    var centralManager: CBCentralManager!
    var cornixPeripheral: CBPeripheral?
    var leftBattery: Int?
    var rightBattery: Int?
    var leftCharging: Bool = false
    var rightCharging: Bool = false
    var onUpdate: (() -> Void)?

    var discoveredBatteryServices: [CBService] = []
    private var connectionState: ConnectionState = .unknown

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
        sendNotification(title: "Cornix 接続", body: "キーボードに接続しました")
        connectionState = .connected
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        if connectionState == .connected {
            sendNotification(title: "Cornix 切断", body: "キーボードとの接続が切れました")
        }
        connectionState = .disconnected

        leftBattery = nil
        rightBattery = nil
        leftCharging = false
        rightCharging = false
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
            peripheral.discoverCharacteristics(
                [batteryLevelCharUUID, chargingCentralCharUUID, chargingPeripheralCharUUID],
                for: service
            )
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard let chars = service.characteristics else { return }
        for char in chars {
            switch char.uuid {
            case batteryLevelCharUUID,
                 chargingCentralCharUUID,
                 chargingPeripheralCharUUID:
                peripheral.readValue(for: char)
                peripheral.setNotifyValue(true, for: char)
            default:
                break
            }
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard let data = characteristic.value, let firstByte = data.first else { return }

        switch characteristic.uuid {
        case batteryLevelCharUUID:
            let batteryLevel = Int(firstByte)
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
        case chargingCentralCharUUID:
            DispatchQueue.main.async {
                self.leftCharging = (firstByte != 0)
                self.onUpdate?()
            }
        case chargingPeripheralCharUUID:
            DispatchQueue.main.async {
                self.rightCharging = (firstByte != 0)
                self.onUpdate?()
            }
        default:
            break
        }
    }

    // Periodic refresh
    func startPeriodicRead() {
        Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            guard let self = self, let peripheral = self.cornixPeripheral else { return }
            for service in self.discoveredBatteryServices {
                if let chars = service.characteristics {
                    for char in chars {
                        switch char.uuid {
                        case batteryLevelCharUUID,
                             chargingCentralCharUUID,
                             chargingPeripheralCharUUID:
                            peripheral.readValue(for: char)
                        default:
                            break
                        }
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

        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }

        batteryManager = BatteryManager.shared
        batteryManager.onUpdate = { [weak self] in
            self?.updateMenubarTitle()
        }
        batteryManager.startPeriodicRead()
    }

    func updateMenubarTitle() {
        let mgr = BatteryManager.shared
        let attr = NSMutableAttributedString()
        attr.append(formatSide(label: "L:", level: mgr.leftBattery, charging: mgr.leftCharging))
        attr.append(NSAttributedString(string: " "))
        attr.append(formatSide(label: "R:", level: mgr.rightBattery, charging: mgr.rightCharging))
        statusItem.button?.attributedTitle = attr
    }

    private func formatSide(label: String, level: Int?, charging: Bool) -> NSAttributedString {
        let valueStr: String
        let color: NSColor
        if let lv = level {
            valueStr = "\(lv)%\(charging ? "⚡" : "")"
            color = lv < 20 ? .systemRed : .labelColor
        } else {
            valueStr = "--"
            color = .labelColor
        }
        return NSAttributedString(string: "\(label)\(valueStr)", attributes: [.foregroundColor: color])
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
                for char in chars {
                    switch char.uuid {
                    case batteryLevelCharUUID,
                         chargingCentralCharUUID,
                         chargingPeripheralCharUUID:
                        peripheral.readValue(for: char)
                    default:
                        break
                    }
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
