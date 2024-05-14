//
//  PeripheralManager.swift
//  bleep-eval
//
//  Created by Simon Núñez Aschenbrenner on 04.05.24.
//

import Foundation
import CoreBluetooth
import OSLog

@Observable
class PeripheralManagerDelegate: NSObject, CBPeripheralManagerDelegate {
    
    unowned var bluetoothManager: BluetoothManager!
    var peripheralManager: CBPeripheralManager!
    var central: CBCentral?
    
    var name: String!
    var service: CBMutableService! // TODO: list
    var characteristic: CBMutableCharacteristic! // TODO: list
    var value: String! // TODO: queue for each characteristic?
    
    // MARK: initializing methods
    
    init(bluetoothManager: BluetoothManager!, name: String!, serviceUUID: CBUUID!, characteristicUUID: CBUUID!) {
        super.init()
        self.bluetoothManager = bluetoothManager
        self.peripheralManager = CBPeripheralManager(delegate: self, queue: nil, options: [CBPeripheralManagerOptionRestoreIdentifierKey: BluetoothConstants.peripheralIdentifierKey, CBPeripheralManagerOptionShowPowerAlertKey: true])
        self.name = name
        self.service = CBMutableService(type: serviceUUID, primary: true)
        self.characteristic = CBMutableCharacteristic(type: characteristicUUID, properties: [.indicate], value: nil, permissions: [.readable])
        self.service.characteristics = [characteristic]
        self.value = "" // TODO: Better to differentiate between empty and nil string
        Logger.bluetooth.debug("PeripheralManagerDelegate initialized")
    }
    
    // MARK: public methods
    
    func startAdvertising() {
        Logger.bluetooth.debug("Peripheral attempts to \(#function) as '\(self.name!)' with service '\(BluetoothConstants.getKey(for: self.service.uuid) ?? "")' to centrals")
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
        Logger.bluetooth.debug("Peripheral attempts to \(#function) of '\(BluetoothConstants.getKey(for: mutableCharacteristic.uuid) ?? "")'")
        let data: Data = value?.data(using: .utf8) ?? Data()
        if peripheralManager.updateValue(data, for: mutableCharacteristic, onSubscribedCentrals: nil) {
            Logger.bluetooth.info("Peripheral updated value of characteristic '\(BluetoothConstants.getKey(for: mutableCharacteristic.uuid) ?? "")' to '\(self.value ?? "")'")
        } else {
            Logger.bluetooth.notice("Peripheral did not update value of characteristic '\(BluetoothConstants.getKey(for: mutableCharacteristic.uuid) ?? "")' to '\(self.value ?? "")', but will try again")
        }
    }
    
    // MARK: delegate methods
    
    func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
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
    
    func peripheralManager(_ peripheral: CBPeripheralManager, willRestoreState dict: [String : Any]) {
        self.peripheralManager = peripheral
        peripheral.delegate = self
        Logger.bluetooth.debug("In \(#function):willRestoreState")
        // TODO: Readd service?
        if bluetoothManager.mode == .peripheral && !peripheralManager.isAdvertising {
            startAdvertising()
        }
    }
    
    func peripheralManager(_ peripheral: CBPeripheralManager, central: CBCentral, didSubscribeTo characteristic: CBCharacteristic) {
        Logger.bluetooth.info("Central '\(central.identifier.uuidString.suffix(BluetoothConstants.UUIDSuffixLength))' subscribed to characteristic '\(BluetoothConstants.getKey(for: characteristic.uuid) ?? "")' in service '\(BluetoothConstants.getKey(for: characteristic.service?.uuid) ?? "")'")
        updateValue(of: characteristic)
        stopAdvertising()
    }
    
    func peripheralManager(_ peripheral: CBPeripheralManager, central: CBCentral, didUnsubscribeFrom characteristic: CBCharacteristic) {
        Logger.bluetooth.info("Central '\(central.identifier.uuidString.suffix(BluetoothConstants.UUIDSuffixLength))' unsubscribed to characteristic '\(BluetoothConstants.getKey(for: characteristic.uuid) ?? "")' in service '\(BluetoothConstants.getKey(for: characteristic.service?.uuid) ?? "")'")
        if bluetoothManager.mode == .peripheral && !peripheralManager.isAdvertising {
            startAdvertising()
        }
    }
    
    func peripheralManagerIsReady(toUpdateSubscribers peripheral: CBPeripheralManager) {
        Logger.bluetooth.debug("In \(#function):toUpdateSubscribers")
        updateValue(of: nil)
    }
    
    func peripheralManagerDidStartAdvertising(_ peripheral: CBPeripheralManager, error: (any Error)?) {
        if (error != nil) {
            Logger.bluetooth.fault("Peripheral did not start advertising: \(error!.localizedDescription)")
        } else {
            Logger.bluetooth.info("Peripheral started advertising")
        }
    }
    
    func peripheralManager(_ peripheral: CBPeripheralManager, didAdd service: CBService, error: (any Error)?) {
        if (error != nil) {
            Logger.bluetooth.fault("Peripheral did not add service '\(BluetoothConstants.getKey(for: service.uuid) ?? "")': \(error!.localizedDescription)")
        } else {
            Logger.bluetooth.info("Peripheral added service '\(BluetoothConstants.getKey(for: service.uuid) ?? "")'")
        }
    }
}
