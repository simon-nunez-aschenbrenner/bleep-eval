//
//  CentralManager.swift
//  bleep-eval
//
//  Created by Simon Núñez Aschenbrenner on 07.05.24.
//

import Foundation
import CoreBluetooth
import OSLog

@Observable
class CentralManagerDelegate: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate {
        
    unowned var bluetoothManager: BluetoothManager!
    var centralManager: CBCentralManager!
    var peripheral: CBPeripheral? // TODO: list
    
    let autoSubscribe: Bool!
    var shallSubscribe: Bool!
    var shallScan: Bool = false
    var service: CBMutableService!
    var characteristic: CBMutableCharacteristic! // TODO: list
    var value: String! // TODO: queue for each characteristic?
        
    init(bluetoothManager: BluetoothManager!, autoSubscribe: Bool!, serviceUUID: CBUUID!, characteristicUUID: CBUUID!) {
        self.autoSubscribe = autoSubscribe
        super.init()
        self.shallSubscribe = autoSubscribe
        self.bluetoothManager = bluetoothManager
        self.centralManager = CBCentralManager(delegate: self, queue: nil, options: [CBCentralManagerOptionRestoreIdentifierKey: BluetoothConstants.centralIdentifierKey, CBCentralManagerOptionShowPowerAlertKey: true])
        self.service = CBMutableService(type: serviceUUID, primary: true)
        self.characteristic = CBMutableCharacteristic(type: characteristicUUID, properties: [.indicate], value: nil, permissions: [.readable])
        self.service.characteristics = [characteristic]
        self.value = "" // TODO: Better to differentiate between empty and nil string
        Logger.bluetooth.trace("CentralManagerDelegate initialized")
    }
    
    // MARK: public methods
        
    func startScan(andSubscribe: Bool?) {
        shallSubscribe = andSubscribe ?? autoSubscribe
        Logger.bluetooth.debug("Central attempts to \(#function) \(self.shallSubscribe ? "andSubscribe to" : "for") peripherals with service '\(BluetoothConstants.getKey(for: self.service.uuid) ?? "")'")
        centralManager.scanForPeripherals(withServices: [self.service.uuid], options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
    }
    
    func stopScan() {
        Logger.bluetooth.trace("Central attempts to \(#function)")
        centralManager.isScanning ? centralManager.stopScan() : Logger.bluetooth.trace("Central was not scanning")
    }
    
    func subscribe(to peripheral: CBPeripheral) {
        // Skipping service discovery // TODO: delete
        // var serviceUUIDs = [self.service.uuid]
        // Logger.bluetooth.debug("Central attempts to discoverServices on peripheral '\(peripheral.identifier.uuidString.suffix(BluetoothConstants.UUIDSuffixLength))' including '\(BluetoothConstants.getKey(for: serviceUUIDs[0]) ?? "")'") // TODO: list all services
        // peripheral.discoverServices(serviceUUIDs)
        let characteristicUUIDs = [self.characteristic.uuid]
        Logger.bluetooth.debug("Central attempts to discoverCharacteristics on peripheral '\(peripheral.identifier.uuidString.suffix(BluetoothConstants.UUIDSuffixLength))' including '\(BluetoothConstants.getKey(for: characteristicUUIDs[0]) ?? "")'") // TODO: list all chaacteristics
        peripheral.discoverCharacteristics(characteristicUUIDs, for: self.service)
    }
    
    func unsubscribe(peripheral: CBPeripheral, andDisconnect: Bool = false, andStartScan: Bool = false) {
        Logger.bluetooth.debug("Central attempts to \(#function) \(andDisconnect ? "andDisconnect" : "") from peripheral '\(peripheral.identifier.uuidString.suffix(BluetoothConstants.UUIDSuffixLength))'\(andDisconnect ? " andStartScan" : "")")
        peripheral.setNotifyValue(false, for: characteristic)
        shallScan = andStartScan
        andDisconnect ? centralManager.cancelPeripheralConnection(peripheral) : ()
    }
    
    // MARK: delegate methods
    
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            Logger.bluetooth.notice("\(#function) to 'poweredOn'")
            if bluetoothManager.mode == .central && !centralManager.isScanning {
                startScan(andSubscribe: nil)
            }
        // TODO: handle other cases incl. authorization cases
        case .unknown:
            Logger.bluetooth.warning("\(#function) to 'unknown'")
        case .resetting:
            Logger.bluetooth.warning("\(#function) to 'resetting'")
        case .unsupported:
            Logger.bluetooth.error("\(#function) to 'unsupported'")
        case .unauthorized:
            Logger.bluetooth.error("\(#function) to 'unauthorized'")
            Logger.bluetooth.error("CBManager authorization: \(CBPeripheralManager.authorization.rawValue)")
        case .poweredOff:
            Logger.bluetooth.error("\(#function) to 'poweredOff'")
        @unknown default:
            Logger.bluetooth.error("\(#function) to not implemented state: \(central.state.rawValue)")
        }
    }
    
    func centralManager(_ central: CBCentralManager, willRestoreState dict: [String : Any]) {
        Logger.bluetooth.trace("In \(#function)")
        self.centralManager = central
        central.delegate = self
        if bluetoothManager.mode == .central && !self.centralManager.isScanning {
            startScan(andSubscribe: nil)
        }
    }
    
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        Logger.bluetooth.info("Central didDiscover peripheral '\(peripheral.identifier.uuidString.suffix(BluetoothConstants.UUIDSuffixLength))' (RSSI: \(RSSI.intValue)) and attempts to connect to it")
        self.peripheral = peripheral
        peripheral.delegate = self
        centralManager.stopScan()
        centralManager.connect(peripheral, options: nil)
    }
    
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        Logger.bluetooth.notice("Central didConnect to peripheral '\(peripheral.identifier.uuidString.suffix(BluetoothConstants.UUIDSuffixLength))'")
        shallSubscribe ? subscribe(to: peripheral) : ()
    }
    
    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: (any Error)?) { // TODO: handle
        Logger.bluetooth.error("Central didFailToConnect to peripheral '\(peripheral.identifier.uuidString.suffix(BluetoothConstants.UUIDSuffixLength))': '\(error?.localizedDescription ?? "")'")
    }
    
    // Skipping service discovery // TODO: delete
    // func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
    //     if (error != nil) { // TODO: handle
    //         Logger.bluetooth.error("Central did not discoverServices on peripheral '\(peripheral.identifier.uuidString.suffix(BluetoothConstants.UUIDSuffixLength))': '\(error!.localizedDescription)'")
    //     } else {
    //         guard let discoveredService = peripheral.services?[0] else { // TODO: handle
    //             Logger.bluetooth.fault("The services array of peripheral '\(peripheral.identifier.uuidString.suffix(BluetoothConstants.UUIDSuffixLength))' is nil or empty")
    //             return
    //         }
    //         var characteristicUUIDs = [self.characteristic.uuid]
    //         Logger.bluetooth.info("Central didDiscoverServices on peripheral '\(peripheral.identifier.uuidString.suffix(BluetoothConstants.UUIDSuffixLength))', including service '\(BluetoothConstants.getKey(for: discoveredService.uuid) ?? "")', and attempts to discoverCharacteristics including '\(BluetoothConstants.getKey(for: characteristicUUIDs[0]) ?? "")' on it")
    //         peripheral.discoverCharacteristics(characteristicUUIDs, for: discoveredService)
    //     }
    // }
    
    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        if (error != nil) { // TODO: handle
            Logger.bluetooth.error("Central did not discoverCharacteristicsFor service '\(BluetoothConstants.getKey(for: service.uuid) ?? "")' on peripheral '\(peripheral.identifier.uuidString.suffix(BluetoothConstants.UUIDSuffixLength))': '\(error!.localizedDescription)'")
        } else {
            guard let discoveredCharacteristic = service.characteristics?[0] else { // TODO: handle
                Logger.bluetooth.fault("The characteristics array of service '\(BluetoothConstants.getKey(for: service.uuid) ?? "")' on peripheral '\(peripheral.identifier.uuidString.suffix(BluetoothConstants.UUIDSuffixLength)) is nil or empty")
                return
            }
            Logger.bluetooth.debug("Central didDiscoverCharacteristicsFor service '\(BluetoothConstants.getKey(for: service.uuid) ?? "")' on peripheral '\(peripheral.identifier.uuidString.suffix(BluetoothConstants.UUIDSuffixLength))', including characteristic '\(BluetoothConstants.getKey(for: discoveredCharacteristic.uuid) ?? "")', attempting to setNotifyValue for it to true")
            peripheral.setNotifyValue(true, for: discoveredCharacteristic) // TODO: Rather our own?
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        if (error != nil) { // TODO: handle
            Logger.bluetooth.fault("Central did not receive UpdateValueFor characteristic '\(BluetoothConstants.getKey(for: characteristic.uuid) ?? "")' on peripheral '\(peripheral.identifier.uuidString.suffix(BluetoothConstants.UUIDSuffixLength))': '\(error!.localizedDescription)'")
        } else {
            guard let data = characteristic.value else { // TODO: handle
                Logger.bluetooth.fault("The value property of characteristic '\(BluetoothConstants.getKey(for: characteristic.uuid) ?? "")' on peripheral '\(peripheral.identifier.uuidString.suffix(BluetoothConstants.UUIDSuffixLength)) is nil")
                return
            }
            self.value = String(data: data, encoding: .utf8)
            Logger.bluetooth.notice("Central did receive UpdateValueFor characteristic \(BluetoothConstants.getKey(for: characteristic.uuid) ?? "") on peripheral '\(peripheral.identifier.uuidString.suffix(BluetoothConstants.UUIDSuffixLength)): \(self.value ?? "")")
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: (any Error)?) {
        if (error != nil) { // TODO: handle
            Logger.bluetooth.fault("Central did not UpdateNotificationStateFor characteristic '\(BluetoothConstants.getKey(for: characteristic.uuid) ?? "")' on peripheral '\(peripheral.identifier.uuidString.suffix(BluetoothConstants.UUIDSuffixLength))': '\(error!.localizedDescription)'")
        } else {
            Logger.bluetooth.notice("Central didUpdateNotificationStateFor characteristic '\(BluetoothConstants.getKey(for: characteristic.uuid) ?? "")' on peripheral '\(peripheral.identifier.uuidString.suffix(BluetoothConstants.UUIDSuffixLength))' to \(characteristic.isNotifying)")
        }
    }
    
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, timestamp: CFAbsoluteTime, isReconnecting: Bool, error: (any Error)?) {
        if (error != nil) { // TODO: handle
            Logger.bluetooth.fault("Central did not DisconnectPeripheral '\(peripheral.identifier.uuidString.suffix(BluetoothConstants.UUIDSuffixLength))': '\(error!.localizedDescription)'")
        } else {
            Logger.bluetooth.notice("Central didDisconnectPeripheral '\(peripheral.identifier.uuidString.suffix(BluetoothConstants.UUIDSuffixLength))'")
            if isReconnecting {
                Logger.bluetooth.debug("Central isReconnecting to peripheral '\(peripheral.identifier.uuidString.suffix(BluetoothConstants.UUIDSuffixLength))'")
            } else if shallScan {
                !centralManager.isScanning ? startScan(andSubscribe: nil) : ()
                shallScan = false
            }
        }
    }
}
