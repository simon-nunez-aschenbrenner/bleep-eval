//
//  CentralManager.swift
//  bleep-eval
//
//  Created by Simon Núñez Aschenbrenner on 07.05.24.
//

import Foundation
import CoreBluetooth
import OSLog

@Observable
class CentralManagerDelegate: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate {
        
    unowned var notificationManager: NotificationManager!
    unowned var bluetoothManager: BluetoothManager!
    var centralManager: CBCentralManager!
    
    var service: CBService?
    var controlPoint: CBCharacteristic?
    
    var peripheral: CBPeripheral? // TODO: multiple peripherals
    var receivedQueue: [Data: Notification] = [:] // TODO: for each peripheral?
    var storedNotificationHashIDs: [Data] = []
    
    // MARK: initializing methods
            
    init(notificationManager: NotificationManager, bluetoothManager: BluetoothManager) {
        super.init()
        self.notificationManager = notificationManager
        self.bluetoothManager = bluetoothManager
        self.centralManager = CBCentralManager(delegate: self, queue: nil, options: [CBCentralManagerOptionRestoreIdentifierKey: BluetoothConstants.centralIdentifierKey, CBCentralManagerOptionShowPowerAlertKey: true])
        Logger.central.trace("CentralManagerDelegate initialized")
    }
    
    // MARK: public methods
        
    func startScan() {
        Logger.peripheral.trace("In \(#function)")
        if centralManager.isScanning {
            Logger.peripheral.debug("Central is already scanning")
        } else if centralManager.state == .poweredOn && bluetoothManager.modeIsCentral && peripheral == nil {
            Logger.central.debug("Central attempts to \(#function) for peripherals with service '\(BluetoothConstants.getName(of: BluetoothConstants.serviceUUID))'")
            centralManager.scanForPeripherals(withServices: [BluetoothConstants.serviceUUID], options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
        } else {
            Logger.central.notice("Central won't attempt to \(#function) because CentralState is \(self.centralManager.state == .poweredOn ? "poweredOn" : "NOT poweredOn"), BluetoothMode is \(self.bluetoothManager.modeIsCentral ? "central" : "NOT central") or Peripheral property is \(self.peripheral == nil ? "nil" : "NOT nil")")
        }
    }
    
    func stopScan() {
        Logger.central.trace("Central attempts to \(#function)")
        centralManager.isScanning ? centralManager.stopScan() : Logger.central.trace("Central was not scanning")
    }
    
    func disconnect() {
        Logger.central.trace("Central attempts to \(#function) from all peripherals")
        if self.peripheral != nil {
            disconnect(from: self.peripheral!)
        } else {
            Logger.central.trace("Central has no peripherals to disconnect from")
        }
    }
    
    // MARK: private methods
    
    private func disconnect(from peripheral: CBPeripheral) {
        Logger.central.debug("Central attempts to \(#function) from peripheral '\(printID(peripheral.identifier.uuidString))'")
        centralManager.cancelPeripheralConnection(peripheral)
    }
    
    private func handleNotificationSourceUpdate(peripheral: CBPeripheral, data: Data) {
        Logger.central.debug("Central attempts to \(#function) from peripheral '\(printID(peripheral.identifier.uuidString))': '\(printData(data))' (Length: \(data.count) bytes)")
        guard data.count == 65 else { // TODO: handle
            Logger.central.fault("NotificationSourceUpdate from peripheral '\(printID(peripheral.identifier.uuidString))' not 65 bytes long: '\(printData(data))' (Length: \(data.count) bytes)")
            return
        }
        let categoryID = UInt8(data[0])
        if categoryID == 0 { // TODO: Needs timeout solution as well, so we are not dependent on the peripheral to disconnect and clear the Queue
            Logger.central.notice("NotificationSourceUpdate from peripheral '\(printID(peripheral.identifier.uuidString))' indicates no more notifications")
            // disconnect(from: peripheral)
        } else {
            let hashedID = data.subdata(in: 1..<33)
            Logger.central.trace("Checking if there's already a notification #\(printID(hashedID)) in storage")
            if storedNotificationHashIDs.contains(hashedID) {
                Logger.central.info("Ignoring notificationSourceUpdate for notification #\(printID(hashedID)) from peripheral '\(printID(peripheral.identifier.uuidString))' as this notification is already stored")
                return // TODO: Send command indicating we are ready for the next notification?
            }
            let hashedDestinationAddress = data.subdata(in: 33..<65)
            let notification = Notification(categoryID: categoryID, hashedID: hashedID, hashedDestinationAddress: hashedDestinationAddress)
            notificationManager.insertNotification(notification)
            receivedQueue[hashedID] = notification
            Logger.peripheral.trace("Central added notification #\(printID(notification.hashedID)) to its receivedQueue, categoryID is \(notification.categoryID)")
            if categoryID == 1 {
                getNotificationData(peripheral: peripheral, hashedID: hashedID, address: notificationManager.address.other)
            } else if categoryID == 2 {
                if notification.hashedDestinationAddress == Address.Broadcast.hashed {
                    Logger.central.trace("Notification #\(printID(notification.hashedID)) is a broadcast message")
                    getNotificationData(peripheral: peripheral, hashedID: hashedID, address: Address.Broadcast.data)
                } else if notification.hashedDestinationAddress == notificationManager.address.hashed {
                    Logger.central.trace("Notification #\(printID(notification.hashedID)) is destined for this notificationManager's address")
                    getNotificationData(peripheral: peripheral, hashedID: hashedID, address: notificationManager.address.data)
                } else {
                    Logger.peripheral.notice("Central won't attempt to getNotificationData of #\(printID(notification.hashedID)), as its hashedDestinationAddress '\(printID(notification.hashedDestinationAddress))' doesn't match this notificationManager's hashed address '\(printID(self.notificationManager.address.hashed))' or the hashed broadcast address '\(printID(Address.Broadcast.hashed))'")
                }
            }
        }
    }
    
    private func getNotificationData(peripheral: CBPeripheral, hashedID: Data, address: Data) {
        Logger.central.trace("Central attempts to \(#function) from peripheral '\(printID(peripheral.identifier.uuidString))' for notification #\(printID(hashedID))")
        var data = Data()
        data.append(0) // CommandID
        data.append(hashedID)
        data.append(address)
        assert(data.count == 41)
        guard let controlPoint = self.controlPoint else { // TODO: handle
            Logger.central.fault("Central can't \(#function) because the controlPoint property is nil")
            return
        }
        peripheral.writeValue(data, for: controlPoint, type: .withResponse)
    }
    
    private func handleDataSourceUpdate(peripheral: CBPeripheral, data: Data) {
        Logger.central.debug("Central attempts to \(#function) from peripheral '\(printID(peripheral.identifier.uuidString))': '\(printData(data))' (Length: \(data.count) bytes)")
        guard data.count > 65 else { // TODO: handle
            Logger.central.fault("DataSourceUpdate from peripheral '\(printID(peripheral.identifier.uuidString))' not more than 65 bytes long: '\(printData(data))' (Length: \(data.count) bytes)")
            return
        }
        let categoryID = UInt8(data[0])
        let hashedID = data.subdata(in: 1..<33)
        let hashedSourceAddress = data.subdata(in: 33..<65)
        let messageData = data.subdata(in: 65..<data.count)
        let message: String = String(data: messageData, encoding: .utf8) ?? ""
        Logger.central.trace("DataSourceUpdate for notification #\(printID(hashedID)) contains the following messageData: '\(message)'")
        Logger.central.trace("Attempting to retrieve notification #\(printID(hashedID)) from receivedQueue")
        guard let notification = receivedQueue[hashedID] else {
            Logger.central.error("Notification #\(printID(hashedID)) not found in receivedQueue") // TODO: handle
            return
        }
        if notification.categoryID != categoryID {
            Logger.central.warning("Notification #\(printID(hashedID)) categoryID changed from \(notification.categoryID) to \(categoryID) between handleNotificationSourceUpdate and \(#function) and will be updated")
            notification.categoryID = categoryID
        }
        notification.hashedSourceAddress = hashedSourceAddress
        notification.message = message
        Logger.central.info("Central updated data of notification #\(printID(notification.hashedID)), including message: '\(notification.message ?? "")'")
        receivedQueue.removeValue(forKey: notification.hashedID)
        Logger.peripheral.trace("Removed notification #\(printID(notification.hashedID)) from receivedQueue")
        if notification.hashedDestinationAddress == notificationManager.address.hashed || notification.hashedDestinationAddress == Address.Broadcast.hashed {
            notificationManager.updateNotificationsDisplay()
        }
    }
    
    private func clearQueue(of peripheral: CBPeripheral) {
        receivedQueue.removeAll()
        Logger.peripheral.trace("Central cleared its receivedQueue")
    }
    
    // MARK: delegate methods
    
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            Logger.central.notice("\(#function) to 'poweredOn'")
            startScan()
        // TODO: handle other cases incl. authorization cases
        case .unknown:
            Logger.central.warning("\(#function) to 'unknown'")
        case .resetting:
            Logger.central.warning("\(#function) to 'resetting'")
        case .unsupported:
            Logger.central.error("\(#function) to 'unsupported'")
        case .unauthorized:
            Logger.central.error("\(#function) to 'unauthorized'")
            Logger.central.error("CBManager authorization: \(CBPeripheralManager.authorization.rawValue)")
        case .poweredOff:
            Logger.central.error("\(#function) to 'poweredOff'")
        @unknown default:
            Logger.central.error("\(#function) to not implemented state: \(central.state.rawValue)")
        }
    }
    
    func centralManager(_ central: CBCentralManager, willRestoreState dict: [String : Any]) {
        Logger.central.trace("In \(#function)")
        startScan()
    }
    
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        Logger.central.info("Central didDiscover peripheral '\(printID(peripheral.identifier.uuidString))' (RSSI: \(RSSI.intValue)) and attempts to connect to it")
        self.peripheral = peripheral
        peripheral.delegate = self
        stopScan()
        storedNotificationHashIDs = notificationManager.fetchAllNotificationHashIDs() ?? []
        centralManager.connect(peripheral, options: nil)
    }
    
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        Logger.central.notice("Central didConnect to peripheral '\(printID(peripheral.identifier.uuidString))' and attempts to discoverServices, including '\(BluetoothConstants.getName(of: BluetoothConstants.serviceUUID))'")
        peripheral.discoverServices([BluetoothConstants.serviceUUID])
    }
    
    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) { // TODO: handle
        Logger.central.error("Central didFailToConnect to peripheral '\(printID(peripheral.identifier.uuidString))': '\(error?.localizedDescription ?? "")'")
        startScan()
    }
    
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: (any Error)?) {
        Logger.central.notice("Central didDiscoverServices on peripheral '\(printID(peripheral.identifier.uuidString))' and attempts to discoverCharacteristics of service '\(BluetoothConstants.getName(of: BluetoothConstants.serviceUUID))'")
        guard let discoveredServices = peripheral.services else { // TODO: handle
            Logger.central.fault("Central can't discoverCharacteristics, because the services array of peripheral '\(printID(peripheral.identifier.uuidString))' is nil")
            return
        }
        for service in discoveredServices {
            Logger.central.trace("Central discovered service '\(BluetoothConstants.getName(of: service.uuid))' on peripheral '\(printID(peripheral.identifier.uuidString))'")
            if service.uuid.uuidString == BluetoothConstants.serviceUUID.uuidString {
                self.service = service
            }
        }
        if self.service == nil {
            Logger.central.fault("Central can't discoverCharacteristics, because it did not discover service '\(BluetoothConstants.getName(of: BluetoothConstants.serviceUUID))' on peripheral '\(printID(peripheral.identifier.uuidString))'")
        } else {
            peripheral.discoverCharacteristics(nil, for: self.service!)
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        if (error != nil) { // TODO: handle
            Logger.central.error("Central did not discoverCharacteristicsFor service '\(BluetoothConstants.getName(of: service.uuid))' on peripheral '\(printID(peripheral.identifier.uuidString))': '\(error!.localizedDescription)'")
        } else {
            guard let discoveredCharacteristics = service.characteristics else { // TODO: handle
                Logger.central.fault("The characteristics array of service '\(BluetoothConstants.getName(of: service.uuid))' on peripheral '\(printID(peripheral.identifier.uuidString)) is nil")
                return
            }
            Logger.central.debug("Central didDiscoverCharacteristicsFor service '\(BluetoothConstants.getName(of: service.uuid))' on peripheral '\(printID(peripheral.identifier.uuidString))', attempting to setNotifyValue")
            var discoveredAllCharacteristics = [false, false, false] // TODO: better name
            for characteristic in discoveredCharacteristics {
                Logger.central.trace("Central discovered characteristic '\(BluetoothConstants.getName(of: characteristic.uuid))'")
                switch characteristic.uuid.uuidString {
                case BluetoothConstants.notificationSourceUUID.uuidString:
                    discoveredAllCharacteristics[0] = true
                    Logger.central.trace("Central attempts to setNotifyValue of '\(BluetoothConstants.getName(of: characteristic.uuid))' to true")
                    peripheral.setNotifyValue(true, for: characteristic)
                case BluetoothConstants.controlPointUUID.uuidString:
                    discoveredAllCharacteristics[1] = true
                    self.controlPoint = characteristic
                    Logger.central.trace("Central added '\(BluetoothConstants.getName(of: characteristic.uuid))' characteristic")
                case BluetoothConstants.dataSourceUUID.uuidString:
                    discoveredAllCharacteristics[2] = true
                    Logger.central.trace("Central attempts to setNotifyValue of '\(BluetoothConstants.getName(of: characteristic.uuid))' to true")
                    peripheral.setNotifyValue(true, for: characteristic)
                default:
                    Logger.central.warning("Central discoverd unexpected characteristic for service '\(BluetoothConstants.getName(of: service.uuid))' on peripheral '\(printID(peripheral.identifier.uuidString))': '\(characteristic.uuid.uuidString)'")
                }
            }
            if !discoveredAllCharacteristics.allSatisfy({ $0 }) { // TODO: handle
                Logger.central.fault("Central did not discover all CharacteristicsFor service '\(BluetoothConstants.getName(of: service.uuid))' on peripheral '\(printID(peripheral.identifier.uuidString))': \(discoveredAllCharacteristics)")
            } else {
                Logger.central.notice("Central did discover all CharacteristicsFor service '\(BluetoothConstants.getName(of: service.uuid))' on peripheral '\(printID(peripheral.identifier.uuidString))': \(discoveredAllCharacteristics)")
            }
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        if (error != nil) { // TODO: handle
            Logger.central.fault("Central did not receive UpdateValueFor characteristic '\(BluetoothConstants.getName(of: characteristic.uuid))' on peripheral '\(printID(peripheral.identifier.uuidString))': '\(error!.localizedDescription)'")
        } else {
            guard let data = characteristic.value else { // TODO: handle
                Logger.central.fault("The value property of characteristic '\(BluetoothConstants.getName(of: characteristic.uuid))' on peripheral '\(printID(peripheral.identifier.uuidString)) is nil")
                return
            }
            Logger.central.debug("Central did receive UpdateValueFor characteristic \(BluetoothConstants.getName(of: characteristic.uuid)) on peripheral '\(printID(peripheral.identifier.uuidString))': '\(printData(data))' (Length: \(data.count) bytes)")
            if characteristic.uuid.uuidString == BluetoothConstants.notificationSourceUUID.uuidString {
                handleNotificationSourceUpdate(peripheral: peripheral, data: data)
            } else if characteristic.uuid.uuidString == BluetoothConstants.dataSourceUUID.uuidString {
                handleDataSourceUpdate(peripheral: peripheral, data: data)
            }
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        if (error != nil) { // TODO: handle
            Logger.central.fault("Central did not WriteValueFor characteristic '\(BluetoothConstants.getName(of: characteristic.uuid))' on peripheral '\(printID(peripheral.identifier.uuidString))': '\(error!.localizedDescription)'")
        } else {
            Logger.central.notice("Central didWriteValueFor characteristic \(BluetoothConstants.getName(of: characteristic.uuid)) on peripheral '\(printID(peripheral.identifier.uuidString))'")
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        if (error != nil) { // TODO: handle
            Logger.central.fault("Central did not UpdateNotificationStateFor characteristic '\(BluetoothConstants.getName(of: characteristic.uuid))' on peripheral '\(printID(peripheral.identifier.uuidString))': '\(error!.localizedDescription)'")
        } else {
            Logger.central.notice("Central didUpdateNotificationStateFor characteristic '\(BluetoothConstants.getName(of: characteristic.uuid))' on peripheral '\(printID(peripheral.identifier.uuidString))' to \(characteristic.isNotifying)")
        }
    }
    
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, timestamp: CFAbsoluteTime, isReconnecting: Bool, error: (any Error)?) {
        if (error != nil) { // TODO: handle
            Logger.central.fault("Central did not DisconnectPeripheral '\(printID(peripheral.identifier.uuidString))': '\(error!.localizedDescription)'")
            if error!.localizedDescription == "The specified device has disconnected from us." { // TODO: needs better solution (connectionEvent?)
                self.peripheral = nil
                clearQueue(of: peripheral)
                startScan()
            }
        } else {
            Logger.central.notice("Central didDisconnectPeripheral '\(printID(peripheral.identifier.uuidString))'")
            if isReconnecting {
                Logger.central.debug("Central isReconnecting to peripheral '\(printID(peripheral.identifier.uuidString))'")
            } else {
                self.peripheral = nil
                clearQueue(of: peripheral)
                startScan()
            }
        }
    }
}
