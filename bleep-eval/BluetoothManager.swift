//
//  BluetoothManager.swift
//  bleep-eval
//
//  Created by Simon Núñez Aschenbrenner on 10.05.24.
//

import Foundation
import CoreBluetooth
import OSLog

enum BluetoothMode: Int {
    case central = -1 // Notification Consumer (NC)
    case undefined = 0
    case peripheral = 1 // Notification Provider (NP)
}

struct BluetoothConstants {
    
    static let peripheralName = "bleeper"
    static let centralIdentifierKey = "com.simon.bleep-eval.central"
    static let peripheralIdentifierKey = "com.simon.bleep-eval.peripheral"
    static let UUIDSuffixLength = 5
    
    static let serviceUUID = CBUUID(string: "7905F431-B5CE-4E99-A40F-4B1E122D00D1")
    static let notificationSourceUUID = CBUUID(string: "9FBF120D-6301-42D9-8C58-25E699A21DBE")
    static let controlPointUUID = CBUUID(string: "69D1D8F3-45E1-49A8-9821-9BBDFDAAD9DA")
    static let dataSourceUUID = CBUUID(string: "22EAC6E9-24D6-4BB5-BE44-B36ACE7C7BFC")
    
    static func getName(of cbuuid: CBUUID) -> String {
//        Logger.bluetooth.trace("In \(#function) for CBUUID '\(cbuuid.uuidString)'")
        switch cbuuid.uuidString {
        case serviceUUID.uuidString:
            return "Apple Notification Center Service"
        case notificationSourceUUID.uuidString:
            return "Notification Source Characteristic"
        case controlPointUUID.uuidString:
            return "Control Point Characteristic"
        case dataSourceUUID.uuidString:
            return "Data Source Characteristic"
        default:
            return cbuuid.uuidString
        }
    }
}

struct Notification {
    var eventID: UInt8 = 0
    var eventFlags: UInt8 = 0
    let categoryID: UInt8
    let notificationID: UInt32
    var attributes: [String]
}

@Observable
class BluetoothManager: NSObject {
    
    private(set) var peripheralManagerDelegate: PeripheralManagerDelegate!
    private(set) var centralManagerDelegate: CentralManagerDelegate!
    
    let address: CBUUID!
    
    private var mode: BluetoothMode! {
        didSet {
            let modeString = "\(mode!)"
            Logger.bluetooth.notice("BluetoothManager mode set to '\(modeString)'")
        }
    }
    
    var modeIsPeripheral: Bool { return !(mode.rawValue < 1) }
    var modeIsCentral: Bool { return !(mode.rawValue > -1) }
    var modeIsUndefined: Bool { return mode.rawValue == 0 }
    
    override init() {
        address = CBUUID(nsuuid: UUID()) // TODO: persist
        super.init()
        peripheralManagerDelegate = PeripheralManagerDelegate(bluetoothManager: self)
        centralManagerDelegate = CentralManagerDelegate(bluetoothManager: self)
        initMode()
        Logger.bluetooth.trace("BluetoothManager initialized")
    }
    
    private func initMode() {
        let isScanning = centralManagerDelegate.centralManager.isScanning
        let isAdvertising = peripheralManagerDelegate.peripheralManager.isAdvertising
        Logger.bluetooth.debug("In \(#function): isScanning = \(isScanning), isAdvertising = \(isAdvertising)")
        if isAdvertising && isScanning { // TODO: handle
            Logger.bluetooth.fault("Could not \(#function): isScanning = \(isScanning), isAdvertising = \(isAdvertising)")
            self.mode = .undefined
        } else if !isAdvertising && !isScanning {
            self.mode = .undefined
        } else if isScanning {
            self.mode = .central
        } else if isAdvertising {
            self.mode = .peripheral
        }
    }
    
    private func setMode(to mode: BluetoothMode) {
        self.mode = mode
        switch mode {
        case .central:
            peripheralManagerDelegate.stopAdvertising()
            centralManagerDelegate.startScan()
        case .peripheral:
            centralManagerDelegate.stopScan()
            centralManagerDelegate.disconnect()
            peripheralManagerDelegate.startAdvertising()
        case .undefined:
            centralManagerDelegate.stopScan()
            centralManagerDelegate.disconnect()
            peripheralManagerDelegate.stopAdvertising()
        }
    }
    
    // MARK: public methods
    
    func publish(_ message: String, categoryID: UInt8 = 0) {
        Logger.bluetooth.debug("Attempting to \(#function) category \(categoryID) message '\(message)'")
        let notificationID = UInt32(peripheralManagerDelegate.notifications.count)
        let notification = Notification(categoryID: categoryID, notificationID: notificationID, attributes: [message])
        peripheralManagerDelegate.notifications[notificationID] = notification
        setMode(to: .peripheral)
        peripheralManagerDelegate.sendNotification(notification)
    }
    
    func subscribe(categoryID: UInt8 = 0) {
        Logger.bluetooth.trace("Attempting to \(#function)")
        setMode(to: .central)
    }
    
    func idle() {
        Logger.bluetooth.debug("Attempting to \(#function)")
        setMode(to: .undefined)
    }
}
