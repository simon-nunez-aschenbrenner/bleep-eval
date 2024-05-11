//
//  CentralManager.swift
//  bleep-eval
//
//  Created by Simon Núñez Aschenbrenner on 07.05.24.
//

import Foundation
import CoreBluetooth
import OSLog

class CentralManagerDelegate: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate, ObservableObject {
        
    unowned var bluetoothManager: BluetoothManager!
    internal var centralManager: CBCentralManager!
    internal var peripheral: CBPeripheral? // TODO: list
    
    internal var service: CBMutableService! // TODO: list
    internal var characteristic: CBMutableCharacteristic! // TODO: list
    @Published internal var value: String? // TODO: queue for each characteristic?
    
    init(bluetoothManager: BluetoothManager, serviceUUID: CBUUID!, characteristicUUID: CBUUID!) {
        super.init()
        self.bluetoothManager = bluetoothManager
        self.centralManager = CBCentralManager(delegate: self, queue: nil, options: [CBCentralManagerOptionRestoreIdentifierKey: "com.simon.bleep-eval.central", CBCentralManagerOptionShowPowerAlertKey: true])
        service = CBMutableService(type: serviceUUID, primary: true)
        characteristic = CBMutableCharacteristic(type: characteristicUUID, properties: [.indicate], value: nil, permissions: [.readable])
        service.characteristics = [characteristic]

        Logger.bluetooth.debug("CentralManagerDelegate initialized")
    }
    
    // MARK: public methods
        
    func startScan() {
        Logger.bluetooth.debug("Central attempts to \(#function) for peripherals with service '\(self.service!.uuid.uuidString.suffix(BluetoothConstants.testUUIDSuffixLength))'")
        centralManager.scanForPeripherals(withServices: [service!.uuid], options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
    }
    
    func stopScan() {
        Logger.bluetooth.debug("Central attempts to \(#function)")
        if centralManager.isScanning {
            centralManager.stopScan()
            // TODO: Can we verify advertising has stopped?
            // !centralManager.isScanning ? Logger.bluetooth.info("Central stopped scanning") : Logger.bluetooth.error("Central did not stop scanning")
        } else {
            Logger.bluetooth.debug("Central was not scanning")
        }
    }
    
    // MARK: delegate methods
    
    internal func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            Logger.bluetooth.info("\(#function) to 'poweredOn'")
            if bluetoothManager.mode == .central && !centralManager.isScanning {
                startScan()
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
    
    internal func centralManager(_ central: CBCentralManager, willRestoreState dict: [String : Any]) {
        self.centralManager = central
        central.delegate = self
        Logger.bluetooth.debug("In \(#function):willRestoreState")
        if bluetoothManager.mode == .central && !self.centralManager.isScanning {
            startScan()
        }
    }
    
    internal func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        Logger.bluetooth.info("Central didDiscover peripheral '\(peripheral.identifier.uuidString.suffix(BluetoothConstants.testUUIDSuffixLength))' (RSSI: \(RSSI.intValue)) and attempts to connect to it")
        self.peripheral = peripheral
        peripheral.delegate = self
        centralManager.stopScan()
        centralManager.connect(peripheral, options: nil)
    }
    
    internal func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        assert(peripheral == self.peripheral)
        var serviceUUIDs: [CBUUID]? = nil
        (self.service != nil) ? serviceUUIDs = [self.service!.uuid] : ()
        Logger.bluetooth.info("Central connected to peripheral '\(peripheral.identifier.uuidString.suffix(BluetoothConstants.testUUIDSuffixLength))' and attempts to discoverServices including '\(serviceUUIDs?[0].uuidString.suffix(BluetoothConstants.testUUIDSuffixLength) ?? "")'") // TODO: list all services
        peripheral.discoverServices(serviceUUIDs)
    }
    
    internal func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if (error != nil) { // TODO: handle
            Logger.bluetooth.fault("Central did not discoverServices on peripheral '\(peripheral.identifier.uuidString.suffix(BluetoothConstants.testUUIDSuffixLength))': \(error!.localizedDescription)")
        } else {
            guard let discoveredServices = peripheral.services else { // TODO: handle
                Logger.bluetooth.fault("The services property of peripheral '\(peripheral.identifier.uuidString.suffix(BluetoothConstants.testUUIDSuffixLength))' is nil")
                return
            }
            // TODO: necessary?
            Logger.bluetooth.info("Central didDiscoverServices on peripheral '\(peripheral.identifier.uuidString.suffix(BluetoothConstants.testUUIDSuffixLength))' and attempts to find matching services")
            for service in discoveredServices {
                Logger.bluetooth.debug("Checking service '\(service.uuid.uuidString.suffix(BluetoothConstants.testUUIDSuffixLength))'")
                if (service.uuid.uuidString == self.service?.uuid.uuidString) {
                    var characteristicUUIDs: [CBUUID]? = nil
                    (self.characteristic != nil) ? characteristicUUIDs = [self.characteristic!.uuid] : ()
                    Logger.bluetooth.debug("'\(service.uuid.uuidString.suffix(BluetoothConstants.testUUIDSuffixLength))' is the service we're looking for on peripheral '\(peripheral.identifier.uuidString.suffix(BluetoothConstants.testUUIDSuffixLength))', attempting to discoverCharacteristics including '\(characteristicUUIDs?[0].uuidString.suffix(BluetoothConstants.testUUIDSuffixLength) ?? "")'")
                    peripheral.discoverCharacteristics(characteristicUUIDs, for: service)
                    return
                }
            }
            // TODO: handle?
            Logger.bluetooth.error("Central did not find any matching services on peripheral '\(peripheral.identifier.uuidString.suffix(BluetoothConstants.testUUIDSuffixLength))'")
        }
    }
    
    internal func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        if (error != nil) { // TODO: handle
            Logger.bluetooth.fault("Central did not discoverCharacteristicsFor service '\(service.uuid.uuidString.suffix(BluetoothConstants.testUUIDSuffixLength))' on peripheral '\(peripheral.identifier.uuidString.suffix(BluetoothConstants.testUUIDSuffixLength))': \(error!.localizedDescription)")
        } else {
            guard let discoveredCharacteristics = service.characteristics else { // TODO: handle
                Logger.bluetooth.fault("The characteristics property of service '\(service.uuid.uuidString.suffix(BluetoothConstants.testUUIDSuffixLength))' on peripheral '\(peripheral.identifier.uuidString.suffix(BluetoothConstants.testUUIDSuffixLength)) is nil")
                return
            }
            // TODO: necessary?
            Logger.bluetooth.info("Central didDiscoverCharacteristicsFor service '\(service.uuid.uuidString.suffix(BluetoothConstants.testUUIDSuffixLength))' on peripheral '\(peripheral.identifier.uuidString.suffix(BluetoothConstants.testUUIDSuffixLength)) and attempts to find matching characteristics")
            for characteristic in discoveredCharacteristics {
                Logger.bluetooth.debug("Checking characteristic '\(characteristic.uuid.uuidString.suffix(BluetoothConstants.testUUIDSuffixLength))'")
                if (characteristic.uuid.uuidString == self.characteristic?.uuid.uuidString) {
                    Logger.bluetooth.debug("'\(characteristic.uuid.uuidString.suffix(BluetoothConstants.testUUIDSuffixLength))' is the characteristic we're looking for in '\(service.uuid.uuidString.suffix(BluetoothConstants.testUUIDSuffixLength))' on peripheral '\(peripheral.identifier.uuidString.suffix(BluetoothConstants.testUUIDSuffixLength)), attempting to setNotifyValue to true")
                    peripheral.setNotifyValue(true, for: characteristic)
                    return
                }
            }
            // TODO: handle?
            Logger.bluetooth.error("Central did not find any matching characteristics in '\(service.uuid.uuidString.suffix(BluetoothConstants.testUUIDSuffixLength))' on peripheral '\(peripheral.identifier.uuidString.suffix(BluetoothConstants.testUUIDSuffixLength))'")
        }
    }
    
    internal func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        if (error != nil) { // TODO: handle
            Logger.bluetooth.fault("Central did not receive UpdateValueFor characteristic '\(characteristic.uuid.uuidString.suffix(BluetoothConstants.testUUIDSuffixLength))' on peripheral '\(peripheral.identifier.uuidString.suffix(BluetoothConstants.testUUIDSuffixLength))': \(error!.localizedDescription)")
        } else {
            guard let data = characteristic.value else { // TODO: handle
                Logger.bluetooth.fault("The value property of characteristic '\(characteristic.uuid.uuidString.suffix(BluetoothConstants.testUUIDSuffixLength))' on peripheral '\(peripheral.identifier.uuidString.suffix(BluetoothConstants.testUUIDSuffixLength)) is nil")
                return
            }
            self.value = String(data: data, encoding: .utf8)
            Logger.bluetooth.info("Central received UpdateValueFor characteristic '\(characteristic.uuid.uuidString.suffix(BluetoothConstants.testUUIDSuffixLength))' on peripheral '\(peripheral.identifier.uuidString.suffix(BluetoothConstants.testUUIDSuffixLength)): \(self.value ?? "")")
        }
    }
    
    internal func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: (any Error)?) {
        if (error != nil) { // TODO: handle
            Logger.bluetooth.fault("Central did not UpdateNotificationStateFor characteristic '\(characteristic.uuid.uuidString.suffix(BluetoothConstants.testUUIDSuffixLength))' on peripheral '\(peripheral.identifier.uuidString.suffix(BluetoothConstants.testUUIDSuffixLength))': \(error!.localizedDescription)")
        } else {
            Logger.bluetooth.info("Central didUpdateNotificationStateFor characteristic '\(characteristic.uuid.uuidString.suffix(BluetoothConstants.testUUIDSuffixLength))' on peripheral '\(peripheral.identifier.uuidString.suffix(BluetoothConstants.testUUIDSuffixLength))'")
        }
    }
}
