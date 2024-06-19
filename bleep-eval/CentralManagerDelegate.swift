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
    
    let serviceUUID = BluetoothConstants.serviceUUID
    let characteristicUUID = BluetoothConstants.notificationSourceUUID
    
    var peripheral: CBPeripheral? // TODO: multiple peripherals
    var storedNotificationHashedIDs: [Data] = []
    
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
        Logger.peripheral.trace("Central may attempt to \(#function)")
        if centralManager.isScanning {
            Logger.peripheral.debug("Central is already scanning")
        } else if centralManager.state == .poweredOn && bluetoothManager.mode.isConsumer && peripheral == nil {
            Logger.central.debug("Central attempts to \(#function) for peripherals with service '\(getName(of: self.serviceUUID))'")
            centralManager.scanForPeripherals(withServices: [self.serviceUUID], options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
        } else {
            Logger.central.info("Central won't attempt to \(#function)")
            Logger.central.debug("CentralState is \(self.centralManager.state == .poweredOn ? "poweredOn" : "NOT poweredOn"), BluetoothMode is \(self.bluetoothManager.mode.isConsumer ? "central" : "NOT central") or Peripheral property is \(self.peripheral == nil ? "nil" : "NOT nil")")
            if peripheral != nil {
                () // TODO: ?
            }
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
        Logger.central.debug("Central attempts to \(#function) from peripheral '\(printID(peripheral.identifier.uuidString))' with \(data.count-minMessageLength)+\(minMessageLength)=\(data.count) bytes")
        guard data.count >= minMessageLength else { // TODO: handle
            Logger.central.warning("Central will ignore notificationSourceUpdate from peripheral '\(printID(peripheral.identifier.uuidString))' with \(data.count) bytes as it's not at least \(minMessageLength) bytes long")
            return
        }
        let controlByte = ControlByte(value: UInt8(data[0]))
        if controlByte.destinationControlValue == 0 { // TODO: Needs timeout solution as well, so we are not dependent on the peripheral to disconnect and clear the Queue
            Logger.central.info("NotificationSourceUpdate from peripheral '\(printID(peripheral.identifier.uuidString))' indicates no more notifications")
            notificationManager.save()
            disconnect(from: peripheral)
        } else if controlByte.value <= maxSupportedControlByteValue(for: notificationManager.self) {
            let hashedID = data.subdata(in: 1..<33)
            Logger.central.trace("Central checks if there's already a notification #\(printID(hashedID)) in storage")
            if storedNotificationHashedIDs.contains(hashedID) {
                Logger.central.info("Central will ignore notificationSourceUpdate #\(printID(hashedID)) from peripheral '\(printID(peripheral.identifier.uuidString))' as this notification is already stored")
                return
            }
            let hashedDestinationAddress = data.subdata(in: 33..<65)
            if controlByte.destinationControlValue == 2 && !(hashedDestinationAddress == Address.Broadcast.hashed || hashedDestinationAddress == notificationManager.address.hashed) {
                Logger.central.info("Central will ignore notificationSourceUpdate #\(printID(hashedID)), as its hashedDestinationAddress '\(printID(hashedDestinationAddress))' doesn't match this notificationManager's hashed address '\(printID(self.notificationManager.address.hashed))' or the hashed broadcast address '\(printID(Address.Broadcast.hashed))'")
                return
            }
            let hashedSourceAddress = data.subdata(in: 65..<97)
            let sentTimestampData = data.subdata(in: 97..<105)
            let messageData = data.subdata(in: 105..<data.count)
            let message: String = String(data: messageData, encoding: .utf8) ?? ""
            let notification = Notification(controlByte: controlByte, hashedID: hashedID, hashedDestinationAddress: hashedDestinationAddress, hashedSourceAddress: hashedSourceAddress, sentTimestampData: sentTimestampData, message: message)
            notificationManager.insert(notification, andSave: false)
            storedNotificationHashedIDs.append(notification.hashedID)
            Logger.peripheral.info("Central successfully received notification #\(printID(notification.hashedID)) with message: '\(notification.message)'")
            if hashedDestinationAddress == Address.Broadcast.hashed || hashedDestinationAddress == notificationManager.address.hashed {
                notificationManager.updateView(with: notification)
            }
        }
    }
    
    // MARK: delegate methods
    
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            Logger.central.debug("\(#function) to 'poweredOn'")
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
        Logger.central.trace("\(#function)")
        startScan()
    }
    
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        Logger.central.info("Central didDiscover peripheral '\(printID(peripheral.identifier.uuidString))' (RSSI: \(RSSI.intValue)) and attempts to connect to it")
        self.peripheral = peripheral
        peripheral.delegate = self
        stopScan()
        storedNotificationHashedIDs = notificationManager.fetchAllHashedIDs() ?? []
        centralManager.connect(peripheral, options: nil)
    }
    
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        Logger.central.debug("Central didConnect to peripheral '\(printID(peripheral.identifier.uuidString))' and attempts to discoverServices, including '\(getName(of: self.serviceUUID))'")
        peripheral.discoverServices([self.serviceUUID])
    }
    
    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) { // TODO: handle
        Logger.central.error("Central didFailToConnect to peripheral '\(printID(peripheral.identifier.uuidString))': '\(error?.localizedDescription ?? "")'")
        startScan()
    }
    
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: (any Error)?) {
        if (error != nil) { // TODO: handle
            Logger.central.error("Central did not didDiscoverServices on peripheral '\(printID(peripheral.identifier.uuidString))': '\(error!.localizedDescription)'")
        } else {
            Logger.central.debug("Central didDiscoverServices on peripheral '\(printID(peripheral.identifier.uuidString))' and attempts to discoverCharacteristics of service '\(getName(of: self.serviceUUID))'")
            guard let discoveredServices = peripheral.services else { // TODO: handle
                Logger.central.fault("Central can't discoverCharacteristics, because the services array of peripheral '\(printID(peripheral.identifier.uuidString))' is nil")
                return
            }
            var discoveredService = false
            for service in discoveredServices {
                Logger.central.trace("Central discovered service '\(getName(of: service.uuid))' on peripheral '\(printID(peripheral.identifier.uuidString))'")
                if service.uuid.uuidString == self.serviceUUID.uuidString {
                    discoveredService = true
                    peripheral.discoverCharacteristics(nil, for: service)
                }
            }
            if !discoveredService { // TODO: handle
                Logger.central.error("Central can't discoverCharacteristics, because it did not discover service '\(getName(of: self.serviceUUID))' on peripheral '\(printID(peripheral.identifier.uuidString))'")
                disconnect(from: peripheral)
                startScan()
            }
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        if (error != nil) { // TODO: handle
            Logger.central.error("Central did not discoverCharacteristicsFor service '\(getName(of: service.uuid))' on peripheral '\(printID(peripheral.identifier.uuidString))': '\(error!.localizedDescription)'")
        } else {
            guard let discoveredCharacteristics = service.characteristics else { // TODO: handle
                Logger.central.error("Central can't setNotifyValue because the characteristics array of service '\(getName(of: service.uuid))' on peripheral '\(printID(peripheral.identifier.uuidString)) is nil")
                return
            }
            Logger.central.debug("Central didDiscoverCharacteristicsFor service '\(getName(of: service.uuid))' on peripheral '\(printID(peripheral.identifier.uuidString))' and attempts to setNotifyValue")
            var discoveredCharacteristic = false
            for characteristic in discoveredCharacteristics {
                Logger.central.trace("Central discovered characteristic '\(getName(of: characteristic.uuid))'")
                if characteristic.uuid.uuidString == self.characteristicUUID.uuidString {
                    discoveredCharacteristic = true
                    Logger.central.trace("Central attempts to setNotifyValue of '\(getName(of: characteristic.uuid))' to true")
                    peripheral.setNotifyValue(true, for: characteristic)
                }
            }
            if !discoveredCharacteristic { // TODO: handle
                Logger.central.error("Central can't attempt to setNotifyValue, because it did not discover characteristic '\(getName(of: self.characteristicUUID))' on peripheral '\(printID(peripheral.identifier.uuidString))'")
                disconnect(from: peripheral)
                startScan()
            }
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        if (error != nil) { // TODO: handle
            Logger.central.error("Central did not receive UpdateValueFor characteristic '\(getName(of: characteristic.uuid))' on peripheral '\(printID(peripheral.identifier.uuidString))': '\(error!.localizedDescription)'")
        } else {
            guard let data = characteristic.value else { // TODO: handle
                Logger.central.error("Central can't handleNotificationSourceUpdate, because value property of characteristic '\(getName(of: characteristic.uuid))' on peripheral '\(printID(peripheral.identifier.uuidString)) is nil")
                return
            }
            Logger.central.debug("Central did receive UpdateValueFor characteristic \(getName(of: characteristic.uuid)) on peripheral '\(printID(peripheral.identifier.uuidString))' with \(data.count-minMessageLength)+\(minMessageLength)=\(data.count) bytes")
            if characteristic.uuid.uuidString == self.characteristicUUID.uuidString {
                handleNotificationSourceUpdate(peripheral: peripheral, data: data)
            } else {
                Logger.central.warning("Central did receive UpdateValueFor unknown characteristic \(getName(of: characteristic.uuid))")
            }
        }
    }
    
//    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
//        if (error != nil) { // TODO: handle
//            Logger.central.fault("Central did not WriteValueFor characteristic '\(getName(of: characteristic.uuid))' on peripheral '\(printID(peripheral.identifier.uuidString))': '\(error!.localizedDescription)'")
//        } else {
//            Logger.central.info("Central didWriteValueFor characteristic \(getName(of: characteristic.uuid)) on peripheral '\(printID(peripheral.identifier.uuidString))'")
//        }
//    }
    
    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        if (error != nil) { // TODO: handle
            Logger.central.error("Central did not UpdateNotificationStateFor characteristic '\(getName(of: characteristic.uuid))' on peripheral '\(printID(peripheral.identifier.uuidString))': '\(error!.localizedDescription)'")
        } else {
            Logger.central.debug("Central didUpdateNotificationStateFor characteristic '\(getName(of: characteristic.uuid))' on peripheral '\(printID(peripheral.identifier.uuidString))' to \(characteristic.isNotifying)")
        }
    }
    
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, timestamp: CFAbsoluteTime, isReconnecting: Bool, error: (any Error)?) {
        if (error != nil) { // TODO: handle
            Logger.central.error("Central did not DisconnectPeripheral '\(printID(peripheral.identifier.uuidString))': '\(error!.localizedDescription)'")
            if error!.localizedDescription == "The specified device has disconnected from us." { // TODO: needs better solution (connectionEvent?)
                self.peripheral = nil
                startScan()
            }
        } else {
            Logger.central.info("Central didDisconnectPeripheral '\(printID(peripheral.identifier.uuidString))'")
            if isReconnecting {
                Logger.central.debug("Central isReconnecting to peripheral '\(printID(peripheral.identifier.uuidString))'")
            } else {
                self.peripheral = nil
                startScan()
            }
        }
    }
}
