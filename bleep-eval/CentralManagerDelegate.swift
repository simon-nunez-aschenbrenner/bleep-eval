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
    var peripheral: CBPeripheral? // TODO: list
    
    var notifications: [UInt32: Notification] = [:] // TODO: for each peripheral
    
    // MARK: initializing methods
            
    init(bluetoothManager: BluetoothManager) {
        super.init()
        self.bluetoothManager = bluetoothManager
        self.centralManager = CBCentralManager(delegate: self, queue: nil, options: [CBCentralManagerOptionRestoreIdentifierKey: BluetoothConstants.centralIdentifierKey, CBCentralManagerOptionShowPowerAlertKey: true])
        Logger.bluetooth.trace("CentralManagerDelegate initialized")
    }
    
    // MARK: public methods
        
    func startScan() {
        Logger.bluetooth.debug("Central attempts to \(#function) for peripherals with service '\(BluetoothConstants.getName(of: self.bluetoothManager.service.uuid))'")
        centralManager.scanForPeripherals(withServices: [self.bluetoothManager.service.uuid], options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
    }
    
    func stopScan() {
        Logger.bluetooth.trace("Central attempts to \(#function)")
        centralManager.isScanning ? centralManager.stopScan() : Logger.bluetooth.trace("Central was not scanning")
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
        peripheral.writeValue(data, for: bluetoothManager.controlPoint, type: .withResponse)
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
            notifications[notificationID]?.attributes[attributeID] = attribute // TODO: test with different attributeIDs
        }
    }
    
    // MARK: delegate methods
    
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            Logger.bluetooth.notice("\(#function) to 'poweredOn'")
            if bluetoothManager.mode == .central && !centralManager.isScanning {
                startScan()
            }
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
        self.centralManager = central
        central.delegate = self
        if bluetoothManager.mode == .central && !self.centralManager.isScanning {
            startScan()
        }
    }
    
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        Logger.bluetooth.info("Central didDiscover peripheral '\(peripheral.identifier.uuidString.suffix(BluetoothConstants.UUIDSuffixLength))' (RSSI: \(RSSI.intValue)) and attempts to connect to it")
        self.peripheral = peripheral
        peripheral.delegate = self
        centralManager.stopScan()
        centralManager.connect(peripheral, options: nil)
    }
    
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        Logger.bluetooth.notice("Central didConnect to peripheral '\(peripheral.identifier.uuidString.suffix(BluetoothConstants.UUIDSuffixLength))' and attempts to discoverCharacteristics")
        let characteristicUUIDs = [bluetoothManager.notificationSource.uuid, bluetoothManager.controlPoint.uuid, bluetoothManager.dataSource.uuid]
        peripheral.discoverCharacteristics(characteristicUUIDs, for: bluetoothManager.service)
    }
    
    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) { // TODO: handle
        Logger.bluetooth.error("Central didFailToConnect to peripheral '\(peripheral.identifier.uuidString.suffix(BluetoothConstants.UUIDSuffixLength))': '\(error?.localizedDescription ?? "")'")
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
            for characteristic in discoveredCharacteristics {
                if characteristic.uuid.uuidString == bluetoothManager.notificationSource.uuid.uuidString || characteristic.uuid.uuidString == bluetoothManager.dataSource.uuid.uuidString {
                    Logger.bluetooth.trace("setNotifyValue of '\(BluetoothConstants.getName(of: characteristic.uuid))' to true")
                    peripheral.setNotifyValue(true, for: characteristic)
                }
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
            if characteristic.uuid.uuidString == bluetoothManager.notificationSource.uuid.uuidString {
                handleNotificationSourceUpdate(peripheral: peripheral, data: data)
            } else if characteristic.uuid.uuidString == bluetoothManager.dataSource.uuid.uuidString {
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
        } else {
            Logger.bluetooth.notice("Central didDisconnectPeripheral '\(peripheral.identifier.uuidString.suffix(BluetoothConstants.UUIDSuffixLength))'")
            if isReconnecting {
                Logger.bluetooth.debug("Central isReconnecting to peripheral '\(peripheral.identifier.uuidString.suffix(BluetoothConstants.UUIDSuffixLength))'")
            } else {
                !centralManager.isScanning ? startScan() : () // TODO: only when we're no longer connected to any peripheral
            }
        }
    }
}
