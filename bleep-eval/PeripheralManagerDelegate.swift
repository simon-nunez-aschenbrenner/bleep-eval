//
//  PeripheralManager.swift
//  bleep-eval
//
//  Created by Simon Núñez Aschenbrenner on 04.05.24.
//

import Foundation
import CoreBluetooth
import OSLog

class PeripheralManagerDelegate: NSObject, CBPeripheralManagerDelegate, ObservableObject {
    
    unowned var bluetoothManager: BluetoothManager!
    internal var peripheralManager: CBPeripheralManager!
    internal var central: CBCentral?
    
    internal var name: String!
    internal var service: CBMutableService! // TODO: list
    internal var characteristic: CBMutableCharacteristic! // TODO: list
    @Published internal var value: String? // TODO: queue for each characteristic?
    
    // MARK: initializing methods
    
    init(bluetoothManager: BluetoothManager!, name: String!, serviceUUID: CBUUID!, characteristicUUID: CBUUID!) {
        super.init()
        self.bluetoothManager = bluetoothManager
        self.peripheralManager = CBPeripheralManager(delegate: self, queue: nil, options: [CBPeripheralManagerOptionRestoreIdentifierKey: "com.simon.bleep-eval.peripheral", CBPeripheralManagerOptionShowPowerAlertKey: true])
        self.name = name
        self.service = CBMutableService(type: serviceUUID, primary: true)
        self.characteristic = CBMutableCharacteristic(type: characteristicUUID, properties: [.indicate], value: nil, permissions: [.readable])
        self.service.characteristics = [characteristic]
        Logger.bluetooth.debug("PeripheralManagerDelegate initialized")
    }
    
    // MARK: public methods
    
    func startAdvertising() {
        Logger.bluetooth.debug("Peripheral attempts to \(#function) as '\(self.name!)' with service '\(self.service!.uuid.uuidString.suffix(BluetoothConstants.testUUIDSuffixLength))' to centrals")
        peripheralManager.startAdvertising([CBAdvertisementDataServiceUUIDsKey: [service.uuid], CBAdvertisementDataLocalNameKey: name!])
    }
    
    func stopAdvertising() {
        Logger.bluetooth.debug("Peripheral attempts to \(#function)")
        if peripheralManager.isAdvertising {
            peripheralManager.stopAdvertising()
            // TODO: Can we verify advertising has stopped?
            //!peripheralManager.isAdvertising ? Logger.bluetooth.info("Peripheral stopped advertising") : Logger.bluetooth.error("Peripheral did not stop advertising")
        } else {
            Logger.bluetooth.debug("Peripheral was not advertising")
        }
    }
        
    func updateValue(of characteristic: CBCharacteristic?) {
        let mutableCharacteristic: CBMutableCharacteristic
        if characteristic == nil {
            mutableCharacteristic = self.characteristic
        } else {
            mutableCharacteristic = characteristic as! CBMutableCharacteristic
        }
        Logger.bluetooth.debug("Peripheral attempts to \(#function) of '\(mutableCharacteristic.uuid.uuidString.suffix(BluetoothConstants.testUUIDSuffixLength))'")
        let data: Data = value?.data(using: .utf8) ?? Data()
        if peripheralManager.updateValue(data, for: mutableCharacteristic, onSubscribedCentrals: nil) {
            Logger.bluetooth.info("Peripheral updated value of characteristic '\(mutableCharacteristic.uuid.uuidString.suffix(BluetoothConstants.testUUIDSuffixLength))' to '\(self.value ?? "")'")
        } else {
            Logger.bluetooth.notice("Peripheral did not update value of characteristic '\(mutableCharacteristic.uuid.uuidString.suffix(BluetoothConstants.testUUIDSuffixLength))' to '\(self.value ?? "")', but will try again")
        }
    }
    
    // MARK: delegate methods
    
    internal func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        switch peripheral.state {
        case .poweredOn:
            Logger.bluetooth.info("\(#function) to 'poweredOn'")
            peripheralManager.add(service!)
            if bluetoothManager.mode == .peripheral && !peripheralManager.isAdvertising {
                startAdvertising()
            }
        case .unknown: // TODO: handle
            Logger.bluetooth.notice("\(#function) to 'unknown'")
        case .resetting: // TODO: handle
            Logger.bluetooth.notice("\(#function): 'resetting'")
        case .unsupported: // TODO: handle
            Logger.bluetooth.error("\(#function): 'unsupported'")
        case .unauthorized: // TODO: handle
            Logger.bluetooth.error("\(#function): 'unauthorized'")
            Logger.bluetooth.notice("CBManager authorization: \(CBPeripheralManager.authorization.rawValue)") // TODO: handle incl. authorization cases
        case .poweredOff: // TODO: handle
            Logger.bluetooth.error("\(#function): 'poweredOff'")
        @unknown default: // TODO: handle
            Logger.bluetooth.error("\(#function) to not implemented state: \(peripheral.state.rawValue)")
        }
    }
    
    internal func peripheralManager(_ peripheral: CBPeripheralManager, willRestoreState dict: [String : Any]) {
        self.peripheralManager = peripheral
        peripheral.delegate = self
        Logger.bluetooth.debug("In \(#function):willRestoreState")
        // TODO: Readd service?
        if bluetoothManager.mode == .peripheral && !peripheralManager.isAdvertising {
            startAdvertising()
        }
    }
    
    internal func peripheralManager(_ peripheral: CBPeripheralManager, central: CBCentral, didSubscribeTo characteristic: CBCharacteristic) {
        Logger.bluetooth.info("Central '\(central.identifier.uuidString.suffix(BluetoothConstants.testUUIDSuffixLength))' subscribed to characteristic '\(characteristic.uuid.uuidString.suffix(BluetoothConstants.testUUIDSuffixLength))'")
        updateValue(of: characteristic)
        stopAdvertising()
    }
    
    internal func peripheralManager(_ peripheral: CBPeripheralManager, central: CBCentral, didUnsubscribeFrom characteristic: CBCharacteristic) {
        Logger.bluetooth.info("Central '\(central.identifier.uuidString.suffix(BluetoothConstants.testUUIDSuffixLength))' unsubscribed from characteristic '\(characteristic.uuid.uuidString.suffix(BluetoothConstants.testUUIDSuffixLength))'")
        if bluetoothManager.mode == .peripheral && !peripheralManager.isAdvertising {
            startAdvertising()
        }
    }
    
    internal func peripheralManagerIsReady(toUpdateSubscribers peripheral: CBPeripheralManager) {
        Logger.bluetooth.debug("In \(#function):toUpdateSubscribers")
        updateValue(of: nil)
    }
    
    internal func peripheralManagerDidStartAdvertising(_ peripheral: CBPeripheralManager, error: (any Error)?) {
        if (error != nil) {
            Logger.bluetooth.fault("Peripheral did not start advertising: \(error!.localizedDescription)")
        } else {
            Logger.bluetooth.info("Peripheral started advertising")
        }
    }
    
    internal func peripheralManager(_ peripheral: CBPeripheralManager, didAdd service: CBService, error: (any Error)?) {
        if (error != nil) {
            Logger.bluetooth.fault("Peripheral did not add service '\(service.uuid.uuidString.suffix(BluetoothConstants.testUUIDSuffixLength))': \(error!.localizedDescription)")
        } else {
            Logger.bluetooth.info("Peripheral added service '\(service.uuid.uuidString.suffix(BluetoothConstants.testUUIDSuffixLength))'")
        }
    }
}
