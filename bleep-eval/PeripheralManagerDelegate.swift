//
//  PeripheralManager.swift
//  bleep-eval
//
//  Created by Simon Núñez Aschenbrenner on 04.05.24.
//

import CoreBluetooth
import Foundation
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
        self.peripheralManager = CBPeripheralManager(delegate: self, queue: nil, options: [CBPeripheralManagerOptionRestoreIdentifierKey: BluetoothManager.peripheralIdentifierKey, CBPeripheralManagerOptionShowPowerAlertKey: true])
        self.service = CBMutableService(type: BluetoothManager.serviceUUID, primary: true)
        self.notificationSource = CBMutableCharacteristic(type: BluetoothManager.notificationSourceUUID, properties: [.indicate], value: nil, permissions: [])
        self.notificationAcknowledgement = CBMutableCharacteristic(type: BluetoothManager.notificationAcknowledgementUUID, properties: [.write], value: nil, permissions: [.writeable])
        self.service.characteristics = [notificationSource, notificationAcknowledgement]
        Logger.peripheral.trace("PeripheralManagerDelegate initialized")
    }
    
    // MARK: public methods
    
    func advertise() {
        Logger.peripheral.debug("Peripheral may attempt to \(#function): \(self.peripheralManager.state == .poweredOn ? "poweredOn" : "!poweredOn") \(self.peripheralManager.isAdvertising ? "isAdvertising" : "!isAdvertising")")
        if peripheralManager.state == .poweredOn {
            if peripheralManager.isAdvertising { peripheralManager.stopAdvertising() }
            peripheralManager.removeAllServices()
            peripheralManager.add(self.service)
            Logger.peripheral.debug("Peripheral attempts to \(#function) with identifier '\(self.notificationManager.identifier)' and service '\(BluetoothManager.getName(of: self.service.uuid))' to centrals")
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
            Logger.peripheral.fault("Peripheral did not add service '\(BluetoothManager.getName(of: service.uuid))': \(error!.localizedDescription)")
        } else {
            Logger.peripheral.debug("Peripheral added service '\(BluetoothManager.getName(of: service.uuid))'")
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
                guard let data = request.value else { // TODO: handle
                    Logger.peripheral.fault("Peripheral can't receiveAcknowledgement(data:) from central '\(Utils.printID(request.central.identifier.uuidString))' because the value property of '\(BluetoothManager.getName(of: request.characteristic.uuid))' is nil")
                    peripheral.respond(to: request, withResult: .attributeNotFound)
                    return
                }
                Logger.peripheral.debug("Peripheral didReceiveWrite for '\(BluetoothManager.getName(of: request.characteristic.uuid))' from central '\(Utils.printID(request.central.identifier.uuidString))' with \(data.count) bytes and will attempt to receiveAcknowledgement(data:)")
                notificationManager.receiveAcknowledgement(data: data)
                peripheral.respond(to: request, withResult: .success) // TODO: different responses depending on receiveAcknowledgement(data:) return value
            }
        }
    }
    
    func peripheralManager(_ peripheral: CBPeripheralManager, central: CBCentral, didSubscribeTo characteristic: CBCharacteristic) {
        Logger.peripheral.info("Central '\(Utils.printID(central.identifier.uuidString))' didSubscribeTo characteristic '\(BluetoothManager.getName(of: characteristic.uuid))'")
        self.central = central
        peripheralManager.setDesiredConnectionLatency(.low, for: central)
        notificationManager.sendNotifications()
    }
    
    func peripheralManager(_ peripheral: CBPeripheralManager, central: CBCentral, didUnsubscribeFrom characteristic: CBCharacteristic) {
        Logger.peripheral.info("Central '\(Utils.printID(central.identifier.uuidString))' didUnsubscribeFrom characteristic '\(BluetoothManager.getName(of: characteristic.uuid))'")
    }
    
    func peripheralManagerIsReady(toUpdateSubscribers peripheral: CBPeripheralManager) {
        Logger.peripheral.debug("\(#function):toUpdateSubscribers")
        notificationManager.sendNotifications()
    }
    
}
