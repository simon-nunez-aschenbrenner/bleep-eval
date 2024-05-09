//
//  CentralManager.swift
//  bleep-eval
//
//  Created by Simon Núñez Aschenbrenner on 07.05.24.
//

import Foundation
import CoreBluetooth
import Logging

private let logger = Logger(label: "com.simon.bleep-eval.logger.central")

class CentralManagerDelegate: NSObject, ObservableObject, CBCentralManagerDelegate {
        
    var centralManager: CBCentralManager!
    var peripheral: CBPeripheral? // TODO: Needs to be a list
    var peripheralDelegate: PeripheralDelegate! // TODO: Needs one for each peripheral
    
    override init() {
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: nil, options: [CBCentralManagerOptionRestoreIdentifierKey: "com.simon.bleep-eval.central", CBCentralManagerOptionShowPowerAlertKey: true])
        peripheralDelegate = PeripheralDelegate()
        logger.debug("CentralManagerDelegate initialized")
    }
    
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        
        switch central.state {
        case .poweredOn:
            logger.info("\(#function): poweredOn")
            // startScan()
        case .unknown: // TODO: handle
            logger.notice("\(#function): unknown")
        case .resetting: // TODO: handle
            logger.notice("\(#function): resetting")
        case .unsupported: // TODO: handle
            logger.error("\(#function): unsupported")
        case .unauthorized: // TODO: handle
            logger.error("\(#function): unauthorized")
            logger.notice("CBManager authorization: \(CBManager.authorization)") // TODO: handle authorization cases
        case .poweredOff: // TODO: handle
            logger.error("\(#function): poweredOff")
        @unknown default: // TODO: handle
            logger.error("\(#function): \(central.state) (not implemented)")
        }
    }
    
    func startScan() {
        centralManager.scanForPeripherals(withServices: [PeripheralManagerDelegate.testServiceUUID], options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
        logger.info("Scanning for peripherals with testService")
    }
    
    func centralManager(_ central: CBCentralManager, willRestoreState dict: [String : Any]) {
        central.delegate = self
        self.centralManager = central
        
        if !self.centralManager.isScanning {
             startScan()
        }
    }
    
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        logger.info("Discovered peripheral \(peripheral.identifier) with advertisementData \(advertisementData) and RSSI \(RSSI)")
        self.peripheral = peripheral
        self.peripheral?.delegate = peripheralDelegate
        if (self.peripheral == nil || self.peripheralDelegate == nil) {
            logger.critical("CBPeripheral instance and/or its delegate is nil")
        }
        centralManager.stopScan()
        centralManager.connect(peripheral, options: nil)
    }
    
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        logger.info("Connected to peripheral \(peripheral.identifier)")
        peripheral.discoverServices([PeripheralManagerDelegate.testServiceUUID]) // TODO: replace with discoverIncludedServices?
    }
}

class PeripheralDelegate: NSObject, ObservableObject, CBPeripheralDelegate {
    
    @Published var testMessage: String?
    
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if (error != nil) {
            logger.error("didDiscoverServices of peripheral \(peripheral.identifier) returned error \(String(describing: error))")
        }
        guard let services = peripheral.services else {
            logger.error("Peripheral's services property is nil")
            return
        }
        logger.info("Checking discovered services on peripheral \(peripheral.identifier) for matches")
        for service in services {
            if service.uuid == PeripheralManagerDelegate.testServiceUUID {
                peripheral.discoverCharacteristics([PeripheralManagerDelegate.testCharacteristicUUID], for: service)
                return
            }
        }
        logger.warning("No matching service found on peripheral \(peripheral.identifier)")
    }
    
    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        if (error != nil) {
            logger.error("didDiscoverCharacteristicsFor service \(service.uuid) returned error \(String(describing: error))")
        }
        guard let characteristics = service.characteristics else {
            logger.error("Services's characteristics property is nil")
            return
        }
        logger.info("Checking discovered characteristics in service \(service.uuid) for matches")
        for characteristic in characteristics {
            if characteristic.uuid == PeripheralManagerDelegate.testCharacteristicUUID {
                // peripheral.readValue(for: characteristic)
                peripheral.setNotifyValue(true, for: characteristic)
                return
            }
        }
        logger.warning("No matching characteristics found in service \(service.uuid)")
    }
    
    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        if (error != nil) {
            logger.error("didUpdateValueFor characteristic \(characteristic.uuid) returned error \(String(describing: error))")
        }
        if let data = characteristic.value {
            logger.info("didUpdateValueFor characteristic \(characteristic.uuid): \(data)")
            self.testMessage = String(data: data, encoding: .utf8)
            logger.debug("Updated testMessage: \(String(describing: self.testMessage))")
        } else {
            logger.error("Unable to update value of characteristic \(characteristic.uuid)")
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: (any Error)?) {
        if (error != nil) {
            logger.error("didUpdateNotificationStateFor characteristic \(characteristic.uuid) returned error \(String(describing: error))")
        }
        logger.info("Peripheral \(peripheral.identifier) didUpdateNotificationStateFor characteristic \(characteristic.uuid)")
    }
}
