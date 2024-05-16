//
//  BluetoothManager.swift
//  bleep-eval
//
//  Created by Simon Núñez Aschenbrenner on 10.05.24.
//

import Foundation
import CoreBluetooth
import OSLog

struct BluetoothConstants {
    
    static let peripheralName = "bleep"
    static let centralIdentifierKey = "com.simon.bleep-eval.central"
    static let peripheralIdentifierKey = "com.simon.bleep-eval.peripheral"
    static let UUIDSuffixLength = 5
    
    static let CBUUIDs: [String: CBUUID] = [
        "testService": CBUUID(string: "d50cfc1b-9fc7-4f07-9fa0-fe7cd33f3e92"),
        "testCharacteristic": CBUUID(string: "f03a20be-b7e9-44cf-b156-685fe9762504"),
    ]
    
    static func getKey(for cbuuid: CBUUID?) -> String? {
        guard cbuuid != nil else {
            Logger.bluetooth.trace("getKey returns nil because the provided CBUUID is nil")
            return nil
        }
        for item in self.CBUUIDs {
            guard item.value.uuidString == cbuuid!.uuidString else { continue }
            Logger.bluetooth.trace("getKey for CBUUID '\(cbuuid?.uuidString ?? "")' is '\(item.key)'")
            return item.key
        }
        Logger.bluetooth.trace("getKey returns nil because it found no matching CBUUID")
        return nil
    }
}

enum BluetoothMode : Int {
    case central = -1
    case undefined = 0
    case peripheral = 1
}

@Observable
class BluetoothManager: NSObject {
        
    private(set) var peripheralManagerDelegate: PeripheralManagerDelegate!
    private(set) var centralManagerDelegate: CentralManagerDelegate!
    
    private(set) var mode: BluetoothMode! {
        didSet {
            let modeString = "\(mode!)"
            Logger.bluetooth.notice("BluetoothManager mode set to '\(modeString)'")
        }
    }
    
    var modeIsPeripheral: Bool {
        return !(mode.rawValue < 1)
    }
    var modeIsCentral: Bool {
        return !(mode.rawValue > -1)
    }
    var modeIsUndefined: Bool {
        return mode.rawValue == 0
    }
    
    // MARK: initializing methods
    
    convenience override init() {
        self.init(peripheralName: BluetoothConstants.peripheralName, serviceUUID: BluetoothConstants.CBUUIDs["testService"], characteristicUUID: BluetoothConstants.CBUUIDs["testCharacteristic"])
    }
    
    init(peripheralName: String!, serviceUUID: CBUUID!, characteristicUUID: CBUUID!) {
        mode = .undefined
        super.init()
        peripheralManagerDelegate = PeripheralManagerDelegate(bluetoothManager: self, name: peripheralName, serviceUUID: serviceUUID, characteristicUUID: characteristicUUID)
        centralManagerDelegate = CentralManagerDelegate(bluetoothManager: self, autoSubscribe: true, serviceUUID: serviceUUID, characteristicUUID: characteristicUUID)
        setMode(to: nil)
        Logger.bluetooth.trace("BluetoothManager initialized")
    }
    
    private func setMode(to mode: BluetoothMode?) {
        if mode != nil {
            self.mode = mode!
        } else {
            let isScanning = centralManagerDelegate.centralManager.isScanning
            let isAdvertising = peripheralManagerDelegate.peripheralManager.isAdvertising
            if (!isAdvertising && !isScanning) || (isAdvertising && isScanning) { // TODO: XOR
                self.mode = .undefined
            } else if isScanning {
                self.mode = .central
            } else if isAdvertising {
                self.mode = .peripheral
            }
        }
    }
    
    // MARK: public methods

    func publish(_ value: String, for characteristicUUID: CBUUID) {
        Logger.bluetooth.debug("Attempting to \(#function) value '\(value)' for characteristic '\(BluetoothConstants.getKey(for: characteristicUUID) ?? "")'")
        peripheralManagerDelegate.value = value
        if !modeIsPeripheral {
            centralManagerDelegate.stopScan()
            setMode(to: .peripheral)
        }
        if peripheralManagerDelegate.peripheralManager.state == .poweredOn && !peripheralManagerDelegate.peripheralManager.isAdvertising {
            peripheralManagerDelegate.startAdvertising()
        }
        // else peripheralManagerDidUpdateState or willRestoreState will call startAdvertising
        // TODO: logging
        let characteristics = peripheralManagerDelegate.service.characteristics
        guard characteristics != nil && characteristics?[0] != nil else {
            Logger.bluetooth.fault("The characteristics array of service '\(BluetoothConstants.getKey(for: self.peripheralManagerDelegate.service.uuid) ?? "")' is nil or empty")
            return
        }
        for characteristic in characteristics! {
            if characteristic.uuid.uuidString == characteristicUUID.uuidString {
                peripheralManagerDelegate.updateValue(for: characteristic as! CBMutableCharacteristic)
                break
            } else { continue }
        }
    }
    
    // TODO: Needs better solution
    func stopPublishing(for characteristicUUID: CBUUID) {
        Logger.bluetooth.debug("Attempting to stop publishing for characteristic '\(BluetoothConstants.getKey(for: characteristicUUID) ?? "")'")
        publish("", for: characteristicUUID)
        centralManagerDelegate.stopScan()
        // TODO: stopAdvertising?
        setMode(to: .undefined)
    }
        
    func subscribe() {
        Logger.bluetooth.trace("Attempting to \(#function)")
        if !modeIsCentral {
            peripheralManagerDelegate.stopAdvertising()
            setMode(to: .central)
        }
        if centralManagerDelegate.centralManager.state == .poweredOn && !centralManagerDelegate.centralManager.isScanning {
            centralManagerDelegate.startScan(andSubscribe: true)
        }
        // else centralManagerDidUpdateState or willRestoreState will call startScan
    }
    
    func unsubscribe(from characteristicUUID: CBUUID, andDisconnectFromPeripheral: Bool = true) {
        Logger.bluetooth.debug("Attempting to unsubscibe from characteristic '\(BluetoothConstants.getKey(for: characteristicUUID) ?? "")' \(andDisconnectFromPeripheral ? "andDisconnectFromPeripheral" : "")")
        guard let peripheral = centralManagerDelegate.peripheral else {
            Logger.bluetooth.fault("Unable to \(#function) from characteristic '\(BluetoothConstants.getKey(for: characteristicUUID) ?? "")', because the peripheral property in the CentralManagerDelegate is nil")
            return
        }
        centralManagerDelegate.unsubscribe(peripheral: peripheral, andDisconnect: andDisconnectFromPeripheral)
        peripheralManagerDelegate.stopAdvertising()
        centralManagerDelegate.stopScan()
        setMode(to: .undefined)
    }
    
// TODO: dry
//    func getCBMutableCharacteristic(from: characteristicUUID CBUUID, in delegate: CBPeer?) {
//        let characteristics = delegate.service.characteristics
//        guard characteristics != nil && characteristics?[0] != nil else {
//            Logger.bluetooth.fault("The characteristics array of service '\(BluetoothConstants.getKey(for: delegate.service.uuid) ?? "")' is nil or empty")
//        }
//        for characteristic in characteristics! {
//            if characteristic.uuid.uuidString == characteristicUUID.uuidString {
//                return characteristic
//            } else { continue }
//        }
//    }
}
