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
        
    unowned var bluetoothManager: BluetoothManager!
    var centralManager: CBCentralManager!
    
    var service: CBService?
    var controlPoint: CBCharacteristic?
    
    var peripheral: CBPeripheral? // TODO: multiple peripherals
    var receivedQueue: [Data: Notification] = [:] // TODO: for each peripheral?
    var storedNotificationHashIDs: [Data] = []
    
    // MARK: initializing methods
            
    init(bluetoothManager: BluetoothManager) {
        super.init()
        self.bluetoothManager = bluetoothManager
        self.centralManager = CBCentralManager(delegate: self, queue: nil, options: [CBCentralManagerOptionRestoreIdentifierKey: BluetoothConstants.centralIdentifierKey, CBCentralManagerOptionShowPowerAlertKey: true])
        Logger.central.trace("CentralManagerDelegate initialized")
    }
    
    // MARK: public methods
        
    func startScan() {
        if centralManager.state == .poweredOn && bluetoothManager.modeIsCentral && peripheral == nil {
            Logger.central.debug("Central attempts to \(#function) for peripherals with service '\(BluetoothConstants.getName(of: BluetoothConstants.serviceUUID))'")
            centralManager.scanForPeripherals(withServices: [BluetoothConstants.serviceUUID], options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
        } else { // TODO: handle
            Logger.central.warning("Central won't attempt to \(#function): CentralState is \(self.centralManager.state == .poweredOn ? "poweredOn" : "not poweredOn"), BluetoothMode is \(self.bluetoothManager.modeIsCentral ? "central" : "not central"), Peripheral property is \(self.peripheral == nil ? "nil" : "not nil")")
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
        Logger.central.debug("Central attempts to \(#function) from peripheral '\(peripheral.identifier.uuidString.suffix(BluetoothConstants.suffixLength))'")
        centralManager.cancelPeripheralConnection(peripheral)
    }
    
    private func handleNotificationSourceUpdate(peripheral: CBPeripheral, data: Data) {
        Logger.central.debug("Central attempts to \(#function) from peripheral '\(peripheral.identifier.uuidString.suffix(BluetoothConstants.suffixLength))': '\(data.map { String($0) }.joined())' (Length: \(data.count) bytes)")
        guard data.count == 65 else { // TODO: handle
            Logger.central.fault("NotificationSourceUpdate from peripheral '\(peripheral.identifier.uuidString.suffix(BluetoothConstants.suffixLength))' not 65 bytes long: '\(data.map { String($0) }.joined())' (Length: \(data.count) bytes)")
            return
        }
        let categoryID = UInt8(data[0])
        if categoryID == 0 { // TODO: Needs timeout solution as well, so we are not dependent on the peripheral to disconnect and clear the Queue
            Logger.central.notice("NotificationSourceUpdate from peripheral '\(peripheral.identifier.uuidString.suffix(BluetoothConstants.suffixLength))' indicates no more notifications")
            disconnect(from: peripheral)
        } else {
            let hashedID = data.subdata(in: 1..<33)
            if storedNotificationHashIDs.contains(hashedID) {
                Logger.central.info("Ignoring notificationSourceUpdate for notification #\(hashedID) from peripheral '\(peripheral.identifier.uuidString.suffix(BluetoothConstants.suffixLength))' as this notification is already stored")
                return // TODO: Send command indicating we are ready for the next notification?
            }
            let hashedDestinationAddress = data.subdata(in: 33..<65)
            let notification = Notification(categoryID: categoryID, hashedID: hashedID, hashedDestinationAddress: hashedDestinationAddress)
            receivedQueue[hashedID] = notification
            // TODO: log, refine
            if categoryID == 1 {
                getNotificationData(peripheral: peripheral, hashedID: hashedID, address: bluetoothManager.address.other)
            } else if categoryID == 2 {
                if hashedID == bluetoothManager.address.hashed {
                    getNotificationData(peripheral: peripheral, hashedID: hashedID, address: bluetoothManager.address.data)
                } else if hashedID == Address.Broadcast.hashed {
                    getNotificationData(peripheral: peripheral, hashedID: hashedID, address: Address.Broadcast.data)
                }
            }
        }
    }
    
    private func getNotificationData(peripheral: CBPeripheral, hashedID: Data, address: Data) {
        Logger.central.trace("Central attempts to \(#function) from peripheral '\(peripheral.identifier.uuidString.suffix(BluetoothConstants.suffixLength))' for notification #\(hashedID)")
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
        Logger.central.debug("Central attempts to \(#function) from peripheral '\(peripheral.identifier.uuidString.suffix(BluetoothConstants.suffixLength))': '\(data.map { String($0) }.joined(separator: " "))' (Length: \(data.count) bytes)")
        guard data.count > 65 else { // TODO: handle
            Logger.central.fault("DataSourceUpdate from peripheral '\(peripheral.identifier.uuidString.suffix(BluetoothConstants.suffixLength))' not more than 65 bytes long: '\(data.map { String($0) }.joined())' (Length: \(data.count) bytes)")
            return
        }
        let categoryID = UInt8(data[0])
        let hashedID = data.subdata(in: 1..<33)
        let hashedSourceAddress = data.subdata(in: 33..<65)
        let messageData = data.subdata(in: 65..<data.count)
        Logger.central.trace("messageData: '\(messageData.map { String($0) }.joined())'")
        let message: String = String(data: messageData, encoding: .utf8) ?? ""
        Logger.central.trace("Attempting to retrieve category \(categoryID) notification #\(hashedID)")
        guard let notification = receivedQueue[hashedID] else {
            Logger.central.error("Category \(categoryID) notification #\(hashedID) not found in receivedQueue") // TODO: handle
            return
        }
        if notification.categoryID != categoryID {
            Logger.central.warning("Notification #\(hashedID) categoryID changed from \(notification.categoryID) to \(categoryID) between handleNotificationSourceUpdate and \(#function), will be updated")
            notification.categoryID = categoryID
        }
        notification.hashedSourceAddress = hashedSourceAddress
        notification.message = message
        Logger.central.info("Central recieved data of notification #\(hashedID) (message: '\(notification.message ?? "")')")
    }
    
    // TODO: log
    // TODO: Needs faster way if there's a notification for us
    private func clearQueue(of peripheral: CBPeripheral) {
        Logger.central.trace("In \(#function)")
        for notification in receivedQueue.values {
            NotificationManager.shared.context!.insert(notification)
        }
        do {
            try NotificationManager.shared.context!.save()
        } catch {
            Logger.notification.error("Failed to save new notifications: \(error)")
        }
        receivedQueue = [:]
        assert(receivedQueue.isEmpty)
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
        Logger.central.info("Central didDiscover peripheral '\(peripheral.identifier.uuidString.suffix(BluetoothConstants.suffixLength))' (RSSI: \(RSSI.intValue)) and attempts to connect to it")
        self.peripheral = peripheral
        peripheral.delegate = self
        stopScan()
        storedNotificationHashIDs = NotificationManager.shared.fetchAllNotificationHashIDs() ?? []
        centralManager.connect(peripheral, options: nil)
    }
    
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        Logger.central.notice("Central didConnect to peripheral '\(peripheral.identifier.uuidString.suffix(BluetoothConstants.suffixLength))' and attempts to discoverServices, including '\(BluetoothConstants.getName(of: BluetoothConstants.serviceUUID))'")
        peripheral.discoverServices([BluetoothConstants.serviceUUID])
    }
    
    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) { // TODO: handle
        Logger.central.error("Central didFailToConnect to peripheral '\(peripheral.identifier.uuidString.suffix(BluetoothConstants.suffixLength))': '\(error?.localizedDescription ?? "")'")
        startScan()
    }
    
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: (any Error)?) {
        Logger.central.notice("Central didDiscoverServices on peripheral '\(peripheral.identifier.uuidString.suffix(BluetoothConstants.suffixLength))' and attempts to discoverCharacteristics of service '\(BluetoothConstants.getName(of: BluetoothConstants.serviceUUID))'")
        guard let discoveredServices = peripheral.services else { // TODO: handle
            Logger.central.fault("Central can't discoverCharacteristics, because the services array of peripheral '\(peripheral.identifier.uuidString.suffix(BluetoothConstants.suffixLength))' is nil")
            return
        }
        for service in discoveredServices {
            Logger.central.trace("Central discovered service '\(BluetoothConstants.getName(of: service.uuid))' on peripheral '\(peripheral.identifier.uuidString.suffix(BluetoothConstants.suffixLength))'")
            if service.uuid.uuidString == BluetoothConstants.serviceUUID.uuidString {
                self.service = service
            }
        }
        if self.service == nil {
            Logger.central.fault("Central can't discoverCharacteristics, because it did not discover service '\(BluetoothConstants.getName(of: BluetoothConstants.serviceUUID))' on peripheral '\(peripheral.identifier.uuidString.suffix(BluetoothConstants.suffixLength))'")
        } else {
            peripheral.discoverCharacteristics(nil, for: self.service!)
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        if (error != nil) { // TODO: handle
            Logger.central.error("Central did not discoverCharacteristicsFor service '\(BluetoothConstants.getName(of: service.uuid))' on peripheral '\(peripheral.identifier.uuidString.suffix(BluetoothConstants.suffixLength))': '\(error!.localizedDescription)'")
        } else {
            guard let discoveredCharacteristics = service.characteristics else { // TODO: handle
                Logger.central.fault("The characteristics array of service '\(BluetoothConstants.getName(of: service.uuid))' on peripheral '\(peripheral.identifier.uuidString.suffix(BluetoothConstants.suffixLength)) is nil")
                return
            }
            Logger.central.debug("Central didDiscoverCharacteristicsFor service '\(BluetoothConstants.getName(of: service.uuid))' on peripheral '\(peripheral.identifier.uuidString.suffix(BluetoothConstants.suffixLength))', attempting to setNotifyValue")
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
                    Logger.central.warning("Central discoverd unexpected characteristic for service '\(BluetoothConstants.getName(of: service.uuid))' on peripheral '\(peripheral.identifier.uuidString.suffix(BluetoothConstants.suffixLength))': '\(characteristic.uuid.uuidString)'")
                }
            }
            if !discoveredAllCharacteristics.allSatisfy({ $0 }) { // TODO: handle
                Logger.central.fault("Central did not discover all CharacteristicsFor service '\(BluetoothConstants.getName(of: service.uuid))' on peripheral '\(peripheral.identifier.uuidString.suffix(BluetoothConstants.suffixLength))': \(discoveredAllCharacteristics)")
            } else {
                Logger.central.notice("Central did discover all CharacteristicsFor service '\(BluetoothConstants.getName(of: service.uuid))' on peripheral '\(peripheral.identifier.uuidString.suffix(BluetoothConstants.suffixLength))': \(discoveredAllCharacteristics)")
            }
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        if (error != nil) { // TODO: handle
            Logger.central.fault("Central did not receive UpdateValueFor characteristic '\(BluetoothConstants.getName(of: characteristic.uuid))' on peripheral '\(peripheral.identifier.uuidString.suffix(BluetoothConstants.suffixLength))': '\(error!.localizedDescription)'")
        } else {
            guard let data = characteristic.value else { // TODO: handle
                Logger.central.fault("The value property of characteristic '\(BluetoothConstants.getName(of: characteristic.uuid))' on peripheral '\(peripheral.identifier.uuidString.suffix(BluetoothConstants.suffixLength)) is nil")
                return
            }
            Logger.central.debug("Central did receive UpdateValueFor characteristic \(BluetoothConstants.getName(of: characteristic.uuid)) on peripheral '\(peripheral.identifier.uuidString.suffix(BluetoothConstants.suffixLength))': '\(data.map { String($0) }.joined(separator: " "))' (Length: \(data.count) bytes)")
            if characteristic.uuid.uuidString == BluetoothConstants.notificationSourceUUID.uuidString {
                handleNotificationSourceUpdate(peripheral: peripheral, data: data)
            } else if characteristic.uuid.uuidString == BluetoothConstants.dataSourceUUID.uuidString {
                handleDataSourceUpdate(peripheral: peripheral, data: data)
            }
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        if (error != nil) { // TODO: handle
            Logger.central.fault("Central did not WriteValueFor characteristic '\(BluetoothConstants.getName(of: characteristic.uuid))' on peripheral '\(peripheral.identifier.uuidString.suffix(BluetoothConstants.suffixLength))': '\(error!.localizedDescription)'")
        } else {
            Logger.central.notice("Central didWriteValueFor characteristic \(BluetoothConstants.getName(of: characteristic.uuid)) on peripheral '\(peripheral.identifier.uuidString.suffix(BluetoothConstants.suffixLength))'")
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        if (error != nil) { // TODO: handle
            Logger.central.fault("Central did not UpdateNotificationStateFor characteristic '\(BluetoothConstants.getName(of: characteristic.uuid))' on peripheral '\(peripheral.identifier.uuidString.suffix(BluetoothConstants.suffixLength))': '\(error!.localizedDescription)'")
        } else {
            Logger.central.notice("Central didUpdateNotificationStateFor characteristic '\(BluetoothConstants.getName(of: characteristic.uuid))' on peripheral '\(peripheral.identifier.uuidString.suffix(BluetoothConstants.suffixLength))' to \(characteristic.isNotifying)")
        }
    }
    
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, timestamp: CFAbsoluteTime, isReconnecting: Bool, error: (any Error)?) {
        if (error != nil) { // TODO: handle
            Logger.central.fault("Central did not DisconnectPeripheral '\(peripheral.identifier.uuidString.suffix(BluetoothConstants.suffixLength))': '\(error!.localizedDescription)'")
            if error!.localizedDescription == "The specified device has disconnected from us." { // TODO: needs better solution (connectionEvent?)
                self.peripheral = nil
                clearQueue(of: peripheral)
                startScan()
            }
        } else {
            Logger.central.notice("Central didDisconnectPeripheral '\(peripheral.identifier.uuidString.suffix(BluetoothConstants.suffixLength))'")
            if isReconnecting {
                Logger.central.debug("Central isReconnecting to peripheral '\(peripheral.identifier.uuidString.suffix(BluetoothConstants.suffixLength))'")
            } else {
                self.peripheral = nil
                clearQueue(of: peripheral)
                startScan()
            }
        }
    }
}
