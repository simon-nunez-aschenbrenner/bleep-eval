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
    
    var central: CBCentral? // TODO: multiple centrals
    var sendQueue: [Notification] = [] // TODO: for each central?
        
    // MARK: initializing methods
    
    init(notificationManager: NotificationManager, bluetoothManager: BluetoothManager) {
        super.init()
        self.notificationManager = notificationManager
        self.bluetoothManager = bluetoothManager
        self.peripheralManager = CBPeripheralManager(delegate: self, queue: nil, options: [CBPeripheralManagerOptionRestoreIdentifierKey: BluetoothConstants.peripheralIdentifierKey, CBPeripheralManagerOptionShowPowerAlertKey: true])
        self.service = CBMutableService(type: BluetoothConstants.serviceUUID, primary: true)
        self.notificationSource = CBMutableCharacteristic(type: BluetoothConstants.notificationSourceUUID, properties: [.indicate], value: nil, permissions: [])
        self.service.characteristics = [notificationSource]
        Logger.peripheral.trace("PeripheralManagerDelegate initialized")
    }
    
    // MARK: public methods
    
    func startAdvertising() {
        let maxSupportedCategoryID = 2
        Logger.peripheral.trace("Peripheral may attempt to \(#function)")
        guard notificationManager.version <= maxSupportedCategoryID else { // TODO: handle
            Logger.peripheral.fault("Peripheral can only startAdvertising with categoryIDs < \(maxSupportedCategoryID + 1), but notificationManager is initialized as version \(self.notificationManager.version)")
            return
        }
        let notificationCount = notificationManager.fetchNotificationCount(withCategoryIDs: [1,2])
        if peripheralManager.isAdvertising {
            Logger.peripheral.debug("Peripheral is already advertising")
        } else if peripheralManager.state == .poweredOn && bluetoothManager.modeIsPeripheral && central == nil && notificationCount > 0 {
            Logger.peripheral.info("Peripheral attempts to \(#function) as '\(self.name)' with service '\(getName(of: self.service.uuid))' to centrals")
            peripheralManager.startAdvertising([CBAdvertisementDataServiceUUIDsKey: [self.service.uuid], CBAdvertisementDataLocalNameKey: self.name])
        } else {
            Logger.peripheral.notice("Peripheral won't attempt to \(#function)")
            Logger.peripheral.debug("PeripheralState is \(self.peripheralManager.state == .poweredOn ? "poweredOn" : "NOT poweredOn"), BluetoothMode is \(self.bluetoothManager.modeIsPeripheral ? "peripheral" : "NOT peripheral"), central property is \(self.central == nil ? "nil" : "NOT nil"), notificationCount is \(!(notificationCount > 0) ? "ZERO" : String(notificationCount))")
            if central != nil { // TODO: && notificationCount > 0 ?
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
        let maxSupportedCategoryID = 2
        Logger.peripheral.trace("Peripheral attempts to \(#function)")
        guard notificationManager.version <= maxSupportedCategoryID else { // TODO: handle
            Logger.peripheral.fault("Peripheral can only sendNotifications with categoryIDs < \(maxSupportedCategoryID + 1), but notificationManager is initialized as version \(self.notificationManager.version)")
            return
        }
        if self.sendQueue.isEmpty {
            Logger.peripheral.trace("Peripheral attempts to populate the sendQueue")
            let notifications = notificationManager.fetchAllNotifications(withCategoryIDs: [1,2])
            if notifications == nil || notifications!.isEmpty {
                Logger.peripheral.notice("Peripheral has no notifications to add to the sendQueue")
            } else {
                self.sendQueue = notifications!
                Logger.peripheral.debug("Peripheral has successfully populated the sendQueue with \(self.sendQueue.count) notifications")
            }
        }
        var endedSuccessfully = true // To sendNoNotificationSignal() in case there are no (more) notifications in the sendQueue
        for notification in self.sendQueue {
            guard notification.categoryID > 0 else {
                Logger.peripheral.trace("Skipping notification #\(printID(notification.hashedID)) because its categoryID is 0")
                continue
            }
            Logger.peripheral.debug("Peripheral attempts to sendNotification #\(printID(notification.hashedID)) with message: '\(notification.message ?? "")'")
            var data = Data()
            data.append(notification.categoryID)
            data.append(notification.hashedID)
            data.append(notification.hashedDestinationAddress)
            data.append(notification.hashedSourceAddress)
            assert(data.count == minMessageLength)
            if let messageData = notification.message.data(using: .utf8) {
                data.append(messageData)
            }
            Logger.peripheral.trace("Peripheral attempts to updateValue of '\(getName(of: self.notificationSource.uuid))'")
            if peripheralManager.updateValue(data, for: self.notificationSource, onSubscribedCentrals: nil) {
                Logger.peripheral.notice("Peripheral updated value of '\(getName(of: self.notificationSource.uuid))' with \(data.count-minMessageLength)+\(minMessageLength)=\(data.count) bytes")
                notification.categoryID = 0
                endedSuccessfully = true
                continue
            } else {
                Logger.peripheral.warning("Peripheral did not update value of '\(getName(of: self.notificationSource.uuid)))' with \(data.count-minMessageLength)+\(minMessageLength)=\(data.count) bytes")
                endedSuccessfully = false
                // peripheralManagerIsReady(toUpdateSubscribers) will call sendNotifications() again.
            }
        }
        if endedSuccessfully {
            Logger.peripheral.trace("Peripheral's \(#function) loop endedSuccessfully, removing all notifications from the sendQueue")
            self.sendQueue.removeAll()
            sendNoNotificationSignal()
        }
    }
    
    private func sendNoNotificationSignal() {
        Logger.peripheral.trace("Peripheral attempts to \(#function)")
        let data = Data(count: minMessageLength)
        Logger.peripheral.debug("Peripheral attempts to updateValue of '\(getName(of: self.notificationSource.uuid))'")
        if peripheralManager.updateValue(data, for: self.notificationSource, onSubscribedCentrals: nil) {
            Logger.peripheral.notice("Peripheral updated value for characteristic '\(getName(of: self.notificationSource.uuid))' with \(data.count) zeros")
        } else {
            Logger.peripheral.warning("Peripheral did not update value of characteristic '\(getName(of: self.notificationSource.uuid)))' with \(data.count) zeros")
            //sendNoNotificationSignal() was not succesful. peripheralManagerIsReady(toUpdateSubscribers) will call sendNotifications() and try to sendNoNotificationSignal() again.
        }
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
        Logger.peripheral.trace("\(#function)")
        startAdvertising()
    }
    
    func peripheralManager(_ peripheral: CBPeripheralManager, didAdd service: CBService, error: (any Error)?) {
        if (error != nil) { // TODO: handle
            Logger.peripheral.fault("Peripheral did not add service '\(getName(of: service.uuid))': \(error!.localizedDescription)")
        } else {
            Logger.peripheral.info("Peripheral added service '\(getName(of: service.uuid))'")
        }
    }
    
    func peripheralManagerDidStartAdvertising(_ peripheral: CBPeripheralManager, error: (any Error)?) {
        if (error != nil) { // TODO: handle
            Logger.peripheral.fault("Peripheral did not start advertising: \(error!.localizedDescription)")
        } else {
            Logger.peripheral.notice("Peripheral started advertising")
        }
    }
    
//    func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveWrite requests: [CBATTRequest]) {
//        Logger.peripheral.trace("Peripheral didReceiveWrite")
//        for request in requests {
//            ()
//        }
//    }
    
    func peripheralManager(_ peripheral: CBPeripheralManager, central: CBCentral, didSubscribeTo characteristic: CBCharacteristic) {
        Logger.peripheral.info("Central '\(printID(central.identifier.uuidString))' didSubscribeTo characteristic '\(getName(of: characteristic.uuid))'")
        self.central = central
        stopAdvertising()
        peripheralManager.setDesiredConnectionLatency(.low, for: central)
        sendNotifications()
    }
    
    func peripheralManager(_ peripheral: CBPeripheralManager, central: CBCentral, didUnsubscribeFrom characteristic: CBCharacteristic) {
        Logger.peripheral.info("Central '\(printID(central.identifier.uuidString))' didUnsubscribeFrom characteristic '\(getName(of: characteristic.uuid))', removing all notifications from the sendQueue")
        self.central = nil
        sendQueue.removeAll()
        startAdvertising()
    }
    
    func peripheralManagerIsReady(toUpdateSubscribers peripheral: CBPeripheralManager) {
        Logger.peripheral.notice("\(#function):toUpdateSubscribers")
        sendNotifications()
    }
}
