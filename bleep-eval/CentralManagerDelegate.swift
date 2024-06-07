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
    var notifications: [UInt16: Notification] = [:] // TODO: for each peripheral? // TODO: rolling queue, list?
    
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
        Logger.bluetooth.debug("Central attempts to \(#function) from peripheral '\(peripheral.identifier.uuidString.suffix(BluetoothConstants.suffixLength))'")
        centralManager.cancelPeripheralConnection(peripheral)
    }
    
    // MARK: private methods
    
    private func handleNotificationSourceUpdate(peripheral: CBPeripheral, data: Data) {
        Logger.bluetooth.debug("Central attempts to \(#function) from peripheral '\(peripheral.identifier.uuidString.suffix(BluetoothConstants.suffixLength))': '\(data.map { String($0) }.joined(separator: " "))' (Length: \(data.count))")
        guard data.count == 11 else { // TODO: handle
            Logger.bluetooth.fault("NotificationSourceUpdate from peripheral '\(peripheral.identifier.uuidString.suffix(BluetoothConstants.suffixLength))' not 11 bytes long: '\(data.map { String($0) }.joined(separator: " "))' (Length: \(data.count))")
            return
        }
        // TODO: handle different categoryIDs
        let notificationIDData = data.subdata(in: 0..<2)
        let notificationID: UInt16 = notificationIDData.withUnsafeBytes { $0.load(as: UInt16.self) }.littleEndian
        getNotificationData(peripheral: peripheral, notificationID: notificationID)
    }
    
    private func getNotificationData(peripheral: CBPeripheral, notificationID: UInt16) {
        Logger.bluetooth.trace("Central attempts to \(#function) from peripheral '\(peripheral.identifier.uuidString.suffix(BluetoothConstants.suffixLength))' for notification #\(notificationID)")
        var data = Data()
        var notificationID = notificationID
        withUnsafeBytes(of: &notificationID) { bytes in data.append(contentsOf: bytes) }
        data.append(0) // CommandID
        guard let controlPoint = self.controlPoint else { // TODO: handle
            Logger.bluetooth.fault("Central can't \(#function) because the controlPoint property is nil")
            return
        }
        peripheral.writeValue(data, for: controlPoint, type: .withResponse)
    }
    
    private func handleDataSourceUpdate(peripheral: CBPeripheral, data: Data) {
        Logger.bluetooth.debug("Central attempts to \(#function) from peripheral '\(peripheral.identifier.uuidString.suffix(BluetoothConstants.suffixLength))'")
        guard data.count > 18 else { // TODO: handle
            Logger.bluetooth.fault("DataSourceUpdate from peripheral '\(peripheral.identifier.uuidString.suffix(BluetoothConstants.suffixLength))' not more than 18 bytes long: '\(data.map { String($0) }.joined(separator: " "))' (Length: \(data.count))")
            return
        }
        if data[2] == 0 { // TODO: handle other CommandIDs
            let notificationIDData = data.subdata(in: 0..<2)
            let notificationID: UInt16 = notificationIDData.withUnsafeBytes { $0.load(as: UInt16.self) }.littleEndian
            let categoryID = UInt8(data[2]) // TODO: redundant
            let destinationAddressData = data.subdata(in: 3..<11)
            let destinationAddress: Address = Address(destinationAddressData.withUnsafeBytes { $0.load(as: UInt64.self) }.littleEndian)
            let sourceAddressData = data.subdata(in: 11..<19)
            let sourceAddress: Address = Address(sourceAddressData.withUnsafeBytes { $0.load(as: UInt64.self) }.littleEndian)
            let messageData = data.subdata(in: 19..<data.count)
            Logger.bluetooth.trace("messageData: '\(messageData.map { String($0) }.joined(separator: " "))'")
            let message: String = String(data: messageData, encoding: .utf8) ?? ""
            Logger.bluetooth.trace("Attempting to add category \(categoryID) notification #\(notificationID) with message '\(message)' intended from '\(sourceAddress.base58EncodedString.suffix(BluetoothConstants.suffixLength))' to '\(destinationAddress.base58EncodedString.suffix(BluetoothConstants.suffixLength))'")
            let notification = Notification(notificationID: notificationID, categoryID: categoryID, sourceAddress: sourceAddress, destinationAddress: destinationAddress, message: message)
            notifications[notificationID] = notification
            Logger.bluetooth.info("Central recieved data of \(notification)")
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
        Logger.bluetooth.info("Central didDiscover peripheral '\(peripheral.identifier.uuidString.suffix(BluetoothConstants.suffixLength))' (RSSI: \(RSSI.intValue)) and attempts to connect to it")
        self.peripheral = peripheral
        peripheral.delegate = self
        centralManager.stopScan()
        centralManager.connect(peripheral, options: nil)
    }
    
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        Logger.bluetooth.notice("Central didConnect to peripheral '\(peripheral.identifier.uuidString.suffix(BluetoothConstants.suffixLength))' and attempts to discoverServices, including '\(BluetoothConstants.getName(of: BluetoothConstants.serviceUUID))'")
        peripheral.discoverServices([BluetoothConstants.serviceUUID])
    }
    
    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) { // TODO: handle
        Logger.bluetooth.error("Central didFailToConnect to peripheral '\(peripheral.identifier.uuidString.suffix(BluetoothConstants.suffixLength))': '\(error?.localizedDescription ?? "")'")
    }
    
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: (any Error)?) {
        Logger.bluetooth.notice("Central didDiscoverServices on peripheral '\(peripheral.identifier.uuidString.suffix(BluetoothConstants.suffixLength))' and attempts to discoverCharacteristics of service '\(BluetoothConstants.getName(of: BluetoothConstants.serviceUUID))'")
        guard let discoveredServices = peripheral.services else { // TODO: handle
            Logger.bluetooth.fault("Central can't discoverCharacteristics, because the services array of peripheral '\(peripheral.identifier.uuidString.suffix(BluetoothConstants.suffixLength))' is nil")
            return
        }
        for service in discoveredServices {
            Logger.bluetooth.trace("Central discovered service '\(BluetoothConstants.getName(of: service.uuid))' on peripheral '\(peripheral.identifier.uuidString.suffix(BluetoothConstants.suffixLength))'")
            if service.uuid.uuidString == BluetoothConstants.serviceUUID.uuidString {
                self.service = service
            }
        }
        if self.service == nil {
            Logger.bluetooth.fault("Central can't discoverCharacteristics, because it did not discover service '\(BluetoothConstants.getName(of: BluetoothConstants.serviceUUID))' on peripheral '\(peripheral.identifier.uuidString.suffix(BluetoothConstants.suffixLength))'")
        } else {
            peripheral.discoverCharacteristics(nil, for: self.service!)
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        if (error != nil) { // TODO: handle
            Logger.bluetooth.error("Central did not discoverCharacteristicsFor service '\(BluetoothConstants.getName(of: service.uuid))' on peripheral '\(peripheral.identifier.uuidString.suffix(BluetoothConstants.suffixLength))': '\(error!.localizedDescription)'")
        } else {
            guard let discoveredCharacteristics = service.characteristics else { // TODO: handle
                Logger.bluetooth.fault("The characteristics array of service '\(BluetoothConstants.getName(of: service.uuid))' on peripheral '\(peripheral.identifier.uuidString.suffix(BluetoothConstants.suffixLength)) is nil")
                return
            }
            Logger.bluetooth.debug("Central didDiscoverCharacteristicsFor service '\(BluetoothConstants.getName(of: service.uuid))' on peripheral '\(peripheral.identifier.uuidString.suffix(BluetoothConstants.suffixLength))', attempting to setNotifyValue")
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
                    Logger.bluetooth.trace("self.controlPoint = \(self.controlPoint)")
                    
                case BluetoothConstants.dataSourceUUID.uuidString:
                    discoveredAllCharacteristics[2] = true
                    Logger.bluetooth.trace("Central attempts to setNotifyValue of '\(BluetoothConstants.getName(of: characteristic.uuid))' to true")
                    peripheral.setNotifyValue(true, for: characteristic)
                default:
                    Logger.bluetooth.warning("Central discoverd unexpected characteristic for service '\(BluetoothConstants.getName(of: service.uuid))' on peripheral '\(peripheral.identifier.uuidString.suffix(BluetoothConstants.suffixLength))': '\(characteristic.uuid.uuidString)'")
                }
            }
            if !discoveredAllCharacteristics.allSatisfy({ $0 }) { // TODO: handle
                Logger.bluetooth.fault("Central did not discover all CharacteristicsFor service '\(BluetoothConstants.getName(of: service.uuid))' on peripheral '\(peripheral.identifier.uuidString.suffix(BluetoothConstants.suffixLength))': \(discoveredAllCharacteristics)")
            } else {
                Logger.bluetooth.notice("Central did discover all CharacteristicsFor service '\(BluetoothConstants.getName(of: service.uuid))' on peripheral '\(peripheral.identifier.uuidString.suffix(BluetoothConstants.suffixLength))': \(discoveredAllCharacteristics)")
            }
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        if (error != nil) { // TODO: handle
            Logger.bluetooth.fault("Central did not receive UpdateValueFor characteristic '\(BluetoothConstants.getName(of: characteristic.uuid))' on peripheral '\(peripheral.identifier.uuidString.suffix(BluetoothConstants.suffixLength))': '\(error!.localizedDescription)'")
        } else {
            guard let data = characteristic.value else { // TODO: handle
                Logger.bluetooth.fault("The value property of characteristic '\(BluetoothConstants.getName(of: characteristic.uuid))' on peripheral '\(peripheral.identifier.uuidString.suffix(BluetoothConstants.suffixLength)) is nil")
                return
            }
            Logger.bluetooth.debug("Central did receive UpdateValueFor characteristic \(BluetoothConstants.getName(of: characteristic.uuid)) on peripheral '\(peripheral.identifier.uuidString.suffix(BluetoothConstants.suffixLength))': '\(data)'")
            if characteristic.uuid.uuidString == BluetoothConstants.notificationSourceUUID.uuidString {
                handleNotificationSourceUpdate(peripheral: peripheral, data: data)
            } else if characteristic.uuid.uuidString == BluetoothConstants.dataSourceUUID.uuidString {
                handleDataSourceUpdate(peripheral: peripheral, data: data)
            }
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        if (error != nil) { // TODO: handle
            Logger.bluetooth.fault("Central did not WriteValueFor characteristic '\(BluetoothConstants.getName(of: characteristic.uuid))' on peripheral '\(peripheral.identifier.uuidString.suffix(BluetoothConstants.suffixLength))': '\(error!.localizedDescription)'")
        } else {
            Logger.bluetooth.notice("Central didWriteValueFor characteristic \(BluetoothConstants.getName(of: characteristic.uuid)) on peripheral '\(peripheral.identifier.uuidString.suffix(BluetoothConstants.suffixLength))'")
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        if (error != nil) { // TODO: handle
            Logger.bluetooth.fault("Central did not UpdateNotificationStateFor characteristic '\(BluetoothConstants.getName(of: characteristic.uuid))' on peripheral '\(peripheral.identifier.uuidString.suffix(BluetoothConstants.suffixLength))': '\(error!.localizedDescription)'")
        } else {
            Logger.bluetooth.notice("Central didUpdateNotificationStateFor characteristic '\(BluetoothConstants.getName(of: characteristic.uuid))' on peripheral '\(peripheral.identifier.uuidString.suffix(BluetoothConstants.suffixLength))' to \(characteristic.isNotifying)")
        }
    }
    
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, timestamp: CFAbsoluteTime, isReconnecting: Bool, error: (any Error)?) {
        if (error != nil) { // TODO: handle
            Logger.bluetooth.fault("Central did not DisconnectPeripheral '\(peripheral.identifier.uuidString.suffix(BluetoothConstants.suffixLength))': '\(error!.localizedDescription)'")
            if error!.localizedDescription == "The specified device has disconnected from us." { // TODO: needs better solution (connectionEvent?)
                self.peripheral = nil
                startScan()
            }
        } else {
            Logger.bluetooth.notice("Central didDisconnectPeripheral '\(peripheral.identifier.uuidString.suffix(BluetoothConstants.suffixLength))'")
            if isReconnecting {
                Logger.bluetooth.debug("Central isReconnecting to peripheral '\(peripheral.identifier.uuidString.suffix(BluetoothConstants.suffixLength))'")
            } else {
                self.peripheral = nil
                startScan()
            }
        }
    }
}
