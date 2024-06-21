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
    
    let name = BluetoothConstants.peripheralName
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
    
    // MARK: public methods
    
    func startAdvertising() {
        Logger.peripheral.trace("Peripheral may attempt to \(#function)")
        Logger.peripheral.debug("PeripheralManager is \(self.peripheralManager.state == .poweredOn ? "poweredOn" : "NOT poweredOn") and \(self.peripheralManager.isAdvertising ? "ADVERTISING" : "not advertising"), ConnectionManagerMode is \(self.bluetoothManager.mode.isProvider ? "provider" : "NOT provider")")
        if peripheralManager.isAdvertising {
            Logger.peripheral.debug("Peripheral is already advertising")
        } else if peripheralManager.state == .poweredOn && bluetoothManager.mode.isProvider {
            Logger.peripheral.debug("Peripheral attempts to \(#function) as '\(self.name)' with service '\(getName(of: self.service.uuid))' to centrals")
            peripheralManager.startAdvertising([CBAdvertisementDataServiceUUIDsKey: [self.service.uuid], CBAdvertisementDataLocalNameKey: self.name])
        } else {
            Logger.peripheral.info("Peripheral won't attempt to \(#function)")
        }
    }
    
    func stopAdvertising() {
        Logger.peripheral.trace("Peripheral attempts to \(#function)")
        peripheralManager.isAdvertising ? peripheralManager.stopAdvertising() : Logger.peripheral.trace("Peripheral was not advertising")
    }

    // MARK: delegate methods
    
    func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        switch peripheral.state {
        case .poweredOn:
            Logger.peripheral.debug("\(#function) to 'poweredOn'")
            peripheralManager.removeAllServices()
            peripheralManager.add(self.service)
            startAdvertising()
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
        startAdvertising()
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
                guard let data = request.value else {
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
        stopAdvertising()
        peripheralManager.setDesiredConnectionLatency(.low, for: central)
        notificationManager.sendNotifications()
    }
    
    func peripheralManager(_ peripheral: CBPeripheralManager, central: CBCentral, didUnsubscribeFrom characteristic: CBCharacteristic) {
        Logger.peripheral.info("Central '\(printID(central.identifier.uuidString))' didUnsubscribeFrom characteristic '\(getName(of: characteristic.uuid))'")//, removing from centrals array")
        self.central = nil
        if characteristic.uuid.uuidString == BluetoothConstants.notificationSourceUUID.uuidString {
            notificationManager.decide()
        }
    }
    
    func peripheralManagerIsReady(toUpdateSubscribers peripheral: CBPeripheralManager) {
        Logger.peripheral.debug("\(#function):toUpdateSubscribers")
        notificationManager.sendNotifications()
    }
}
