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
    var controlPoint: CBMutableCharacteristic!
    var dataSource: CBMutableCharacteristic!
    
    var central: CBCentral? // TODO: multiple centrals
    var sentQueue: [Data: Notification] = [:] // TODO: for each central?
    var startIndex = 0
        
    // MARK: initializing methods
    
    init(notificationManager: NotificationManager, bluetoothManager: BluetoothManager) {
        super.init()
        self.notificationManager = notificationManager
        self.bluetoothManager = bluetoothManager
        self.peripheralManager = CBPeripheralManager(delegate: self, queue: nil, options: [CBPeripheralManagerOptionRestoreIdentifierKey: BluetoothConstants.peripheralIdentifierKey, CBPeripheralManagerOptionShowPowerAlertKey: true])
        self.service = CBMutableService(type: BluetoothConstants.serviceUUID, primary: true)
        self.notificationSource = CBMutableCharacteristic(type: BluetoothConstants.notificationSourceUUID, properties: [.indicate], value: nil, permissions: [])
        self.controlPoint = CBMutableCharacteristic(type: BluetoothConstants.controlPointUUID, properties: [.write], value: nil, permissions: [.writeable])
        self.dataSource = CBMutableCharacteristic(type: BluetoothConstants.dataSourceUUID, properties: [.indicate], value: nil, permissions: [])
        self.service.characteristics = [notificationSource, controlPoint, dataSource]
        Logger.peripheral.trace("PeripheralManagerDelegate initialized")
    }
    
    // MARK: public methods
    
    func startAdvertising() {
        Logger.peripheral.trace("In \(#function)")
        if peripheralManager.isAdvertising {
            Logger.peripheral.debug("Peripheral is already advertising")
        } else if peripheralManager.state == .poweredOn && bluetoothManager.modeIsPeripheral && central == nil {
            Logger.peripheral.debug("Peripheral attempts to \(#function) as '\(BluetoothConstants.peripheralName)' with service '\(BluetoothConstants.getName(of: self.service.uuid))' to centrals")
            peripheralManager.startAdvertising([CBAdvertisementDataServiceUUIDsKey: [self.service.uuid], CBAdvertisementDataLocalNameKey: BluetoothConstants.peripheralName])
        } else {
            Logger.peripheral.notice("Peripheral won't attempt to \(#function) because PeripheralState is \(self.peripheralManager.state == .poweredOn ? "poweredOn" : "NOT poweredOn"), BluetoothMode is \(self.bluetoothManager.modeIsPeripheral ? "peripheral" : "NOT peripheral") or central property is \(self.central == nil ? "nil" : "NOT nil")")
            if central != nil {
                sendNotifications()
            }
        }
    }
    
    func stopAdvertising() {
        Logger.peripheral.trace("Peripheral attempts to \(#function)")
        peripheralManager.isAdvertising ? peripheralManager.stopAdvertising() : Logger.peripheral.trace("Peripheral was not advertising")
    }
    
    // MARK: private methods
    
    private func sendNotifications() {
        Logger.peripheral.trace("Attempting to \(#function)")
        guard let notifications = notificationManager.fetchAllNotifications() else {
            Logger.peripheral.warning("No notifications to publish")
            sendNoNotificationSignal()
            return
        }
        if startIndex > -1 {
            for index in notifications.indices {
                Logger.peripheral.trace("\(#function): loopIndex = \(index), startIndex = \(self.startIndex)")
                if index < self.startIndex {
                    continue
                }
                let notification = notifications[index]
                Logger.peripheral.debug("Peripheral attempts to sendNotification #\(printID(notification.hashedID)) with message: '\(notification.message ?? "")'")
                sentQueue[notification.hashedID] = notification
                Logger.peripheral.trace("Peripheral added notification #\(printID(notification.hashedID)) to its sentQueue")
                var data = Data()
                data.append(notification.categoryID)
                data.append(notification.hashedID)
                data.append(notification.hashedDestinationAddress)
                assert(data.count == 65)
                Logger.peripheral.debug("Peripheral attempts to updateValue of '\(BluetoothConstants.getName(of: self.notificationSource.uuid))' with: '\(printData(data))' (Length: \(data.count) bytes)")
                self.startIndex = index // We'll save our place in the loop
                if peripheralManager.updateValue(data, for: self.notificationSource, onSubscribedCentrals: nil) {
                    Logger.peripheral.notice("Peripheral updated value for characteristic '\(BluetoothConstants.getName(of: self.notificationSource.uuid))' with '\(printData(data))' (Length: \(data.count) bytes)")
                    self.startIndex = -1 // Iteration was successful, let's go for another round
                    continue
                } else {
                    Logger.peripheral.warning("Peripheral did not update value of characteristic '\(BluetoothConstants.getName(of: self.notificationSource.uuid)))' with '\(printData(data))' (Length: \(data.count) bytes)")
                    break // Iteration was not successful. But peripheralManagerIsReady(toUpdateSubscribers) will call sendNotifications() again and we'll continue with the same index that failed.
                }
            }
        }
        if startIndex < 0 { // The last iteration of the loop before ended successfully. We want to signal that we don't have any more notifications
            sendNoNotificationSignal()
        }
    }
    
    private func sendNoNotificationSignal() {
        let data = Data(count: 65)
        Logger.peripheral.debug("Peripheral attempts to updateValue of '\(BluetoothConstants.getName(of: self.notificationSource.uuid))' with zeros (Length: \(data.count) bytes)")
        if peripheralManager.updateValue(data, for: self.notificationSource, onSubscribedCentrals: nil) {
            Logger.peripheral.notice("Peripheral updated value for characteristic '\(BluetoothConstants.getName(of: self.notificationSource.uuid))' with zeros (Length: \(data.count) bytes)")
            self.startIndex = 0 // Success! But we don't want to update the characteristic's value again.
        } else {
            Logger.peripheral.warning("Peripheral did not update value of characteristic '\(BluetoothConstants.getName(of: self.notificationSource.uuid)))' with zeros (Length: \(data.count) bytes)")
            self.startIndex = -1 // Just to be safe. peripheralManagerIsReady(toUpdateSubscribers) will call sendNotifications() again and we'll have another try.
        }
    }
    
    private func handleControlPointWrite(peripheral: CBPeripheralManager, request: CBATTRequest) {
        if request.characteristic.uuid == self.controlPoint.uuid {
            Logger.peripheral.trace("Peripheral attempts to handle controlPoint command")
            guard let data = request.value else {
                Logger.peripheral.fault("ControlPoint command from central '\(printID(request.central.identifier.uuidString))' is nil")
                peripheral.respond(to: request, withResult: .attributeNotFound)
                return
            }
            guard data.count == 41 else { // TODO: handle
                Logger.peripheral.fault("ControlPoint command from central '\(printID(request.central.identifier.uuidString))' is not 41 bytes long: '\(printData(data))' (Length: \(data.count) bytes)")
                peripheral.respond(to: request, withResult: .invalidAttributeValueLength)
                return
            }
            Logger.peripheral.debug("ControlPoint command from central '\(printID(request.central.identifier.uuidString))' is: '\(printData(data))' (Length: \(data.count) bytes)")
            if data[0] == 0 { // TODO: handle other CommandIDs
                let hashedID = data.subdata(in: 1..<33)
                let destinationAddress = data.subdata(in: 33..<41)
                Logger.peripheral.trace("Provided destinationAddress for notification #\(printID(hashedID)): '\(destinationAddress.withUnsafeBytes { $0.load(as: UInt64.self) })')") // TODO: endianess?
                Logger.peripheral.trace("Attempting to retrieve notification #\(printID(hashedID)) from sentQueue")
                guard let notification = sentQueue[hashedID] else {
                    Logger.peripheral.error("Notification #\(printID(hashedID)) not found in sentQueue") // TODO: handle
                    return
                }
                Logger.peripheral.debug("Retrieved notification #\(printID(hashedID)) from sentQueue, categoryID is \(notification.categoryID)")
                if notification.categoryID == 1 {
                    sendData(of: notification)
                } else if notification.categoryID == 2 {
                    if notification.hashedDestinationAddress == Address.hash(destinationAddress) {
                        sendData(of: notification)
                    } else {
                        Logger.peripheral.warning("Peripheral won't send data of notification #\(printID(notification.hashedID)), as the hash of of the provided destinationAddress '\(printID(Address.hash(destinationAddress)))' doesn't match the notification's hashedDestinationAddress '\(printID(Address.hash(notification.hashedDestinationAddress)))'")
                    }
                }
                
            }
            peripheralManager.respond(to: request, withResult: .success)
            peripheral.respond(to: request, withResult: .success)
        } else {
            Logger.peripheral.error("Unexpected controlPoint command from central '\(printID(request.central.identifier.uuidString))': '\(printData(request.value))'")
            peripheral.respond(to: request, withResult: .requestNotSupported)
        }
    }
    
    private func sendData(of notification: Notification) {
        Logger.peripheral.debug("Peripheral attempts to \(#function) of #\(printID(notification.hashedID))")
        // notification.categoryID = 2 // TODO: Here we may want to reflect that this notification has been sent to another node
        var data = Data()
        data.append(notification.categoryID)
        data.append(notification.hashedID)
        data.append(notification.hashedSourceAddress ?? Data(count: 32))
        assert(data.count == 65)
        data.append(notification.message?.data(using: .utf8) ?? Data())
        Logger.peripheral.debug("Peripheral attempts to updateValue of '\(BluetoothConstants.getName(of: self.dataSource.uuid))' with: '\(printData(data))' (Length: \(data.count) bytes)")
        if peripheralManager.updateValue(data, for: self.dataSource, onSubscribedCentrals: nil) {
            Logger.peripheral.notice("Peripheral updated value for characteristic '\(BluetoothConstants.getName(of: self.dataSource.uuid))' with '\(printData(data))' (Length: \(data.count) bytes)")
            sentQueue.removeValue(forKey: notification.hashedID)
            Logger.peripheral.trace("Removed notification #\(printID(notification.hashedID)) from sentQueue")
        } else {
            Logger.peripheral.warning("Peripheral did not update value of characteristic '\(BluetoothConstants.getName(of: self.dataSource.uuid)))' with '\(printData(data))' (Length: \(data.count) bytes)")
        }
    }
    
    private func clearQueue(of central: CBCentral) {
        startIndex = 0
        sentQueue = [:]
        Logger.peripheral.trace("Peripheral cleared its sentQueue")
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
        Logger.peripheral.trace("In \(#function)")
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
        Logger.peripheral.info("Central '\(printID(central.identifier.uuidString))' didSubscribeTo characteristic '\(BluetoothConstants.getName(of: characteristic.uuid))'")
        self.central = central
        stopAdvertising()
        peripheralManager.setDesiredConnectionLatency(.low, for: central)
        if characteristic.uuid.uuidString == BluetoothConstants.notificationSourceUUID.uuidString && notificationManager.fetchNotificationCount() > 0 {
            sendNotifications()
        }
    }
    
    func peripheralManager(_ peripheral: CBPeripheralManager, central: CBCentral, didUnsubscribeFrom characteristic: CBCharacteristic) {
        Logger.peripheral.info("Central '\(printID(central.identifier.uuidString))' didUnsubscribeFrom characteristic '\(BluetoothConstants.getName(of: characteristic.uuid))'")
        self.central = nil
        if characteristic.uuid.uuidString == BluetoothConstants.notificationSourceUUID.uuidString { // So we only clear the queue once
            clearQueue(of: central)
        }
        startAdvertising()
    }
    
    func peripheralManagerIsReady(toUpdateSubscribers peripheral: CBPeripheralManager) {
        Logger.peripheral.notice("\(#function):toUpdateSubscribers") // TODO: handle
        if self.startIndex > -1 {
            sendNotifications()
        }
    }
}
