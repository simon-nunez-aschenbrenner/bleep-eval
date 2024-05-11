//
//  BluetoothManager.swift
//  bleep-eval
//
//  Created by Simon Núñez Aschenbrenner on 10.05.24.
//

import Foundation
import CoreBluetooth
import OSLog

public enum BluetoothMode : Int {
    case central = -1
    case undefined = 0
    case peripheral = 1
}

struct BluetoothConstants {
    static let testPeripheralName: String = "bleep"
    static let testServiceUUID = CBUUID(string: "d50cfc1b-9fc7-4f07-9fa0-fe7cd33f3e92")
    static let testCharacteristicUUID = CBUUID(string: "f03a20be-b7e9-44cf-b156-685fe9762504")
    static let testUUIDSuffixLength = 5
}

@Observable
class BluetoothManager: NSObject {
    
    private(set) var peripheralManagerDelegate: PeripheralManagerDelegate!
    private(set) var centralManagerDelegate: CentralManagerDelegate!
    
    private(set) var mode: BluetoothMode! {
        didSet {
            Logger.bluetooth.info("BluetoothManager's mode set to \(String(describing: self.mode))")
        }
    }
    
    // MARK: initializing methods
    
    convenience override init() {
        self.init(peripheralName: BluetoothConstants.testPeripheralName, serviceUUID: BluetoothConstants.testServiceUUID, characteristicUUID: BluetoothConstants.testCharacteristicUUID)
    }
    
    init(peripheralName: String!, serviceUUID: CBUUID!, characteristicUUID: CBUUID!) {
        super.init()
        peripheralManagerDelegate = PeripheralManagerDelegate(bluetoothManager: self, name: peripheralName, serviceUUID: serviceUUID, characteristicUUID: characteristicUUID)
        centralManagerDelegate = CentralManagerDelegate(bluetoothManager: self, serviceUUID: serviceUUID, characteristicUUID: characteristicUUID)
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

    func publish(value: String?, serviceUUID: CBUUID?, characteristicUUID: CBUUID?) {
        Logger.bluetooth.debug("\(#function) with value '\(value ?? "")' called for service '\(serviceUUID?.uuidString.suffix(BluetoothConstants.testUUIDSuffixLength) ?? "")' and characteristic '\(characteristicUUID?.uuidString.suffix(BluetoothConstants.testUUIDSuffixLength) ?? "")'")
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
        peripheralManagerDelegate.value = value ?? ""
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
        
    func subscribe(serviceUUID: CBUUID?, characteristicUUID: CBUUID?) {
        Logger.bluetooth.debug("\(#function) called for service '\(serviceUUID?.uuidString.suffix(BluetoothConstants.testUUIDSuffixLength) ?? "")' and characteristic '\(characteristicUUID?.uuidString.suffix(BluetoothConstants.testUUIDSuffixLength) ?? "")'")
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
            centralManagerDelegate.startScan()
        }
        // else centralManagerDidUpdateState or willRestoreState will call startScan
    }
    
    func stop(){
        Logger.bluetooth.debug("\(#function) called")
        peripheralManagerDelegate.stopAdvertising()
        centralManagerDelegate.stopScan()
        setMode(to: .undefined)
    }
}
