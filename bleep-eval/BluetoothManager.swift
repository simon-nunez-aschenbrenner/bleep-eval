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
        // Logger.bluetooth.debug("getKey for CBUUID '\(cbuuid?.uuidString ?? "")' called")
        guard cbuuid != nil else {
            return nil
        }
        for item in self.CBUUIDs {
            guard item.value.uuidString == cbuuid!.uuidString else { continue }
            return item.key
        }
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
    
    private(set) var mode: BluetoothMode! { // TODO: Change to computed property?
        didSet {
            Logger.bluetooth.info("BluetoothManager's mode set to \(self.mode)")
        }
    }
    
    // MARK: initializing methods
    
    convenience override init() {
        self.init(peripheralName: BluetoothConstants.peripheralName, serviceUUID: BluetoothConstants.CBUUIDs["testService"], characteristicUUID: BluetoothConstants.CBUUIDs["testCharacteristic"])
    }
    
    init(peripheralName: String!, serviceUUID: CBUUID!, characteristicUUID: CBUUID!) {
        super.init()
        peripheralManagerDelegate = PeripheralManagerDelegate(bluetoothManager: self, name: peripheralName, serviceUUID: serviceUUID, characteristicUUID: characteristicUUID)
        centralManagerDelegate = CentralManagerDelegate(bluetoothManager: self, autoSubscribe: true, serviceUUID: serviceUUID, characteristicUUID: characteristicUUID)
        setMode(to: nil)
        Logger.bluetooth.debug("BluetoothManager initialized")
    }
    
    private func setMode(to mode: BluetoothMode?) {
        if mode != nil {
            self.mode = mode
        } else {
            let isScanning = centralManagerDelegate.centralManager.isScanning
            let isAdvertising = peripheralManagerDelegate.peripheralManager.isAdvertising
            if (!isAdvertising && !isScanning) || (isAdvertising && isScanning) { // TODO: XOR
                self.mode = BluetoothMode.undefined
            } else if isScanning {
                self.mode = BluetoothMode.central
            } else if isAdvertising {
                self.mode = BluetoothMode.peripheral
            }
        }
    }
    
    // MARK: public methods

    func publish(_ value: String?, _ serviceUUID: CBUUID?, _ characteristicUUID: CBUUID?) {
        Logger.bluetooth.debug("\(#function) with value '\(value ?? "")' called for characteristic '\(BluetoothConstants.getKey(for: characteristicUUID) ?? "")' in service '\(BluetoothConstants.getKey(for: serviceUUID) ?? "")'")
        guard (characteristicUUID == nil || characteristicUUID!.uuidString == peripheralManagerDelegate.service!.uuid.uuidString) else { // TODO: handle
            Logger.bluetooth.error("\(#function) called with mismatching characteristicUUID")
            // peripheralManagerDelegate.characteristic = CBMutableCharacteristic(type: characteristicUUID!, properties: [.indicate], value: nil, permissions: [.readable])
            // peripheralManagerDelegate.service!.characteristics = [peripheralManagerDelegate.characteristic!]
            return
        }
        guard (serviceUUID == nil || serviceUUID!.uuidString == peripheralManagerDelegate.service!.uuid.uuidString) else { // TODO: handle
            Logger.bluetooth.error("\(#function) called with mismatching serviceUUID")
            // peripheralManagerDelegate.peripheralManager.remove(peripheralManagerDelegate.service!)
            // peripheralManagerDelegate.service = CBMutableService(type: serviceUUID!, primary: true)
            // peripheralManagerDelegate.peripheralManager.add(peripheralManagerDelegate.service!)
            return
        }
        if (value == nil) { // When called with nil -> stop
            peripheralManagerDelegate.stopAdvertising()
            centralManagerDelegate.stopScan()
            setMode(to: .undefined)
        } else {
            peripheralManagerDelegate.value = value!
            if mode.rawValue < 1 {
                centralManagerDelegate.stopScan()
                setMode(to: .peripheral)
                if peripheralManagerDelegate.peripheralManager.state == .poweredOn && !peripheralManagerDelegate.peripheralManager.isAdvertising {
                    peripheralManagerDelegate.startAdvertising()
                }// else peripheralManagerDidUpdateState or willRestoreState will call startAdvertising
            } else {
                peripheralManagerDelegate.updateValue(of: nil)
            }
        }
    }
        
    func subscribe(_ serviceUUID: CBUUID?, _ characteristicUUID: CBUUID?) {
        Logger.bluetooth.debug("\(#function) called for characteristic '\(BluetoothConstants.getKey(for: characteristicUUID) ?? "")' in service '\(BluetoothConstants.getKey(for: serviceUUID) ?? "")'")
        guard (characteristicUUID == nil || characteristicUUID!.uuidString == centralManagerDelegate.characteristic!.uuid.uuidString) else {
            Logger.bluetooth.error("\(#function) called with mismatching characteristicUUID")
            // centralManagerDelegate.characteristic = CBMutableCharacteristic(type: characteristicUUID!, properties: [.indicate], value: nil, permissions: [.readable])
            // centralManagerDelegate.service!.characteristics = [centralManagerDelegate.characteristic!]
            return
        }
        guard (serviceUUID == nil || serviceUUID!.uuidString == centralManagerDelegate.service!.uuid.uuidString) else { // TODO: handle
            Logger.bluetooth.error("\(#function) called with mismatching serviceUUID")
            // centralManagerDelegate.service = CBMutableService(type: serviceUUID!, primary: true)
            return
        }
        if mode.rawValue > -1 {
            peripheralManagerDelegate.stopAdvertising()
            setMode(to: .central)
        }
        if centralManagerDelegate.centralManager.state == .poweredOn && !centralManagerDelegate.centralManager.isScanning {
            centralManagerDelegate.startScan(true)
        }
        // else centralManagerDidUpdateState or willRestoreState will call startScan
    }
    
    func stopPublishing() {
        Logger.bluetooth.info("Attempting to stop publishing")
        publish(nil, nil, nil)
    }
    
    // TODO: Rename, we're actually disconnecting
    func unsubscribe(_ serviceUUID: CBUUID?, _ characteristicUUID: CBUUID?) {
        guard let peripheralToDisconnect = centralManagerDelegate.peripheral else {
            Logger.bluetooth.fault("Unable to \(#function) from characteristic '\(BluetoothConstants.getKey(for: characteristicUUID) ?? "")' in service '\(BluetoothConstants.getKey(for: serviceUUID) ?? "")', because peripheral is nil")
            return
        }
        Logger.bluetooth.info("\(#function) from characteristic '\(BluetoothConstants.getKey(for: characteristicUUID) ?? "")' in service '\(BluetoothConstants.getKey(for: serviceUUID) ?? "")' on '\(peripheralToDisconnect.identifier.uuidString.suffix(BluetoothConstants.UUIDSuffixLength))'")
        centralManagerDelegate.disconnect(peripheral: peripheralToDisconnect, andStartScan: false)
        peripheralManagerDelegate.stopAdvertising()
        centralManagerDelegate.stopScan()
        setMode(to: .undefined)
    }
}
