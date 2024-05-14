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
    var shallScan: Bool?
    var service: CBMutableService! // TODO: list
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
        Logger.bluetooth.debug("CentralManagerDelegate initialized")
    }
    
    // MARK: public methods
        
    func startScan(_ andSubscribe: Bool?) {
        shallSubscribe = andSubscribe ?? autoSubscribe
        Logger.bluetooth.debug("Central attempts to \(#function) for \(self.shallSubscribe ? "andSubscribe to" : "") peripherals with service '\(BluetoothConstants.getKey(for: self.service.uuid) ?? "")'")
        centralManager.scanForPeripherals(withServices: [service.uuid], options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
    }
    
    func subscribe(_ peripheral: CBPeripheral) {
        var serviceUUIDs: [CBUUID]? = nil
        (self.service != nil) ? serviceUUIDs = [self.service!.uuid] : ()
        Logger.bluetooth.info("Central attempts to discoverServices on peripheral '\(peripheral.identifier.uuidString.suffix(BluetoothConstants.UUIDSuffixLength))' including '\(BluetoothConstants.getKey(for: serviceUUIDs?[0]) ?? "")'") // TODO: list all services
        peripheral.discoverServices(serviceUUIDs)
    }
    
    func unsubscribe(_ peripheral: CBPeripheral, characteristic: CBCharacteristic) {
        Logger.bluetooth.info("Central attempts to unsubscribe from characteristic '\(BluetoothConstants.getKey(for: characteristic.uuid) ?? "")' in service '\(BluetoothConstants.getKey(for: characteristic.service?.uuid) ?? "")' on peripheral '\(peripheral.identifier.uuidString.suffix(BluetoothConstants.UUIDSuffixLength))'")
        peripheral.setNotifyValue(false, for: characteristic)
        // We're unsubscribed
    }
    
    func disconnect(peripheral: CBPeripheral, andStartScan: Bool = false) {
        peripheral.setNotifyValue(false, for: characteristic) // TODO: Needed?
        centralManager.cancelPeripheralConnection(peripheral)
        shallScan = andStartScan
    }
    
    func stopScan() {
        Logger.bluetooth.debug("Central attempts to \(#function)")
        if centralManager.isScanning {
            centralManager.stopScan()
            // TODO: Can we verify scanning has stopped?
            // !centralManager.isScanning ? Logger.bluetooth.info("Central stopped scanning") : Logger.bluetooth.error("Central did not stop scanning")
        } else {
            Logger.bluetooth.debug("Central was not scanning")
        }
    }
    
    // MARK: delegate methods
    
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            Logger.bluetooth.info("\(#function) to 'poweredOn'")
            if bluetoothManager.mode == .central && !centralManager.isScanning {
                startScan(nil)
            }
        case .unknown: // TODO: handle
            Logger.bluetooth.notice("\(#function) to 'unknown'")
        case .resetting: // TODO: handle
            Logger.bluetooth.notice("\(#function) to 'resetting'")
        case .unsupported: // TODO: handle
            Logger.bluetooth.error("\(#function) to 'unsupported'")
        case .unauthorized: // TODO: handle
            Logger.bluetooth.error("\(#function) to 'unauthorized'")
            Logger.bluetooth.notice("CBManager authorization: \(CBPeripheralManager.authorization.rawValue)") // TODO: handle incl. authorization cases
        case .poweredOff: // TODO: handle
            Logger.bluetooth.error("\(#function) to 'poweredOff'")
        @unknown default: // TODO: handle
            Logger.bluetooth.error("\(#function) to not implemented state: \(central.state.rawValue)")
        }
    }
    
    func centralManager(_ central: CBCentralManager, willRestoreState dict: [String : Any]) {
        self.centralManager = central
        central.delegate = self
        Logger.bluetooth.debug("In \(#function):willRestoreState")
        if bluetoothManager.mode == .central && !self.centralManager.isScanning {
            startScan(nil)
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
        Logger.bluetooth.info("Central connected to peripheral '\(peripheral.identifier.uuidString.suffix(BluetoothConstants.UUIDSuffixLength))'")
        if shallSubscribe {
            subscribe(peripheral)
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if (error != nil) { // TODO: handle
            Logger.bluetooth.fault("Central did not discoverServices on peripheral '\(peripheral.identifier.uuidString.suffix(BluetoothConstants.UUIDSuffixLength))': \(error!.localizedDescription)")
        } else {
            guard let discoveredServices = peripheral.services else { // TODO: handle
                Logger.bluetooth.fault("The services property of peripheral '\(peripheral.identifier.uuidString.suffix(BluetoothConstants.UUIDSuffixLength))' is nil")
                return
            }
//            TODO: The commented lines may be redundant
//            Logger.bluetooth.info("Central didDiscoverServices on peripheral '\(peripheral.identifier.uuidString.suffix(BluetoothConstants.testUUIDSuffixLength))' and attempts to find matching services")
//            for service in discoveredServices {
//                Logger.bluetooth.debug("Checking service '\(service.uuid.uuidString.suffix(BluetoothConstants.testUUIDSuffixLength))'")
//                if (service.uuid.uuidString == self.service?.uuid.uuidString) {
//                    var characteristicUUIDs: [CBUUID]? = nil
//                    (self.characteristic != nil) ? characteristicUUIDs = [self.characteristic!.uuid] : ()
//                    Logger.bluetooth.debug("'\(service.uuid.uuidString.suffix(BluetoothConstants.testUUIDSuffixLength))' is the service we're looking for on peripheral '\(peripheral.identifier.uuidString.suffix(BluetoothConstants.testUUIDSuffixLength))', attempting to discoverCharacteristics including '\(characteristicUUIDs?[0].uuidString.suffix(BluetoothConstants.testUUIDSuffixLength) ?? "")'")
//                    peripheral.discoverCharacteristics(characteristicUUIDs, for: service)
//                    return
//                }
//            }
//            Logger.bluetooth.error("Central did not find any matching services on peripheral '\(peripheral.identifier.uuidString.suffix(BluetoothConstants.testUUIDSuffixLength))'") // TODO: handle?
            var characteristicUUIDs: [CBUUID]? = nil
            (self.characteristic != nil) ? characteristicUUIDs = [self.characteristic!.uuid] : ()
            Logger.bluetooth.info("Central didDiscoverServices on peripheral '\(peripheral.identifier.uuidString.suffix(BluetoothConstants.UUIDSuffixLength))', including service '\(BluetoothConstants.getKey(for: peripheral.services![0].uuid) ?? "")', and attempts to discoverCharacteristics including '\(BluetoothConstants.getKey(for: characteristicUUIDs?[0]) ?? "")'")
            peripheral.discoverCharacteristics(characteristicUUIDs, for: discoveredServices[0])
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        if (error != nil) { // TODO: handle
            Logger.bluetooth.fault("Central did not discoverCharacteristicsFor service '\(BluetoothConstants.getKey(for: service.uuid) ?? "")' on peripheral '\(peripheral.identifier.uuidString.suffix(BluetoothConstants.UUIDSuffixLength))': \(error!.localizedDescription)")
        } else {
            guard let discoveredCharacteristics = service.characteristics else { // TODO: handle
                Logger.bluetooth.fault("The characteristics property of service '\(BluetoothConstants.getKey(for: service.uuid) ?? "")' on peripheral '\(peripheral.identifier.uuidString.suffix(BluetoothConstants.UUIDSuffixLength)) is nil")
                return
            }
//            TODO: The commented lines may be redundant
//            Logger.bluetooth.info("Central didDiscoverCharacteristicsFor service '\(service.uuid.uuidString.suffix(BluetoothConstants.testUUIDSuffixLength))' on peripheral '\(peripheral.identifier.uuidString.suffix(BluetoothConstants.testUUIDSuffixLength)) and attempts to find matching characteristics")
//            for characteristic in discoveredCharacteristics {
//                Logger.bluetooth.debug("Checking characteristic '\(characteristic.uuid.uuidString.suffix(BluetoothConstants.testUUIDSuffixLength))'")
//                if (characteristic.uuid.uuidString == self.characteristic?.uuid.uuidString) {
//                    Logger.bluetooth.debug("'\(characteristic.uuid.uuidString.suffix(BluetoothConstants.testUUIDSuffixLength))' is the characteristic we're looking for in '\(service.uuid.uuidString.suffix(BluetoothConstants.testUUIDSuffixLength))' on peripheral '\(peripheral.identifier.uuidString.suffix(BluetoothConstants.testUUIDSuffixLength)), attempting to setNotifyValue to true")
//                    peripheral.setNotifyValue(true, for: characteristic)
//                    return
//                }
//            }
//            Logger.bluetooth.error("Central did not find any matching characteristics in '\(service.uuid.uuidString.suffix(BluetoothConstants.testUUIDSuffixLength))' on peripheral '\(peripheral.identifier.uuidString.suffix(BluetoothConstants.testUUIDSuffixLength))'") // TODO: handle?
            Logger.bluetooth.debug("Central didDiscoverCharacteristicsFor service '\(BluetoothConstants.getKey(for: service.uuid) ?? "")' on peripheral '\(peripheral.identifier.uuidString.suffix(BluetoothConstants.UUIDSuffixLength))', including characteristic '\(BluetoothConstants.getKey(for: discoveredCharacteristics[0].uuid) ?? "")', attempting to setNotifyValue for it to true")
            peripheral.setNotifyValue(true, for: discoveredCharacteristics[0]) // TODO: Rather our own?
            // We're subscribed
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        if (error != nil) { // TODO: handle
            Logger.bluetooth.fault("Central did not receive UpdateValueFor characteristic '\(BluetoothConstants.getKey(for: characteristic.uuid) ?? "")' in service '\(BluetoothConstants.getKey(for: characteristic.service?.uuid) ?? "")' on peripheral '\(peripheral.identifier.uuidString.suffix(BluetoothConstants.UUIDSuffixLength))': \(error!.localizedDescription)")
        } else {
            guard let data = characteristic.value else { // TODO: handle
                Logger.bluetooth.fault("The value property of characteristic '\(BluetoothConstants.getKey(for: characteristic.uuid) ?? "")' on peripheral '\(peripheral.identifier.uuidString.suffix(BluetoothConstants.UUIDSuffixLength)) is nil")
                return
            }
            self.value = String(data: data, encoding: .utf8)
            Logger.bluetooth.info("Central received UpdateValueFor characteristic \(BluetoothConstants.getKey(for: characteristic.uuid) ?? "") on peripheral '\(peripheral.identifier.uuidString.suffix(BluetoothConstants.UUIDSuffixLength)): \(self.value ?? "")")
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: (any Error)?) {
        if (error != nil) { // TODO: handle
            Logger.bluetooth.fault("Central did not UpdateNotificationStateFor characteristic '\(BluetoothConstants.getKey(for: characteristic.uuid) ?? "")' on peripheral '\(peripheral.identifier.uuidString.suffix(BluetoothConstants.UUIDSuffixLength))': \(error!.localizedDescription)")
        } else {
            Logger.bluetooth.info("Central didUpdateNotificationStateFor characteristic '\(BluetoothConstants.getKey(for: characteristic.uuid) ?? "")' on peripheral '\(peripheral.identifier.uuidString.suffix(BluetoothConstants.UUIDSuffixLength))' to \(characteristic.isNotifying)")
        }
    }
    
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, timestamp: CFAbsoluteTime, isReconnecting: Bool, error: (any Error)?) {
        if (error != nil) { // TODO: handle
            Logger.bluetooth.fault("Central did not DisconnectPeripheral '\(peripheral.identifier.uuidString.suffix(BluetoothConstants.UUIDSuffixLength))': \(error!.localizedDescription)")
        } else {
            Logger.bluetooth.info("Central didDisconnectPeripheral '\(peripheral.identifier.uuidString.suffix(BluetoothConstants.UUIDSuffixLength))'")
            if isReconnecting {
                Logger.bluetooth.info("Central isReconnecting peripheral '\(peripheral.identifier.uuidString.suffix(BluetoothConstants.UUIDSuffixLength))'")
            } else if shallScan ?? false {
                !centralManager.isScanning ? startScan(nil) : ()
            }
        }
    }
}
