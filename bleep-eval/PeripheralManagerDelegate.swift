//
//  PeripheralManager.swift
//  bleep-eval
//
//  Created by Simon Núñez Aschenbrenner on 04.05.24.
//

import Foundation
import CoreBluetooth
import Logging

private let logger = Logger(label: "com.simon.bleep-eval.logger.peripheral")

class PeripheralManagerDelegate: NSObject, ObservableObject, CBPeripheralManagerDelegate {
    
    static let testServiceUUID = CBUUID(string: "d50cfc1b-9fc7-4f07-9fa0-fe7cd33f3e92")
    static let testCharacteristicUUID = CBUUID(string: "f03a20be-b7e9-44cf-b156-685fe9762504")
    static let testAdvertisementKey: String = "bleep"
            
    var peripheralManager: CBPeripheralManager!
    var central: CBCentral?
    
    var testService: CBMutableService!
    var testCharacteristic: CBMutableCharacteristic!
    var testMessage: String! {
        didSet {
            updateTestMessage(for: testCharacteristic, onSubscribedCentrals: nil)
        }
    }
    
    override init() {
        super.init()
        peripheralManager = CBPeripheralManager(delegate: self, queue: nil, options: [CBPeripheralManagerOptionRestoreIdentifierKey: "com.simon.bleep-eval.peripheral", CBPeripheralManagerOptionShowPowerAlertKey: true])
        testService = CBMutableService(type: PeripheralManagerDelegate.testServiceUUID, primary: true)
        testCharacteristic = CBMutableCharacteristic(type: PeripheralManagerDelegate.testCharacteristicUUID, properties: [.indicate], value: nil, permissions: [.readable])
        testService.characteristics = [testCharacteristic]
        peripheralManager.add(testService)
        testMessage = "default"
        logger.debug("PeripheralManagerDelegate initialized")
    }
    
    func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        
        switch peripheral.state {
        case .poweredOn:
            logger.info("\(#function): poweredOn")
            // startAdvertising()
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
            logger.error("\(#function): \(peripheral.state) (not implemented)")
        }
    }
    
    func startAdvertising() {
        peripheralManager.startAdvertising([CBAdvertisementDataServiceUUIDsKey: [PeripheralManagerDelegate.testServiceUUID], CBAdvertisementDataLocalNameKey: PeripheralManagerDelegate.testAdvertisementKey])
        logger.info("Advertising testService to centrals")
    }
    
    func peripheralManager(_ peripheral: CBPeripheralManager, willRestoreState dict: [String : Any]) {
        peripheral.delegate = self
        self.peripheralManager = peripheral
        
        if !self.peripheralManager.isAdvertising {
            startAdvertising()
        }
    }
    
    func updateTestMessage(for characteristic: CBMutableCharacteristic, onSubscribedCentrals centrals: [CBCentral]?) {
        let data: Data! = testMessage.data(using: .utf8)
        self.peripheralManager.updateValue(data, for: characteristic, onSubscribedCentrals: centrals)
        logger.info("Updating value of characteristic \(characteristic.uuid) to: \(String(describing: self.testMessage))")
    }
    
    func peripheralManager(_ peripheral: CBPeripheralManager, central: CBCentral, didSubscribeTo characteristic: CBCharacteristic) {
        logger.info("Central \(central.identifier) subscribed to characteristic \(characteristic.uuid)")
        updateTestMessage(for: characteristic as! CBMutableCharacteristic, onSubscribedCentrals: [central])
    }
    
    func peripheralManager(_ peripheral: CBPeripheralManager, central: CBCentral, didUnsubscribeFrom characteristic: CBCharacteristic) {
        logger.info("Central \(central.identifier) unsubscribed from characteristic \(characteristic.uuid)")
    }
    
    func peripheralManagerIsReady(toUpdateSubscribers peripheral: CBPeripheralManager) {
        logger.warning("\(#function) called")
        updateTestMessage(for: self.testCharacteristic, onSubscribedCentrals: nil)
    }
    
    func peripheralManagerDidStartAdvertising(_ peripheral: CBPeripheralManager, error: (any Error)?) {
        if (error != nil) {
            logger.error("\(#function) returned error \(String(describing: error)) while starting to advertise")
        }
        else {
            logger.info("\(#function) did start advertising")
        }
    }
    
    func peripheralManager(_ peripheral: CBPeripheralManager, didAdd service: CBService, error: (any Error)?) {
        if (error != nil) {
            logger.error("\(#function) returned error \(String(describing: error)) while adding service \(service.uuid)")
        }
        else {
            logger.info("\(#function) did add service \(service.uuid)")
        }
    }
}

