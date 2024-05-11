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
        Logger.bluetooth.debug("Central attempts to \(#function) for peripherals with service \(self.service!.uuid.uuidString)")
        centralManager.scanForPeripherals(withServices: [service!.uuid], options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
    }
    
    func stopScan() {
        Logger.bluetooth.debug("Central attempts to \(#function)")
        if centralManager.isScanning {
            centralManager.stopScan()
            !centralManager.isScanning ? Logger.bluetooth.info("Central stopped scanning") : Logger.bluetooth.error("Central did not stop scanning")
        } else {
            Logger.bluetooth.debug("Central was not scanning")
        }
    }
    
    // MARK: delegate methods
    
    internal func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            Logger.bluetooth.info("\(#function): poweredOn")
            if bluetoothManager.mode == .central && !centralManager.isScanning {
                startScan()
            }
        case .unknown: // TODO: handle
            Logger.bluetooth.notice("\(#function): unknown")
        case .resetting: // TODO: handle
            Logger.bluetooth.notice("\(#function): resetting")
        case .unsupported: // TODO: handle
            Logger.bluetooth.error("\(#function): unsupported")
        case .unauthorized: // TODO: handle
            Logger.bluetooth.error("\(#function): unauthorized")
            Logger.bluetooth.notice("CBManager authorization: \(String(describing: CBCentralManager.authorization))") // TODO: handle incl. authorization cases
        case .poweredOff: // TODO: handle
            Logger.bluetooth.error("\(#function): poweredOff")
        @unknown default: // TODO: handle
            Logger.bluetooth.error("\(#function): \(central.state.rawValue) (not implemented)")
        }
    }
    
    internal func centralManager(_ central: CBCentralManager, willRestoreState dict: [String : Any]) {
        self.centralManager = central
        central.delegate = self
        Logger.bluetooth.debug("In centralManager:willRestoreState()")
        if bluetoothManager.mode == .central && !self.centralManager.isScanning {
            startScan()
        }
    }
    
    internal func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        Logger.bluetooth.info("Discovered peripheral \(peripheral.identifier) with advertisementData \(advertisementData) and RSSI \(RSSI), attempting to connect")
        self.peripheral = peripheral
        peripheral.delegate = self
        centralManager.stopScan()
        centralManager.connect(peripheral, options: nil)
    }
    
    internal func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        assert(peripheral == self.peripheral)
        var serviceUUIDs: [CBUUID]? = nil
        (self.service != nil) ? serviceUUIDs = [self.service!.uuid] : ()
        Logger.bluetooth.info("Connected to peripheral \(peripheral.identifier), attempting to discoverServices \(String(describing:serviceUUIDs))")
        peripheral.discoverServices(serviceUUIDs)
    }
    
    internal func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if (error != nil) { // TODO: handle
            Logger.bluetooth.fault("didDiscoverServices of peripheral \(peripheral.identifier) returned error \(String(describing: error))")
        } else {
            guard let discoveredServices = peripheral.services else { // TODO: handle
                Logger.bluetooth.fault("Peripheral's services property is nil")
                return
            }
            // TODO: necessary?
            Logger.bluetooth.info("Central comparing discovered services on peripheral \(peripheral.identifier) with own")
            for service in discoveredServices {
                Logger.bluetooth.debug("Checking service \(service.uuid)")
                if (service.uuid.uuidString == self.service?.uuid.uuidString) {
                    Logger.bluetooth.debug("It's the service we're looking for, attempting to discover its characteristics")
                    var characteristicUUIDs: [CBUUID]? = nil
                    (self.characteristic != nil) ? characteristicUUIDs = [self.characteristic!.uuid] : ()
                    peripheral.discoverCharacteristics(characteristicUUIDs, for: service)
                    return
                }
            }
            // TODO: handle?
            Logger.bluetooth.error("No matching service found on peripheral \(peripheral.identifier)")
        }
    }
    
    internal func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        if (error != nil) { // TODO: handle
            Logger.bluetooth.fault("didDiscoverCharacteristicsFor service \(service.uuid) returned error \(String(describing: error))")
        } else {
            guard let discoveredCharacteristics = service.characteristics else { // TODO: handle
                Logger.bluetooth.fault("Services's characteristics property is nil")
                return
            }
            Logger.bluetooth.info("Central comparing discovered characteristics in service \(service.uuid) with own")
            for characteristic in discoveredCharacteristics {
                Logger.bluetooth.debug("Checking characteristic \(characteristic.uuid)")
                if (characteristic.uuid.uuidString == self.characteristic?.uuid.uuidString) {
                    Logger.bluetooth.debug("It's the characteristic we're looking for, wating for value update")
                    // peripheral.setNotifyValue(true, for: characteristic)
                    // Logger.bluetooth.debug("setNotifyValue to true for characteristic \(characteristic)")
                    return
                }
            }
            // TODO: handle?
            Logger.bluetooth.error("No matching characteristics found in service \(service.uuid)")
        }
    }
    
    internal func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        if (error != nil) { // TODO: handle
            Logger.bluetooth.fault("didUpdateValueFor characteristic \(characteristic.uuid) returned error \(String(describing: error))")
        } else {
            guard let data = characteristic.value else { // TODO: handle
                Logger.bluetooth.fault("Characteristic's value property is nil")
                return
            }
            Logger.bluetooth.info("Central received characteristic's \(characteristic.uuid) updated value: \(data)")
            self.value = String(data: data, encoding: .utf8)
            Logger.bluetooth.debug("Updated CentralManagerDelegate.value: \(String(describing: self.value))")
        }
    }
    
    internal func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: (any Error)?) {
        if (error != nil) { // TODO: handle
            Logger.bluetooth.fault("didUpdateNotificationStateFor characteristic \(characteristic.uuid) returned error \(String(describing: error))")
        } else {
            Logger.bluetooth.info("Peripheral \(peripheral.identifier) didUpdateNotificationStateFor characteristic \(characteristic.uuid)")
        }
    }
}
