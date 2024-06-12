//
//  BluetoothManager.swift
//  bleep-eval
//
//  Created by Simon Núñez Aschenbrenner on 10.05.24.
//

import Foundation
import CoreBluetooth
import CryptoKit
import OSLog

enum BluetoothMode: Int {
    case central = -1 // Notification Consumer (NC)
    case undefined = 0
    case peripheral = 1 // Notification Provider (NP)
}

struct BluetoothConstants {
    
    static let testAddress = Address(245)
    
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
        address = BluetoothConstants.testAddress // TODO: randomize and persist
        super.init()
        peripheralManagerDelegate = PeripheralManagerDelegate(bluetoothManager: self)
        centralManagerDelegate = CentralManagerDelegate(bluetoothManager: self)
        initMode()
        Logger.bluetooth.debug("BluetoothManager initialized with address '\(self.address.base58Encoded.suffix(BluetoothConstants.suffixLength))'")
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
    
    func publish() {
        Logger.bluetooth.trace("Attempting to \(#function) notifications")
        setMode(to: .peripheral)
    }
    
    func subscribe() {
        Logger.bluetooth.trace("Attempting to \(#function) to notifications")
        setMode(to: .central)
    }
    
    func idle() {
        Logger.bluetooth.debug("Attempting to \(#function)")
        setMode(to: .undefined)
    }
}
