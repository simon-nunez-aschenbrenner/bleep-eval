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
    var notifications: [UInt32: Notification] = [:] // TODO: for each peripheral? // TODO: rolling queue, list?
    
    // MARK: initializing methods
            
    init(bluetoothManager: BluetoothManager) {
        super.init()
        self.bluetoothManager = bluetoothManager
        self.centralManager = CBCentralManager(delegate: self, queue: nil, options: [CBCentralManagerOptionRestoreIdentifierKey: BluetoothConstants.centralIdentifierKey, CBCentralManagerOptionShowPowerAlertKey: true])
        Logger.bluetooth.trace("CentralManagerDelegate initialized")
    }
    
    // MARK: public methods
        
    func startScan() {
        if centralManager.state == .poweredOn && bluetoothManager.modeIsCentral && peripheral == nil {
            Logger.bluetooth.debug("Central attempts to \(#function) for peripherals with service '\(BluetoothConstants.getName(of: BluetoothConstants.serviceUUID))'")
            centralManager.scanForPeripherals(withServices: [BluetoothConstants.serviceUUID], options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
        } else { // TODO: handle
            Logger.bluetooth.warning("Central won't attempt to \(#function): CentralState is \(self.centralManager.state == .poweredOn ? "poweredOn" : "not poweredOn"), BluetoothMode is \(self.bluetoothManager.modeIsCentral ? "central" : "not central"), Peripheral property is \(self.peripheral == nil ? "nil" : "not nil")")
        }
    }
    
    func stopScan() {
        Logger.bluetooth.trace("Central attempts to \(#function)")
        centralManager.isScanning ? centralManager.stopScan() : Logger.bluetooth.trace("Central was not scanning")
    }
    
    func disconnect() {
        Logger.bluetooth.trace("Central attempts to \(#function) from all peripherals")
        if self.peripheral != nil {
            disconnect(from: self.peripheral!)
        } else {
            Logger.bluetooth.trace("Central has no peripherals to disconnect from")
        }
    }
    
    func disconnect(from peripheral: CBPeripheral) {
        Logger.bluetooth.debug("Central attempts to \(#function) from peripheral '\(peripheral.identifier.uuidString.suffix(BluetoothConstants.UUIDSuffixLength))'")
        centralManager.cancelPeripheralConnection(peripheral)
    }
    
    // MARK: private methods
    
    private func handleNotificationSourceUpdate(peripheral: CBPeripheral, data: Data) {
        Logger.bluetooth.debug("Central attempts to \(#function) from peripheral '\(peripheral.identifier.uuidString.suffix(BluetoothConstants.UUIDSuffixLength))': '\(data.map { String($0) }.joined(separator: " "))'")
        guard data.count == 8 else { // TODO: handle
            Logger.bluetooth.fault("NotificationSourceUpdate from peripheral '\(peripheral.identifier.uuidString.suffix(BluetoothConstants.UUIDSuffixLength))' not 8 bytes long: '\(data.map { String($0) }.joined(separator: " "))'")
            return
        }
        // TODO: handle other
        let eventID = 0
        let eventFlags = 0
        let categoryID = 0
        if data[0] == eventID {
            if data[1] == eventFlags {
                if data[2] == categoryID {
                    let notificationID = data.suffix(4).withUnsafeBytes { $0.load(as: UInt32.self) }
                    let notification: Notification = Notification(categoryID: UInt8(categoryID), notificationID: notificationID, attributes: [])
                    notifications[notificationID] = notification
                    getNotificationData(peripheral: peripheral, notification: notification)
                }
            }
        }
    }
    
    private func getNotificationData(peripheral: CBPeripheral, notification: Notification) { // TODO: handle multiple attributes
        Logger.bluetooth.trace("Central attempts to \(#function) from peripheral '\(peripheral.identifier.uuidString.suffix(BluetoothConstants.UUIDSuffixLength))' for notification #\(notification.notificationID)")
        var data = Data()
        data.append(0) // CommandIDGetNotificationAttributes
        var notificationID = notification.notificationID
        withUnsafeBytes(of: &notificationID) { bytes in data.append(contentsOf: bytes) }
        data.append(0) // AttributeID
        guard let controlPoint = self.controlPoint else { // TODO: handle
            Logger.bluetooth.fault("Central can't \(#function) because the controlPoint property is nil")
            return
        }
        peripheral.writeValue(data, for: controlPoint, type: .withResponse)
    }
    
    private func handleDataSourceUpdate(peripheral: CBPeripheral, data: Data) {
        Logger.bluetooth.debug("Central attempts to \(#function) from peripheral '\(peripheral.identifier.uuidString.suffix(BluetoothConstants.UUIDSuffixLength))'")
        guard data.count > 8 else { // TODO: handle
            Logger.bluetooth.fault("DataSourceUpdate from peripheral '\(peripheral.identifier.uuidString.suffix(BluetoothConstants.UUIDSuffixLength))' not more than 8 bytes long: '\(data.map { String($0) }.joined(separator: " "))'")
            return
        }
        if data[0] == 0 { // TODO: handle other CommandIDs
            let notificationIDData = data.subdata(in: 1..<5)
            let notificationID: UInt32 = notificationIDData.withUnsafeBytes { $0.load(as: UInt32.self) }
            let attributeID = Int(data[5]) // TODO: handle multiple attributes
            let attributeLengthData = data.subdata(in: 6..<8)
            let attributeLength: UInt16 = attributeLengthData.withUnsafeBytes { $0.load(as: UInt16.self) }
            let attributeData = data.subdata(in: 8..<Int(attributeLength)+1)
            let attribute: String = String(data: attributeData, encoding: .utf8) ?? ""
            Logger.bluetooth.trace("Attempting to add attribute #\(attributeID) with length of \(attributeLength) to notification #\(notificationID): '\(attribute)'")
            notifications[notificationID]?.attributes[attributeID] = attribute // TODO: test with different attributeIDs
        }
    }
    
    // MARK: delegate methods
    
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            Logger.bluetooth.notice("\(#function) to 'poweredOn'")
            startScan()
        // TODO: handle other cases incl. authorization cases
        case .unknown:
            Logger.bluetooth.warning("\(#function) to 'unknown'")
        case .resetting:
            Logger.bluetooth.warning("\(#function) to 'resetting'")
        case .unsupported:
            Logger.bluetooth.error("\(#function) to 'unsupported'")
        case .unauthorized:
            Logger.bluetooth.error("\(#function) to 'unauthorized'")
            Logger.bluetooth.error("CBManager authorization: \(CBPeripheralManager.authorization.rawValue)")
        case .poweredOff:
            Logger.bluetooth.error("\(#function) to 'poweredOff'")
        @unknown default:
            Logger.bluetooth.error("\(#function) to not implemented state: \(central.state.rawValue)")
        }
    }
    
    func centralManager(_ central: CBCentralManager, willRestoreState dict: [String : Any]) {
        Logger.bluetooth.trace("In \(#function)")
//        self.centralManager = central
//        central.delegate = self
        startScan()
    }
    
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        Logger.bluetooth.info("Central didDiscover peripheral '\(peripheral.identifier.uuidString.suffix(BluetoothConstants.UUIDSuffixLength))' (RSSI: \(RSSI.intValue)) and attempts to connect to it")
        self.peripheral = peripheral
        peripheral.delegate = self
        centralManager.stopScan()
        centralManager.connect(peripheral, options: nil)
    }
    
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        Logger.bluetooth.notice("Central didConnect to peripheral '\(peripheral.identifier.uuidString.suffix(BluetoothConstants.UUIDSuffixLength))' and attempts to discoverServices, including '\(BluetoothConstants.getName(of: BluetoothConstants.serviceUUID))'")
        peripheral.discoverServices([BluetoothConstants.serviceUUID])
    }
    
    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) { // TODO: handle
        Logger.bluetooth.error("Central didFailToConnect to peripheral '\(peripheral.identifier.uuidString.suffix(BluetoothConstants.UUIDSuffixLength))': '\(error?.localizedDescription ?? "")'")
    }
    
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: (any Error)?) {
        Logger.bluetooth.notice("Central didDiscoverServices on peripheral '\(peripheral.identifier.uuidString.suffix(BluetoothConstants.UUIDSuffixLength))' and attempts to discoverCharacteristics of service '\(BluetoothConstants.getName(of: BluetoothConstants.serviceUUID))'")
        guard let discoveredServices = peripheral.services else { // TODO: handle
            Logger.bluetooth.fault("Central can't discoverCharacteristics, because the services array of peripheral '\(peripheral.identifier.uuidString.suffix(BluetoothConstants.UUIDSuffixLength))' is nil")
            return
        }
        for service in discoveredServices {
            Logger.bluetooth.trace("Central discovered service '\(BluetoothConstants.getName(of: service.uuid))' on peripheral '\(peripheral.identifier.uuidString.suffix(BluetoothConstants.UUIDSuffixLength))'")
            if service.uuid.uuidString == BluetoothConstants.serviceUUID.uuidString {
                self.service = service
            }
        }
        if self.service == nil {
            Logger.bluetooth.fault("Central can't discoverCharacteristics, because it did not discover service '\(BluetoothConstants.getName(of: BluetoothConstants.serviceUUID))' on peripheral '\(peripheral.identifier.uuidString.suffix(BluetoothConstants.UUIDSuffixLength))'")
        } else {
            peripheral.discoverCharacteristics(nil, for: self.service!)
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        if (error != nil) { // TODO: handle
            Logger.bluetooth.error("Central did not discoverCharacteristicsFor service '\(BluetoothConstants.getName(of: service.uuid))' on peripheral '\(peripheral.identifier.uuidString.suffix(BluetoothConstants.UUIDSuffixLength))': '\(error!.localizedDescription)'")
        } else {
            guard let discoveredCharacteristics = service.characteristics else { // TODO: handle
                Logger.bluetooth.fault("The characteristics array of service '\(BluetoothConstants.getName(of: service.uuid))' on peripheral '\(peripheral.identifier.uuidString.suffix(BluetoothConstants.UUIDSuffixLength)) is nil")
                return
            }
            Logger.bluetooth.debug("Central didDiscoverCharacteristicsFor service '\(BluetoothConstants.getName(of: service.uuid))' on peripheral '\(peripheral.identifier.uuidString.suffix(BluetoothConstants.UUIDSuffixLength))', attempting to setNotifyValue")
            var discoveredAllCharacteristics = [false, false, false] // TODO: better name
            for characteristic in discoveredCharacteristics {
                Logger.bluetooth.trace("Central discovered characteristic '\(BluetoothConstants.getName(of: characteristic.uuid))'")
                switch characteristic.uuid.uuidString {
                case BluetoothConstants.notificationSourceUUID.uuidString:
                    discoveredAllCharacteristics[0] = true
                    Logger.bluetooth.trace("Central attempts to setNotifyValue of '\(BluetoothConstants.getName(of: characteristic.uuid))' to true")
                    peripheral.setNotifyValue(true, for: characteristic)
                case BluetoothConstants.controlPointUUID.uuidString:
                    discoveredAllCharacteristics[1] = true
                    self.controlPoint = characteristic
                case BluetoothConstants.dataSourceUUID.uuidString:
                    discoveredAllCharacteristics[2] = true
                    Logger.bluetooth.trace("Central attempts to setNotifyValue of '\(BluetoothConstants.getName(of: characteristic.uuid))' to true")
                    peripheral.setNotifyValue(true, for: characteristic)
                default:
                    Logger.bluetooth.warning("Central discoverd unexpected characteristic for service '\(BluetoothConstants.getName(of: service.uuid))' on peripheral '\(peripheral.identifier.uuidString.suffix(BluetoothConstants.UUIDSuffixLength))': '\(characteristic.uuid.uuidString)'")
                }
            }
            if !discoveredAllCharacteristics.allSatisfy({ $0 }) { // TODO: handle
                Logger.bluetooth.fault("Central did not discover all CharacteristicsFor service '\(BluetoothConstants.getName(of: service.uuid))' on peripheral '\(peripheral.identifier.uuidString.suffix(BluetoothConstants.UUIDSuffixLength))': \(discoveredAllCharacteristics)")
            } else {
                Logger.bluetooth.notice("Central did discover all CharacteristicsFor service '\(BluetoothConstants.getName(of: service.uuid))' on peripheral '\(peripheral.identifier.uuidString.suffix(BluetoothConstants.UUIDSuffixLength))': \(discoveredAllCharacteristics)")
            }
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        if (error != nil) { // TODO: handle
            Logger.bluetooth.fault("Central did not receive UpdateValueFor characteristic '\(BluetoothConstants.getName(of: characteristic.uuid))' on peripheral '\(peripheral.identifier.uuidString.suffix(BluetoothConstants.UUIDSuffixLength))': '\(error!.localizedDescription)'")
        } else {
            guard let data = characteristic.value else { // TODO: handle
                Logger.bluetooth.fault("The value property of characteristic '\(BluetoothConstants.getName(of: characteristic.uuid))' on peripheral '\(peripheral.identifier.uuidString.suffix(BluetoothConstants.UUIDSuffixLength)) is nil")
                return
            }
            Logger.bluetooth.debug("Central did receive UpdateValueFor characteristic \(BluetoothConstants.getName(of: characteristic.uuid)) on peripheral '\(peripheral.identifier.uuidString.suffix(BluetoothConstants.UUIDSuffixLength))': '\(data)'")
            if characteristic.uuid.uuidString == BluetoothConstants.notificationSourceUUID.uuidString {
                handleNotificationSourceUpdate(peripheral: peripheral, data: data)
            } else if characteristic.uuid.uuidString == BluetoothConstants.dataSourceUUID.uuidString {
                handleDataSourceUpdate(peripheral: peripheral, data: data)
            }
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        if (error != nil) { // TODO: handle
            Logger.bluetooth.fault("Central did not WriteValueFor characteristic '\(BluetoothConstants.getName(of: characteristic.uuid))' on peripheral '\(peripheral.identifier.uuidString.suffix(BluetoothConstants.UUIDSuffixLength))': '\(error!.localizedDescription)'")
        } else {
            Logger.bluetooth.notice("Central didWriteValueFor characteristic \(BluetoothConstants.getName(of: characteristic.uuid)) on peripheral '\(peripheral.identifier.uuidString.suffix(BluetoothConstants.UUIDSuffixLength))'")
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        if (error != nil) { // TODO: handle
            Logger.bluetooth.fault("Central did not UpdateNotificationStateFor characteristic '\(BluetoothConstants.getName(of: characteristic.uuid))' on peripheral '\(peripheral.identifier.uuidString.suffix(BluetoothConstants.UUIDSuffixLength))': '\(error!.localizedDescription)'")
        } else {
            Logger.bluetooth.notice("Central didUpdateNotificationStateFor characteristic '\(BluetoothConstants.getName(of: characteristic.uuid))' on peripheral '\(peripheral.identifier.uuidString.suffix(BluetoothConstants.UUIDSuffixLength))' to \(characteristic.isNotifying)")
        }
    }
    
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, timestamp: CFAbsoluteTime, isReconnecting: Bool, error: (any Error)?) {
        if (error != nil) { // TODO: handle
            Logger.bluetooth.fault("Central did not DisconnectPeripheral '\(peripheral.identifier.uuidString.suffix(BluetoothConstants.UUIDSuffixLength))': '\(error!.localizedDescription)'")
            if error!.localizedDescription == "The specified device has disconnected from us." { // TODO: needs better solution (connectionEvent?)
                self.peripheral = nil
                startScan()
            }
        } else {
            Logger.bluetooth.notice("Central didDisconnectPeripheral '\(peripheral.identifier.uuidString.suffix(BluetoothConstants.UUIDSuffixLength))'")
            if isReconnecting {
                Logger.bluetooth.debug("Central isReconnecting to peripheral '\(peripheral.identifier.uuidString.suffix(BluetoothConstants.UUIDSuffixLength))'")
            } else {
                self.peripheral = nil
                startScan()
            }
        }
    }
}
