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
    
    static let serviceUUID = CBUUID(string: "7905F431-B5CE-4E99-A40F-4B1E122D00D0")
    static let notificationSourceUUID = CBUUID(string: "9FBF120D-6301-42D9-8C58-25E699A21DBD")
    static let controlPointUUID = CBUUID(string: "69D1D8F3-45E1-49A8-9821-9BBDFDAAD9D9")
    static let dataSourceUUID = CBUUID(string: "22EAC6E9-24D6-4BB5-BE44-B36ACE7C7BFB")
    
    static func getName(of cbuuid: CBUUID) -> String {
        Logger.bluetooth.trace("In \(#function) for CBUUID '\(cbuuid.uuidString)'")
        switch cbuuid.uuidString {
        case "7905F431-B5CE-4E99-A40F-4B1E122D00D0":
            return "Apple Notification Center Service"
        case "9FBF120D-6301-42D9-8C58-25E699A21DBD":
            return "Notification Source Characteristic"
        case "69D1D8F3-45E1-49A8-9821-9BBDFDAAD9D9":
            return "Control Point Characteristic"
        case "22EAC6E9-24D6-4BB5-BE44-B36ACE7C7BFB":
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
    
    let service: CBMutableService!
    let notificationSource: CBMutableCharacteristic!
    let controlPoint: CBMutableCharacteristic!
    let dataSource: CBMutableCharacteristic!
    
    private(set) var peripheralManagerDelegate: PeripheralManagerDelegate!
    private(set) var centralManagerDelegate: CentralManagerDelegate!
    
    let address: CBUUID!
    
    private(set) var mode: BluetoothMode! {
        didSet {
            let modeString = "\(mode!)"
            Logger.bluetooth.notice("BluetoothManager mode set to '\(modeString)'")
        }
    }
    
    var modeIsPeripheral: Bool { return !(mode.rawValue < 1) }
    var modeIsCentral: Bool { return !(mode.rawValue > -1) }
    var modeIsUndefined: Bool { return mode.rawValue == 0 }
    
    override init() {
        // mode = .undefined
        address = CBUUID(nsuuid: UUID()) // TODO: persist
        service = CBMutableService(type: BluetoothConstants.serviceUUID, primary: true)
        notificationSource = CBMutableCharacteristic(type: BluetoothConstants.notificationSourceUUID, properties: [.indicate], value: nil, permissions: [.readable])
        controlPoint = CBMutableCharacteristic(type: BluetoothConstants.controlPointUUID, properties: [.write], value: nil, permissions: [.writeable])
        dataSource = CBMutableCharacteristic(type: BluetoothConstants.dataSourceUUID, properties: [.indicate], value: nil, permissions: [.readable])
        service.characteristics = [notificationSource, controlPoint, dataSource]
        super.init()
        peripheralManagerDelegate = PeripheralManagerDelegate(bluetoothManager: self)
        centralManagerDelegate = CentralManagerDelegate(bluetoothManager: self)
        setMode(to: nil)
        Logger.bluetooth.trace("BluetoothManager initialized")
    }
    
    private func setMode(to mode: BluetoothMode?) {
        if mode != nil {
            self.mode = mode!
        } else {
            let isScanning = centralManagerDelegate.centralManager.isScanning
            let isAdvertising = peripheralManagerDelegate.peripheralManager.isAdvertising
            if isAdvertising == isScanning {
                self.mode = .undefined
            } else if isScanning {
                self.mode = .central
            } else if isAdvertising {
                self.mode = .peripheral
            }
        }
    }
    
    // MARK: public methods
    
    func publish(_ message: String, categoryID: UInt8 = 0) {
        Logger.bluetooth.debug("Attempting to \(#function) category \(categoryID) message '\(message)'")
        let notificationID = peripheralManagerDelegate.notificationCounter
        peripheralManagerDelegate.notificationCounter += 1
        let notification = Notification(categoryID: categoryID, notificationID: notificationID, attributes: [message])
        peripheralManagerDelegate.notifications[notificationID] = notification
        if !modeIsPeripheral {
            centralManagerDelegate.stopScan() // TODO: disconnect?
            setMode(to: .peripheral)
        }
        if peripheralManagerDelegate.peripheralManager.state == .poweredOn && !peripheralManagerDelegate.peripheralManager.isAdvertising {
            peripheralManagerDelegate.startAdvertising()
        }
        // else peripheralManagerDidUpdateState or willRestoreState will call startAdvertising
        // TODO: logging
        peripheralManagerDelegate.sendNotification(notification)
    }
    
    func subscribe() {
        Logger.bluetooth.trace("Attempting to \(#function)")
        if !modeIsCentral {
            peripheralManagerDelegate.stopAdvertising()
            setMode(to: .central)
        }
        if centralManagerDelegate.centralManager.state == .poweredOn && !centralManagerDelegate.centralManager.isScanning {
            centralManagerDelegate.startScan()
        }
        // else centralManagerDidUpdateState or willRestoreState will call startScan
    }
    
    func idle() {
        Logger.bluetooth.debug("Attempting to \(#function)")
        if modeIsCentral {
            if let peripheral = centralManagerDelegate.peripheral {
                centralManagerDelegate.disconnect(from: peripheral)
            } else {
                Logger.bluetooth.fault("Unable to unsubscribe, because the peripheral property in the CentralManagerDelegate is nil")
            }
        }
        peripheralManagerDelegate.stopAdvertising()
        centralManagerDelegate.stopScan()
        setMode(to: .undefined)
    }
}
