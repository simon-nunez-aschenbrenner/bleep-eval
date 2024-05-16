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
        Logger.bluetooth.trace("PeripheralManagerDelegate initialized")
    }
    
    // MARK: public methods
    
    func startAdvertising() {
        Logger.bluetooth.debug("Peripheral attempts to \(#function) as '\(self.name!)' with service '\(BluetoothConstants.getKey(for: self.service.uuid) ?? "")' to centrals")
        peripheralManager.startAdvertising([CBAdvertisementDataServiceUUIDsKey: [service.uuid], CBAdvertisementDataLocalNameKey: name!])
    }
    
    func stopAdvertising() {
        Logger.bluetooth.trace("Peripheral attempts to \(#function)")
        peripheralManager.isAdvertising ? peripheralManager.stopAdvertising() : Logger.bluetooth.trace("Peripheral was not advertising")
    }
        
    func updateValue(for characteristic: CBMutableCharacteristic) {
        Logger.bluetooth.debug("Peripheral attempts to \(#function) for '\(BluetoothConstants.getKey(for: characteristic.uuid) ?? "")'")
        let data: Data = value?.data(using: .utf8) ?? Data()
        if peripheralManager.updateValue(data, for: characteristic, onSubscribedCentrals: nil) {
            Logger.bluetooth.notice("Peripheral updated value for characteristic '\(BluetoothConstants.getKey(for: characteristic.uuid) ?? "")' to '\(self.value ?? "")'")
        } else {
            Logger.bluetooth.warning("Peripheral did not update value of characteristic '\(BluetoothConstants.getKey(for: characteristic.uuid) ?? "")' to '\(self.value ?? "")', but will try again")
        }
    }
    
    // MARK: delegate methods
    
    func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        switch peripheral.state {
        case .poweredOn:
            Logger.bluetooth.notice("\(#function) to 'poweredOn'")
            peripheralManager.add(service!)
            if bluetoothManager.mode == .peripheral && !peripheralManager.isAdvertising {
                startAdvertising()
            }
        // TODO: handle other cases incl. authorization cases
        case .unknown:
            Logger.bluetooth.warning("\(#function) to 'unknown'")
        case .resetting:
            Logger.bluetooth.warning("\(#function): 'resetting'")
        case .unsupported:
            Logger.bluetooth.error("\(#function): 'unsupported'")
        case .unauthorized:
            Logger.bluetooth.error("\(#function): 'unauthorized'")
            Logger.bluetooth.error("CBManager authorization: \(CBPeripheralManager.authorization.rawValue)")
        case .poweredOff:
            Logger.bluetooth.error("\(#function): 'poweredOff'")
        @unknown default:
            Logger.bluetooth.error("\(#function) to not implemented state: \(peripheral.state.rawValue)")
        }
    }
    
    func peripheralManager(_ peripheral: CBPeripheralManager, willRestoreState dict: [String : Any]) {
        Logger.bluetooth.trace("In \(#function)")
        self.peripheralManager = peripheral
        peripheral.delegate = self
        if bluetoothManager.mode == .peripheral && !peripheralManager.isAdvertising {
            startAdvertising()
        }
    }
    
    func peripheralManager(_ peripheral: CBPeripheralManager, central: CBCentral, didSubscribeTo characteristic: CBCharacteristic) {
        Logger.bluetooth.info("Central '\(central.identifier.uuidString.suffix(BluetoothConstants.UUIDSuffixLength))' didSubscribeTo characteristic '\(BluetoothConstants.getKey(for: characteristic.uuid) ?? "")'")
        stopAdvertising()
        Logger.bluetooth.debug("Central's maximumUpdateValueLength is \(central.maximumUpdateValueLength)") // TODO: delete
        updateValue(for: self.characteristic as CBMutableCharacteristic)
    }
    
    func peripheralManager(_ peripheral: CBPeripheralManager, central: CBCentral, didUnsubscribeFrom characteristic: CBCharacteristic) {
        Logger.bluetooth.info("Central '\(central.identifier.uuidString.suffix(BluetoothConstants.UUIDSuffixLength))' didUnsubscribeFrom characteristic '\(BluetoothConstants.getKey(for: characteristic.uuid) ?? "")'")
        if bluetoothManager.mode == .peripheral && !peripheralManager.isAdvertising {
            startAdvertising()
        }
    }
    
    func peripheralManagerIsReady(toUpdateSubscribers peripheral: CBPeripheralManager) { // TODO: needed? (How) should we update all characteristics?
        Logger.bluetooth.notice("\(#function):toUpdateSubscribers")
        updateValue(for: self.characteristic as CBMutableCharacteristic)
    }
    
    func peripheralManagerDidStartAdvertising(_ peripheral: CBPeripheralManager, error: (any Error)?) {
        if (error != nil) {
            Logger.bluetooth.fault("Peripheral did not start advertising: \(error!.localizedDescription)")
        } else {
            Logger.bluetooth.notice("Peripheral started advertising")
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
