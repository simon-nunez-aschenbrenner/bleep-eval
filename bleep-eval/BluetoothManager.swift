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
    static let suffixLength = 5
    
    static let serviceUUID = CBUUID(string: "08373f8c-3635-4b88-8664-1ccc65a60aae")
    static let notificationSourceUUID = CBUUID(string: "c44f6cf4-5bdd-4c8a-b72c-2931be44af0a")
    static let controlPointUUID = CBUUID(string: "9e201989-0725-4fa6-8991-5a1ed1c084b1")
    static let dataSourceUUID = CBUUID(string: "3aaea559-47c6-4cb7-9ca4-eda14b8c05a5")
    
    static func getName(of cbuuid: CBUUID) -> String {
//        Logger.bluetooth.trace("In \(#function) for CBUUID '\(cbuuid.uuidString)'")
        switch cbuuid.uuidString {
        case serviceUUID.uuidString:
            return "Bleep Notification Service"
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

@Observable
class BluetoothManager: NSObject {
    
    private(set) var peripheralManagerDelegate: PeripheralManagerDelegate!
    private(set) var centralManagerDelegate: CentralManagerDelegate!
    
    let address: Address!
    
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
        address = Address() // TODO: persist
        super.init()
        peripheralManagerDelegate = PeripheralManagerDelegate(bluetoothManager: self)
        centralManagerDelegate = CentralManagerDelegate(bluetoothManager: self)
        initMode()
        Logger.bluetooth.debug("BluetoothManager initialized with address '\(self.address.base58EncodedString.suffix(BluetoothConstants.suffixLength))'")
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
        publish(message, categoryID: categoryID, destinationAddress: Address(0)) // Broadcast
    }
    
    func publish(_ message: String, categoryID: UInt8 = 0, destinationAddress: Address) {
        publish(message, categoryID: categoryID, sourceAddress: self.address, destinationAddress: destinationAddress)
    }
    
    func publish(_ notification: Notification, categoryID: UInt8?) {
        publish(notification.message, categoryID: categoryID ?? notification.categoryID, sourceAddress: notification.sourceAddress, destinationAddress: notification.destinationAddress)
    }
    
    func publish(_ message: String, categoryID: UInt8, sourceAddress: Address, destinationAddress: Address) {
        Logger.bluetooth.debug("Attempting to \(#function) category \(categoryID) message '\(message)' intended from '\(sourceAddress.base58EncodedString.suffix(BluetoothConstants.suffixLength))' to '\(destinationAddress.base58EncodedString.suffix(BluetoothConstants.suffixLength))'")
        let notificationID = UInt16(peripheralManagerDelegate.notifications.count)
        let notification = Notification(notificationID: notificationID, categoryID: categoryID, sourceAddress: sourceAddress, destinationAddress: destinationAddress, message: message)
        // peripheralManagerDelegate.notifications[notificationID] = notification
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

struct Notification: CustomStringConvertible {
    let notificationID: UInt16 // messageID: UInt80 = peripheral.address << 16 + notificationID
    let categoryID: UInt8
    let sourceAddress: Address
    let destinationAddress: Address
    var message: String
    
    var description: String {
        return "category \(categoryID) notification #\(notificationID) with message '\(message)' intended from '\(sourceAddress.base58EncodedString.suffix(BluetoothConstants.suffixLength))' to '\(destinationAddress.base58EncodedString.suffix(BluetoothConstants.suffixLength))'"
    }
}

struct Address {
    
    let rawValue: UInt64!
    var base58EncodedString: String {
        return Base58.encode(rawValue)
    }
    
    init() {
        self.rawValue = UInt64.random(in: UInt64.min...UInt64.max)
    }
    
    init(_ value: UInt64) {
        self.rawValue = value
    }
}

struct Base58 {
    
    static let alphabet = Array("123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz")
    
    public static func encode(_ integer: UInt64) -> String {
        var integer = integer
        var result = ""
        while integer > 0 {
            let remainder = Int(integer % 58)
            integer /= 58
            result.append(alphabet[remainder])
        }
        return String(result.reversed())
    }
}
