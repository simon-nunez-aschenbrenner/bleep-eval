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
    var notifications: [UInt16: Notification] = [:] // TODO: for each central? // TODO: rolling queue, list?
        
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
        Logger.bluetooth.trace("PeripheralManagerDelegate initialized")
    }
    
    // MARK: public methods
    
    func startAdvertising() {
        if peripheralManager.state == .poweredOn && bluetoothManager.modeIsPeripheral && central == nil {
            Logger.bluetooth.debug("Peripheral attempts to \(#function) as '\(BluetoothConstants.peripheralName)' with service '\(BluetoothConstants.getName(of: self.service.uuid))' to centrals")
            peripheralManager.startAdvertising([CBAdvertisementDataServiceUUIDsKey: [self.service.uuid], CBAdvertisementDataLocalNameKey: BluetoothConstants.peripheralName])
        } else { // TODO: handle
            Logger.bluetooth.warning("Peripheral won't attempt to \(#function): PeripheralState is \(self.peripheralManager.state == .poweredOn ? "poweredOn" : "not poweredOn"), BluetoothMode is \(self.bluetoothManager.modeIsPeripheral ? "peripheral" : "not peripheral"), Central property is \(self.central == nil ? "nil" : "not nil")")
        }
    }
    
    func stopAdvertising() {
        Logger.bluetooth.trace("Peripheral attempts to \(#function)")
        peripheralManager.isAdvertising ? peripheralManager.stopAdvertising() : Logger.bluetooth.trace("Peripheral was not advertising")
    }
    
    func sendNotification(_ notification: Notification) {
        Logger.bluetooth.debug("Peripheral attempts to \(#function) #\(notification.notificationID): '\(notification.message)'") // TODO: log other properties?
        notifications[notification.notificationID] = notification
        var data = Data()
        var notificationID = notification.notificationID.littleEndian
        withUnsafeBytes(of: &notificationID) { bytes in data.append(contentsOf: bytes) }
        data.append(notification.categoryID)
        var destinationAddress = notification.destinationAddress.rawValue.littleEndian
        withUnsafeBytes(of: &destinationAddress) { bytes in data.append(contentsOf: bytes) }
        Logger.bluetooth.debug("Peripheral attempts to updateValue of '\(BluetoothConstants.getName(of: self.notificationSource.uuid))' with: '\(data.map { String($0) }.joined(separator: " "))' (Length: \(data.count) bytes)")
        if peripheralManager.updateValue(data, for: self.notificationSource, onSubscribedCentrals: nil) {
            Logger.bluetooth.notice("Peripheral updated value for characteristic '\(BluetoothConstants.getName(of: self.notificationSource.uuid))' to '\(data.map { String($0) }.joined(separator: " "))' (Length: \(data.count) bytes)")
        } else {
            Logger.bluetooth.warning("Peripheral did not update value of characteristic '\(BluetoothConstants.getName(of: self.notificationSource.uuid)))' to '\(data.map { String($0) }.joined(separator: " "))' (Length: \(data.count) bytes)")
        }
    }
    
    // MARK: private methods
    
    private func handleControlPointWrite(peripheral: CBPeripheralManager, request: CBATTRequest) {
        if request.characteristic.uuid == self.controlPoint.uuid {
            Logger.bluetooth.trace("Peripheral attempts to handle controlPoint command")
            guard let data = request.value else {
                Logger.bluetooth.fault("ControlPoint command from central '\(request.central.identifier.uuidString.suffix(BluetoothConstants.suffixLength))' is nil")
                peripheral.respond(to: request, withResult: .attributeNotFound)
                return
            }
            guard data.count == 3 else { // TODO: handle
                Logger.bluetooth.fault("ControlPoint command from central '\(request.central.identifier.uuidString.suffix(BluetoothConstants.suffixLength))' is not 3 bytes long: '\(data.map { String($0) }.joined(separator: " "))' (Length: \(data.count) bytes)")
                peripheral.respond(to: request, withResult: .invalidAttributeValueLength)
                return
            }
            Logger.bluetooth.debug("ControlPoint command from central '\(request.central.identifier.uuidString.suffix(BluetoothConstants.suffixLength))' is: '\(data.map { String($0) }.joined(separator: " "))' (Length: \(data.count) bytes)")
            if data[2] == 0 { // TODO: handle other CommandIDs
                let notificationIDData = data.subdata(in: 0..<2)
                let notificationID: UInt16 = notificationIDData.withUnsafeBytes { $0.load(as: UInt16.self) }.littleEndian
                Logger.bluetooth.trace("Attempting to retrieve notification #\(notificationID)")
                sendData(notificationID: notificationID)
            }
            peripheralManager.respond(to: request, withResult: .success)
            peripheral.respond(to: request, withResult: .success)
        } else {
            Logger.bluetooth.error("Unexpected controlPoint command from central '\(request.central.identifier.uuidString.suffix(BluetoothConstants.suffixLength))': '\(String(data: request.value ?? Data(), encoding: .utf8) ?? "")'")
            peripheral.respond(to: request, withResult: .requestNotSupported)
        }
    }
    
    private func sendData(commandID: UInt8 = 0, notificationID: UInt16) {
        // TODO: handle other CommandIDs
        Logger.bluetooth.debug("Peripheral attempts to get Data of notification #\(notificationID)")
        guard let notification = notifications[notificationID] else { // TODO: handle
            Logger.bluetooth.error("Peripheral could not \(#function) of notification #\(notificationID) because the dictionary misses an entry for that ID")
            return
        }
        Logger.bluetooth.debug("Peripheral attempts to \(#function) of \(notification)")
        var data = Data()
        var notificationID = notification.notificationID.littleEndian
        withUnsafeBytes(of: &notificationID) { bytes in data.append(contentsOf: bytes) }
        data.append(notification.categoryID)
        var destinationAddress = notification.destinationAddress.rawValue.littleEndian
        withUnsafeBytes(of: &destinationAddress) { bytes in data.append(contentsOf: bytes) }
        var sourceAddress = notification.sourceAddress.rawValue.littleEndian
        withUnsafeBytes(of: &sourceAddress) { bytes in data.append(contentsOf: bytes) }
        var messageData = notification.message.data(using: .utf8) ?? Data()
        data.append(messageData)
        Logger.bluetooth.debug("Peripheral attempts to updateValue of '\(BluetoothConstants.getName(of: self.dataSource.uuid))' with: '\(data.map { String($0) }.joined(separator: " "))' (Length: \(data.count) bytes)")
        if peripheralManager.updateValue(data, for: self.dataSource, onSubscribedCentrals: nil) {
            Logger.bluetooth.notice("Peripheral updated value for characteristic '\(BluetoothConstants.getName(of: self.dataSource.uuid))' to '\(data.map { String($0) }.joined(separator: " "))' (Length: \(data.count) bytes)")
        } else {
            Logger.bluetooth.warning("Peripheral did not update value of characteristic '\(BluetoothConstants.getName(of: self.dataSource.uuid)))' to '\(data.map { String($0) }.joined(separator: " "))' (Length: \(data.count) bytes)")
        }
    }

    // MARK: delegate methods
    
    func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        switch peripheral.state {
        case .poweredOn:
            Logger.bluetooth.notice("\(#function) to 'poweredOn'")
            peripheralManager.removeAllServices()
            peripheralManager.add(self.service)
            startAdvertising()
        // TODO: handle other cases incl. authorization cases
        case .unknown:
            Logger.bluetooth.warning("\(#function) to 'unknown'")
        case .resetting:
            Logger.bluetooth.warning("\(#function): 'resetting'")
        case .unsupported:
            Logger.bluetooth.error("\(#function): 'unsupported'")
        case .unauthorized:
            Logger.bluetooth.error("\(#function): 'unauthorized'")
            Logger.bluetooth.error("CBManager authorization: \(CBPeripheralManager.authorization.rawValue)")
        case .poweredOff:
            Logger.bluetooth.error("\(#function): 'poweredOff'")
        @unknown default:
            Logger.bluetooth.error("\(#function) to not implemented state: \(peripheral.state.rawValue)")
        }
    }
    
    func peripheralManager(_ peripheral: CBPeripheralManager, willRestoreState dict: [String : Any]) {
        Logger.bluetooth.trace("In \(#function): \(dict)")
//        self.peripheralManager = peripheral
//        peripheral.delegate = self
        startAdvertising()
    }
    
    func peripheralManager(_ peripheral: CBPeripheralManager, didAdd service: CBService, error: (any Error)?) {
        if (error != nil) { // TODO: handle
            Logger.bluetooth.fault("Peripheral did not add service '\(BluetoothConstants.getName(of: service.uuid))': \(error!.localizedDescription)")
        } else {
            Logger.bluetooth.info("Peripheral added service '\(BluetoothConstants.getName(of: service.uuid))'")
        }
    }
    
    func peripheralManagerDidStartAdvertising(_ peripheral: CBPeripheralManager, error: (any Error)?) {
        if (error != nil) { // TODO: handle
            Logger.bluetooth.fault("Peripheral did not start advertising: \(error!.localizedDescription)")
        } else {
            Logger.bluetooth.notice("Peripheral started advertising")
        }
    }
    
    func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveWrite requests: [CBATTRequest]) { // TODO: Teile in private methode auslagern
        Logger.bluetooth.trace("Peripheral didReceiveWrite")
        for request in requests {
            handleControlPointWrite(peripheral: peripheral, request: request)
        }
    }
    
    func peripheralManager(_ peripheral: CBPeripheralManager, central: CBCentral, didSubscribeTo characteristic: CBCharacteristic) {
        Logger.bluetooth.info("Central '\(central.identifier.uuidString.suffix(BluetoothConstants.suffixLength))' didSubscribeTo characteristic '\(BluetoothConstants.getName(of: characteristic.uuid))'")
        self.central = central
        stopAdvertising()
        peripheralManager.setDesiredConnectionLatency(.low, for: central)
    }
    
    func peripheralManager(_ peripheral: CBPeripheralManager, central: CBCentral, didUnsubscribeFrom characteristic: CBCharacteristic) {
        Logger.bluetooth.info("Central '\(central.identifier.uuidString.suffix(BluetoothConstants.suffixLength))' didUnsubscribeFrom characteristic '\(BluetoothConstants.getName(of: characteristic.uuid))'")
        self.central = nil
        startAdvertising()
    }
    
    func peripheralManagerIsReady(toUpdateSubscribers peripheral: CBPeripheralManager) {
        Logger.bluetooth.notice("\(#function):toUpdateSubscribers") // TODO: handle
    }
}
