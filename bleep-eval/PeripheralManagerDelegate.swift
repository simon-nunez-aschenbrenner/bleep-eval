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
    
    unowned var bluetoothManager: BluetoothManager!
    var peripheralManager: CBPeripheralManager!
    
    var service: CBMutableService!
    var notificationSource: CBMutableCharacteristic!
    var controlPoint: CBMutableCharacteristic!
    var dataSource: CBMutableCharacteristic!
    
    var central: CBCentral? // TODO: multiple centrals
    var sentQueue: [Data: Notification] = [:] // TODO: for each central?
        
    // MARK: initializing methods
    
    init(bluetoothManager: BluetoothManager) {
        super.init()
        self.bluetoothManager = bluetoothManager
        self.peripheralManager = CBPeripheralManager(delegate: self, queue: nil, options: [CBPeripheralManagerOptionRestoreIdentifierKey: BluetoothConstants.peripheralIdentifierKey, CBPeripheralManagerOptionShowPowerAlertKey: true])
        self.service = CBMutableService(type: BluetoothConstants.serviceUUID, primary: true)
        self.notificationSource = CBMutableCharacteristic(type: BluetoothConstants.notificationSourceUUID, properties: [.notify], value: nil, permissions: [])
        self.controlPoint = CBMutableCharacteristic(type: BluetoothConstants.controlPointUUID, properties: [.write], value: nil, permissions: [.writeable])
        self.dataSource = CBMutableCharacteristic(type: BluetoothConstants.dataSourceUUID, properties: [.notify], value: nil, permissions: [])
        self.service.characteristics = [notificationSource, controlPoint, dataSource]
        Logger.peripheral.trace("PeripheralManagerDelegate initialized")
    }
    
    // MARK: public methods
    
    func startAdvertising() {
        if peripheralManager.state == .poweredOn && bluetoothManager.modeIsPeripheral && central == nil {
            Logger.peripheral.debug("Peripheral attempts to \(#function) as '\(BluetoothConstants.peripheralName)' with service '\(BluetoothConstants.getName(of: self.service.uuid))' to centrals")
            peripheralManager.startAdvertising([CBAdvertisementDataServiceUUIDsKey: [self.service.uuid], CBAdvertisementDataLocalNameKey: BluetoothConstants.peripheralName])
        } else { // TODO: handle
            Logger.peripheral.warning("Peripheral won't attempt to \(#function): PeripheralState is \(self.peripheralManager.state == .poweredOn ? "poweredOn" : "not poweredOn"), BluetoothMode is \(self.bluetoothManager.modeIsPeripheral ? "peripheral" : "not peripheral"), Central property is \(self.central == nil ? "nil" : "not nil")")
        }
    }
    
    func stopAdvertising() {
        Logger.peripheral.trace("Peripheral attempts to \(#function)")
        peripheralManager.isAdvertising ? peripheralManager.stopAdvertising() : Logger.peripheral.trace("Peripheral was not advertising")
    }
    
    // MARK: private methods
    
    // TODO: log
    private func sendNotifications() {
        Logger.peripheral.trace("Attempting to \(#function)")
        guard let notifications = NotificationManager.shared.fetchAllNotifications() else {
            Logger.peripheral.warning("No notifications to publish")
            return
        }
        for notification in notifications {
            Logger.peripheral.debug("Peripheral attempts to sendNotification #\(notification.hashedID) (message: '\(notification.message ?? "")')")
            sentQueue[notification.hashedID] = notification
            var data = Data()
            data.append(notification.categoryID)
            data.append(notification.hashedID)
            data.append(notification.hashedDestinationAddress)
            assert(data.count == 65)
            updateNotificationSource(data: data)
        }
        updateNotificationSource(data: Data(count: 65)) // Signal that we don't have any more notifications
    }
    
    private func updateNotificationSource(data: Data) {
        Logger.peripheral.debug("Peripheral attempts to updateValue of '\(BluetoothConstants.getName(of: self.notificationSource.uuid))' with: '\(data.map { String($0) }.joined())' (Length: \(data.count) bytes)")
        if peripheralManager.updateValue(data, for: self.notificationSource, onSubscribedCentrals: nil) {
            Logger.peripheral.notice("Peripheral updated value for characteristic '\(BluetoothConstants.getName(of: self.notificationSource.uuid))' to '\(data.map { String($0) }.joined())' (Length: \(data.count) bytes)")
        } else {
            Logger.peripheral.warning("Peripheral did not update value of characteristic '\(BluetoothConstants.getName(of: self.notificationSource.uuid)))' to '\(data.map { String($0) }.joined())' (Length: \(data.count) bytes)")
        }
    }
    
    private func handleControlPointWrite(peripheral: CBPeripheralManager, request: CBATTRequest) {
        if request.characteristic.uuid == self.controlPoint.uuid {
            Logger.peripheral.trace("Peripheral attempts to handle controlPoint command")
            guard let data = request.value else {
                Logger.peripheral.fault("ControlPoint command from central '\(request.central.identifier.uuidString.suffix(BluetoothConstants.suffixLength))' is nil")
                peripheral.respond(to: request, withResult: .attributeNotFound)
                return
            }
            guard data.count == 41 else { // TODO: handle
                Logger.peripheral.fault("ControlPoint command from central '\(request.central.identifier.uuidString.suffix(BluetoothConstants.suffixLength))' is not 41 bytes long: '\(data.map { String($0) }.joined())' (Length: \(data.count) bytes)")
                peripheral.respond(to: request, withResult: .invalidAttributeValueLength)
                return
            }
            Logger.peripheral.debug("ControlPoint command from central '\(request.central.identifier.uuidString.suffix(BluetoothConstants.suffixLength))' is: '\(data.map { String($0) }.joined())' (Length: \(data.count) bytes)")
            if data[0] == 0 { // TODO: handle other CommandIDs
                let hashedID = data.subdata(in: 1..<33)
                let destinationAddress = data.subdata(in: 33..<41)
                Logger.peripheral.trace("Attempting to retrieve notification #\(hashedID) (provided destinationAddress: '\(Address.encode(destinationAddress).suffix(BluetoothConstants.suffixLength))')")
                guard let notification = sentQueue[hashedID] else {
                    Logger.peripheral.error("Notification #\(hashedID) not found in sentQueue") // TODO: handle
                    return
                }
                // TODO: log, refine
                if notification.categoryID == 1 {
                    sendData(of: notification)
                } else if notification.categoryID == 2 {
                    if notification.hashedDestinationAddress == Address.hash(destinationAddress) {
                        sendData(of: notification)
                    }
                }
                
            }
            peripheralManager.respond(to: request, withResult: .success)
            peripheral.respond(to: request, withResult: .success)
        } else {
            Logger.peripheral.error("Unexpected controlPoint command from central '\(request.central.identifier.uuidString.suffix(BluetoothConstants.suffixLength))': '\(String(data: request.value ?? Data(), encoding: .utf8) ?? "")'")
            peripheral.respond(to: request, withResult: .requestNotSupported)
        }
    }
    
    private func sendData(of notification: Notification) {
        Logger.peripheral.debug("Peripheral attempts to \(#function) of \(notification.hashedID)")
        // notification.categoryID = 2 // TODO: Here we may want to reflect that this notification has been sent to another node
        var data = Data()
        data.append(notification.categoryID)
        data.append(notification.hashedID)
        data.append(notification.hashedSourceAddress ?? Data(count: 32))
        assert(data.count == 65)
        data.append(notification.message?.data(using: .utf8) ?? Data())
        updateDataSource(data: data)
    }
    
    private func updateDataSource(data: Data) {
        Logger.peripheral.debug("Peripheral attempts to updateValue of '\(BluetoothConstants.getName(of: self.dataSource.uuid))' with: '\(data.map { String($0) }.joined())' (Length: \(data.count) bytes)")
        if peripheralManager.updateValue(data, for: self.dataSource, onSubscribedCentrals: nil) {
            Logger.peripheral.notice("Peripheral updated value for characteristic '\(BluetoothConstants.getName(of: self.dataSource.uuid))' to '\(data.map { String($0) }.joined())' (Length: \(data.count) bytes)")
        } else {
            Logger.peripheral.warning("Peripheral did not update value of characteristic '\(BluetoothConstants.getName(of: self.dataSource.uuid)))' to '\(data.map { String($0) }.joined())' (Length: \(data.count) bytes)")
        }
    }
    
    // TODO: log
    private func clearQueue(of central: CBCentral) {
        Logger.peripheral.trace("In \(#function)")
        sentQueue = [:]
        assert(sentQueue.isEmpty)
    }

    // MARK: delegate methods
    
    func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        switch peripheral.state {
        case .poweredOn:
            Logger.peripheral.notice("\(#function) to 'poweredOn'")
            peripheralManager.removeAllServices()
            peripheralManager.add(self.service)
            startAdvertising()
        // TODO: handle other cases incl. authorization cases
        case .unknown:
            Logger.peripheral.warning("\(#function) to 'unknown'")
        case .resetting:
            Logger.peripheral.warning("\(#function): 'resetting'")
        case .unsupported:
            Logger.peripheral.error("\(#function): 'unsupported'")
        case .unauthorized:
            Logger.peripheral.error("\(#function): 'unauthorized'")
            Logger.peripheral.error("CBManager authorization: \(CBPeripheralManager.authorization.rawValue)")
        case .poweredOff:
            Logger.peripheral.error("\(#function): 'poweredOff'")
        @unknown default:
            Logger.peripheral.error("\(#function) to not implemented state: \(peripheral.state.rawValue)")
        }
    }
    
    func peripheralManager(_ peripheral: CBPeripheralManager, willRestoreState dict: [String : Any]) {
        Logger.peripheral.trace("In \(#function): \(dict)")
        startAdvertising()
    }
    
    func peripheralManager(_ peripheral: CBPeripheralManager, didAdd service: CBService, error: (any Error)?) {
        if (error != nil) { // TODO: handle
            Logger.peripheral.fault("Peripheral did not add service '\(BluetoothConstants.getName(of: service.uuid))': \(error!.localizedDescription)")
        } else {
            Logger.peripheral.info("Peripheral added service '\(BluetoothConstants.getName(of: service.uuid))'")
        }
    }
    
    func peripheralManagerDidStartAdvertising(_ peripheral: CBPeripheralManager, error: (any Error)?) {
        if (error != nil) { // TODO: handle
            Logger.peripheral.fault("Peripheral did not start advertising: \(error!.localizedDescription)")
        } else {
            Logger.peripheral.notice("Peripheral started advertising")
        }
    }
    
    func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveWrite requests: [CBATTRequest]) {
        Logger.peripheral.trace("Peripheral didReceiveWrite")
        for request in requests {
            handleControlPointWrite(peripheral: peripheral, request: request)
        }
    }
    
    func peripheralManager(_ peripheral: CBPeripheralManager, central: CBCentral, didSubscribeTo characteristic: CBCharacteristic) {
        Logger.peripheral.info("Central '\(central.identifier.uuidString.suffix(BluetoothConstants.suffixLength))' didSubscribeTo characteristic '\(BluetoothConstants.getName(of: characteristic.uuid))'")
        self.central = central
        stopAdvertising()
        peripheralManager.setDesiredConnectionLatency(.low, for: central)
        if characteristic.uuid.uuidString == BluetoothConstants.notificationSourceUUID.uuidString {
            sendNotifications()
        }
    }
    
    func peripheralManager(_ peripheral: CBPeripheralManager, central: CBCentral, didUnsubscribeFrom characteristic: CBCharacteristic) {
        Logger.peripheral.info("Central '\(central.identifier.uuidString.suffix(BluetoothConstants.suffixLength))' didUnsubscribeFrom characteristic '\(BluetoothConstants.getName(of: characteristic.uuid))'")
        self.central = nil
        if characteristic.uuid.uuidString == BluetoothConstants.notificationSourceUUID.uuidString { // So we only clear the queue once
            clearQueue(of: central)
        }
        startAdvertising()
    }
    
    func peripheralManagerIsReady(toUpdateSubscribers peripheral: CBPeripheralManager) {
        Logger.peripheral.notice("\(#function):toUpdateSubscribers") // TODO: handle
    }
}
