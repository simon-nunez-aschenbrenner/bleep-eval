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

class CentralManagerDelegate: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate {
        
    unowned var bluetoothManager: BluetoothManager!
    private(set) var centralManager: CBCentralManager!
    private(set) var peripheral: CBPeripheral? // TODO: Needs to be a list
    var testMessage: String? // TODO: Needs to be a queue
    
    init(bluetoothManager: BluetoothManager) {
        super.init()
        self.bluetoothManager = bluetoothManager
        self.centralManager = CBCentralManager(delegate: self, queue: nil, options: [CBCentralManagerOptionRestoreIdentifierKey: "com.simon.bleep-eval.central", CBCentralManagerOptionShowPowerAlertKey: true])
        logger.debug("CentralManagerDelegate initialized")
    }
    
    // TODO: prepareScan
    
    func startScan() {
        centralManager.scanForPeripherals(withServices: [bluetoothManager.serviceUUID], options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
        logger.info("Central starts scanning for peripherals with testService")
    }
    
    func stopScan() {
        logger.debug("Attempting to \(#function)")
        if centralManager.isScanning {
            centralManager.stopScan()
            logger.info("Central stops scanning for peripherals with testService")
        } else {
            logger.debug("Central was not scanning")
        }
    }
    
    internal func centralManagerDidUpdateState(_ central: CBCentralManager) {
        
        switch central.state {
        case .poweredOn:
            logger.info("\(#function): poweredOn")
            if bluetoothManager.mode == .central && !self.centralManager.isScanning {
                startScan()
            }
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
    
    internal func centralManager(_ central: CBCentralManager, willRestoreState dict: [String : Any]) {
        self.centralManager = central
        central.delegate = self
        logger.debug("In centralManager:willRestoreState()")
        if bluetoothManager.mode == .central && !self.centralManager.isScanning {
            startScan()
        }
    }
    
    internal func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        logger.info("Discovered peripheral \(peripheral.identifier) with advertisementData \(advertisementData) and RSSI \(RSSI)")
        self.peripheral = peripheral
        centralManager.stopScan()
        centralManager.connect(peripheral, options: nil)
    }
    
    internal func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        logger.info("Connected to peripheral \(peripheral.identifier)")
        assert(peripheral == self.peripheral)
        peripheral.delegate = self
        peripheral.discoverServices([bluetoothManager.serviceUUID]) // TODO: replace with discoverIncludedServices?
    }
    
    internal func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if (error != nil) {
            logger.error("didDiscoverServices of peripheral \(peripheral.identifier) returned error \(String(describing: error))")
        }
        guard let services = peripheral.services else {
            logger.error("Peripheral's services property is nil")
            return
        }
        logger.info("Checking discovered services on peripheral \(peripheral.identifier) for matches")
        for service in services {
            if service.uuid.uuidString == bluetoothManager.serviceUUID.uuidString {
                peripheral.discoverCharacteristics([bluetoothManager.characteristicUUID], for: service)
                return
            }
        }
        logger.warning("No matching service found on peripheral \(peripheral.identifier)")
    }
    
    internal func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        if (error != nil) {
            logger.error("didDiscoverCharacteristicsFor service \(service.uuid) returned error \(String(describing: error))")
        }
        guard let characteristics = service.characteristics else {
            logger.error("Services's characteristics property is nil")
            return
        }
        logger.info("Checking discovered characteristics in service \(service.uuid) for matches")
        for characteristic in characteristics {
            if characteristic.uuid.uuidString == bluetoothManager.characteristicUUID.uuidString {
                peripheral.setNotifyValue(true, for: characteristic)
                return
            }
        }
        logger.warning("No matching characteristics found in service \(service.uuid)")
    }
    
    internal func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
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
    
    internal func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: (any Error)?) {
        if (error != nil) {
            logger.error("didUpdateNotificationStateFor characteristic \(characteristic.uuid) returned error \(String(describing: error))")
        }
        logger.info("Peripheral \(peripheral.identifier) didUpdateNotificationStateFor characteristic \(characteristic.uuid)")
    }
}
