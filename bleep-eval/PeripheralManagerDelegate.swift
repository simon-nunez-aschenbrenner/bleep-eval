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

// TODO: Needs better solution for having name/service/characteristic properties set before advertising and updating

class PeripheralManagerDelegate: NSObject, CBPeripheralManagerDelegate {
    
    unowned var bluetoothManager: BluetoothManager!
    private(set) var peripheralManager: CBPeripheralManager!
    private(set) var central: CBCentral?
    
    private(set) var service: CBMutableService? // TODO: Multiple services
    private(set) var characteristic: CBMutableCharacteristic? // TODO: Multiple characteristics
    var testMessage: String? { // TODO: Message queue
        didSet {
            updateTestMessage()
        }
    }
    
    init(bluetoothManager: BluetoothManager) {
        super.init()
        self.bluetoothManager = bluetoothManager
        self.peripheralManager = CBPeripheralManager(delegate: self, queue: nil, options: [CBPeripheralManagerOptionRestoreIdentifierKey: "com.simon.bleep-eval.peripheral", CBPeripheralManagerOptionShowPowerAlertKey: true])
        logger.debug("PeripheralManagerDelegate initialized")
    }
    
    func prepareAdvertising(peripheralName: String!, serviceUUID: CBUUID!, characteristicUUID: CBUUID!) {
        self.service = CBMutableService(type: serviceUUID, primary: true)
        self.characteristic = CBMutableCharacteristic(type: characteristicUUID, properties: [.indicate], value: nil, permissions: [.readable])
        self.service!.characteristics = [self.characteristic!]
        peripheralManager.add(self.service!)
    }
    
    func startAdvertising() {
        peripheralManager.startAdvertising([CBAdvertisementDataServiceUUIDsKey: [bluetoothManager.serviceUUID!.uuidString], CBAdvertisementDataLocalNameKey: bluetoothManager.peripheralName!])
        logger.info("Peripheral starts advertising to centrals")
    }
    
    func stopAdvertising() {
        logger.debug("Attempting to \(#function)")
        if peripheralManager.isAdvertising {
            peripheralManager.stopAdvertising()
            logger.info("Peripheral stops advertising to centrals")
        } else {
            logger.debug("Peripheral was not advertising")
        }
        peripheralManager.removeAllServices()
        logger.info("Peripheral removedAllServices")
    }
    
    private func updateTestMessage() {
        let data: Data = testMessage?.data(using: .utf8) ?? Data()
        if (self.characteristic == nil) {
            logger.error("Peripheral has no characteristic")
        } else {
            self.peripheralManager.updateValue(data, for: self.characteristic!, onSubscribedCentrals: nil)
            logger.info("Updating value of characteristic \(characteristic!.uuid) to: \(String(describing: self.testMessage))")
        }
    }
    
    internal func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        
        switch peripheral.state {
        case .poweredOn:
            logger.info("\(#function): poweredOn")
            if bluetoothManager.mode == .peripheral && !self.peripheralManager.isAdvertising {
                startAdvertising()
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
            logger.error("\(#function): \(peripheral.state) (not implemented)")
        }
    }
    
    internal func peripheralManager(_ peripheral: CBPeripheralManager, willRestoreState dict: [String : Any]) {
        self.peripheralManager = peripheral
        peripheral.delegate = self
        logger.debug("In peripheralManager:willRestoreState()")
        if bluetoothManager.mode == .peripheral && !self.peripheralManager.isAdvertising {
            startAdvertising()
        }
    }
    
    internal func peripheralManager(_ peripheral: CBPeripheralManager, central: CBCentral, didSubscribeTo characteristic: CBCharacteristic) {
        logger.info("Central \(central.identifier) subscribed to characteristic \(characteristic.uuid)")
        updateTestMessage()
    }
    
    internal func peripheralManager(_ peripheral: CBPeripheralManager, central: CBCentral, didUnsubscribeFrom characteristic: CBCharacteristic) {
        logger.info("Central \(central.identifier) unsubscribed from characteristic \(characteristic.uuid)")
    }
    
    internal func peripheralManagerIsReady(toUpdateSubscribers peripheral: CBPeripheralManager) {
        logger.warning("\(#function) called")
        updateTestMessage()
    }
    
    internal func peripheralManagerDidStartAdvertising(_ peripheral: CBPeripheralManager, error: (any Error)?) {
        if (error != nil) {
            logger.error("\(#function) returned error \(String(describing: error)) while starting to advertise")
        }
        else {
            logger.info("\(#function) did start advertising")
        }
    }
    
    internal func peripheralManager(_ peripheral: CBPeripheralManager, didAdd service: CBService, error: (any Error)?) {
        if (error != nil) {
            logger.error("\(#function) returned error \(String(describing: error)) while adding service \(service.uuid)")
        }
        else {
            logger.info("\(#function) did add service \(service.uuid)")
        }
    }
}
