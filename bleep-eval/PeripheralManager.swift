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
    
    private(set) var peripheralManager: CBPeripheralManager!
    private(set) var notificationSource: CBMutableCharacteristic!
    private(set) var notificationAcknowledgement: CBMutableCharacteristic!
    private var service: CBMutableService!
    unowned private var notificationManager: NotificationManager!
    unowned private var bluetoothManager: BluetoothManager!
            
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
        Logger.peripheral.debug("Peripheral may attempt to \(#function)")
        guard peripheralManager.state == .poweredOn else {
            Logger.peripheral.warning("Peripheral won't attempt to \(#function) because the peripheralManager is not poweredOn")
            return
        }
        if peripheralManager.isAdvertising { peripheralManager.stopAdvertising() } // TODO: needed?
        peripheralManager.removeAllServices() // TODO: needed?
        peripheralManager.add(self.service) // TODO: needed?
        Logger.peripheral.debug("Peripheral attempts to \(#function) with randomIdentifier '\(self.bluetoothManager.randomIdentifier)' and service '\(BluetoothManager.getName(of: self.service.uuid))' to centrals")
        peripheralManager.startAdvertising([CBAdvertisementDataServiceUUIDsKey: [self.service.uuid], CBAdvertisementDataLocalNameKey: bluetoothManager.randomIdentifier])
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
        guard error == nil else { // TODO: handle
            Logger.peripheral.error("Peripheral did not add service '\(BluetoothManager.getName(of: service.uuid))': \(error!.localizedDescription)")
            return
        }
        Logger.peripheral.debug("Peripheral added service '\(BluetoothManager.getName(of: service.uuid))'")
    }
    
    func peripheralManagerDidStartAdvertising(_ peripheral: CBPeripheralManager, error: (any Error)?) {
        guard error == nil else { // TODO: handle
            Logger.peripheral.error("Peripheral did not start advertising: \(error!.localizedDescription)")
            return
        }
        Logger.peripheral.info("Peripheral started advertising")
    }
    
    func peripheralManager(_ peripheral: CBPeripheralManager, central: CBCentral, didSubscribeTo characteristic: CBCharacteristic) {
        Logger.peripheral.info("Central '\(Utils.printID(central.identifier.uuidString))' didSubscribeTo characteristic '\(BluetoothManager.getName(of: characteristic.uuid))'")
        peripheralManager.setDesiredConnectionLatency(.low, for: central)
        notificationManager.transmitNotifications()
    }
    
    func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveWrite requests: [CBATTRequest]) {
        Logger.peripheral.trace("Peripheral didReceiveWrite")
        for request in requests {
            guard request.characteristic.uuid == self.notificationAcknowledgement.uuid else {
                Logger.peripheral.warning("Peripheral didReceiveWrite for unknown characteristic '\(BluetoothManager.getName(of: request.characteristic.uuid))' from central '\(Utils.printID(request.central.identifier.uuidString))' and will ignore it")
                peripheral.respond(to: request, withResult: .requestNotSupported)
                continue
            }
            guard let data = request.value else { // TODO: handle
                Logger.peripheral.error("Peripheral can't process write from central from central '\(Utils.printID(request.central.identifier.uuidString))' because the value property of '\(BluetoothManager.getName(of: request.characteristic.uuid))' is nil and will ignore it")
                peripheral.respond(to: request, withResult: .attributeNotFound)
                continue
            }
            Logger.peripheral.debug("Peripheral didReceiveWrite for '\(BluetoothManager.getName(of: request.characteristic.uuid))' from central '\(Utils.printID(request.central.identifier.uuidString))'")
            if notificationManager.receiveAcknowledgement(data, from: request.central.identifier.uuidString) {
                peripheral.respond(to: request, withResult: .success)
            } else {
                peripheral.respond(to: request, withResult: .unlikelyError)
            }
        }
    }
    
    func peripheralManager(_ peripheral: CBPeripheralManager, central: CBCentral, didUnsubscribeFrom characteristic: CBCharacteristic) {
        Logger.peripheral.info("Central '\(Utils.printID(central.identifier.uuidString))' didUnsubscribeFrom characteristic '\(BluetoothManager.getName(of: characteristic.uuid))'")
    }
    
    func peripheralManagerIsReady(toUpdateSubscribers peripheral: CBPeripheralManager) {
        Logger.peripheral.debug("\(#function):toUpdateSubscribers")
        notificationManager.transmitNotifications()
    }
}
