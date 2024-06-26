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
    
    unowned var notificationManager: NotificationManager!
    unowned var bluetoothManager: BluetoothManager!
    var peripheralManager: CBPeripheralManager!
    
    var service: CBMutableService!
    var notificationSource: CBMutableCharacteristic!
    var notificationAcknowledgement: CBMutableCharacteristic!
    
    var central: CBCentral? // TODO: multiple centrals
        
    // MARK: initializing methods
    
    init(notificationManager: NotificationManager, bluetoothManager: BluetoothManager) {
        super.init()
        self.notificationManager = notificationManager
        self.bluetoothManager = bluetoothManager
        self.peripheralManager = CBPeripheralManager(delegate: self, queue: nil, options: [CBPeripheralManagerOptionRestoreIdentifierKey: BluetoothConstants.peripheralIdentifierKey, CBPeripheralManagerOptionShowPowerAlertKey: true])
        self.service = CBMutableService(type: BluetoothConstants.serviceUUID, primary: true)
        self.notificationSource = CBMutableCharacteristic(type: BluetoothConstants.notificationSourceUUID, properties: [.indicate], value: nil, permissions: [])
        self.notificationAcknowledgement = CBMutableCharacteristic(type: BluetoothConstants.notificationAcknowledgementUUID, properties: [.write], value: nil, permissions: [.writeable])
        self.service.characteristics = [notificationSource, notificationAcknowledgement]
        Logger.peripheral.trace("PeripheralManagerDelegate initialized")
    }
    
    deinit {
        Logger.peripheral.trace("PeripheralManagerDelegate deinitializes")
        peripheralManager.stopAdvertising()
        peripheralManager.removeAllServices()
    }
    
    // MARK: public methods
    
    func advertise() {
        Logger.peripheral.debug("PeripheralManager may attempt to \(#function): peripheralManagerState is \(self.peripheralManager.state == .poweredOn ? "poweredOn" : "NOT poweredOn") and connectionManagerMode is \(self.bluetoothManager.mode.isProvider ? "provider" : "NOT provider")")
        if peripheralManager.isAdvertising {
            Logger.peripheral.trace("PeripheralManager is already advertising and attempts to stopAdvertising")
            peripheralManager.stopAdvertising()
        }
        if peripheralManager.state == .poweredOn && bluetoothManager.mode.isProvider {
            peripheralManager.removeAllServices()
            peripheralManager.add(self.service)
            Logger.peripheral.debug("Peripheral attempts to \(#function) as '\(self.notificationManager.identifier)' with service '\(getName(of: self.service.uuid))' to centrals")
            peripheralManager.startAdvertising([CBAdvertisementDataServiceUUIDsKey: [self.service.uuid], CBAdvertisementDataLocalNameKey: notificationManager.identifier!])
        } else { // TODO: handle?
            Logger.peripheral.warning("Peripheral won't attempt to \(#function)")
        }
    }

    // MARK: delegate methods
    
    func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        switch peripheral.state {
        case .poweredOn:
            Logger.peripheral.debug("\(#function) to 'poweredOn'")
            advertise()
        // TODO: handle other cases incl. authorization cases
        case .unknown:
            Logger.peripheral.warning("\(#function) to 'unknown'")
        case .resetting:
            Logger.peripheral.warning("\(#function) to 'resetting'")
        case .unsupported:
            Logger.peripheral.error("\(#function) to 'unsupported'")
        case .unauthorized:
            Logger.peripheral.error("\(#function) to 'unauthorized'")
            Logger.peripheral.error("CBManager authorization: \(CBPeripheralManager.authorization.rawValue)")
        case .poweredOff:
            Logger.peripheral.error("\(#function) to 'poweredOff'")
        @unknown default:
            Logger.peripheral.error("\(#function) to not implemented state: \(peripheral.state.rawValue)")
        }
    }
    
    func peripheralManager(_ peripheral: CBPeripheralManager, willRestoreState dict: [String : Any]) {
        Logger.peripheral.trace("\(#function)")
        advertise()
    }
    
    func peripheralManager(_ peripheral: CBPeripheralManager, didAdd service: CBService, error: (any Error)?) {
        if (error != nil) { // TODO: handle
            Logger.peripheral.fault("Peripheral did not add service '\(getName(of: service.uuid))': \(error!.localizedDescription)")
        } else {
            Logger.peripheral.debug("Peripheral added service '\(getName(of: service.uuid))'")
        }
    }
    
    func peripheralManagerDidStartAdvertising(_ peripheral: CBPeripheralManager, error: (any Error)?) {
        if (error != nil) { // TODO: handle
            Logger.peripheral.fault("Peripheral did not start advertising: \(error!.localizedDescription)")
        } else {
            Logger.peripheral.info("Peripheral started advertising")
        }
    }
    
    func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveWrite requests: [CBATTRequest]) {
        Logger.peripheral.trace("Peripheral didReceiveWrite")
        for request in requests {
            if request.characteristic.uuid == self.notificationAcknowledgement.uuid {
                Logger.peripheral.trace("Peripheral attempts to handle controlPoint command")
                guard let data = request.value else { // TODO: handle
                    Logger.peripheral.fault("ControlPoint command from central '\(printID(request.central.identifier.uuidString))' is nil")
                    peripheral.respond(to: request, withResult: .attributeNotFound)
                    return
                }
                notificationManager.receiveAcknowledgement(data: data)
            }
        }
    }
    
    func peripheralManager(_ peripheral: CBPeripheralManager, central: CBCentral, didSubscribeTo characteristic: CBCharacteristic) {
        Logger.peripheral.info("Central '\(printID(central.identifier.uuidString))' didSubscribeTo characteristic '\(getName(of: characteristic.uuid))'")
        self.central = central
        peripheralManager.stopAdvertising()
        peripheralManager.setDesiredConnectionLatency(.low, for: central)
        notificationManager.sendNotifications()
    }
    
    func peripheralManager(_ peripheral: CBPeripheralManager, central: CBCentral, didUnsubscribeFrom characteristic: CBCharacteristic) {
        Logger.peripheral.info("Central '\(printID(central.identifier.uuidString))' didUnsubscribeFrom characteristic '\(getName(of: characteristic.uuid))'")
        if characteristic.uuid.uuidString == BluetoothConstants.notificationSourceUUID.uuidString { // TODO: needed?
            notificationManager.decide()
        }
    }
    
    func peripheralManagerIsReady(toUpdateSubscribers peripheral: CBPeripheralManager) {
        Logger.peripheral.debug("\(#function):toUpdateSubscribers")
        notificationManager.sendNotifications()
    }
    
}
