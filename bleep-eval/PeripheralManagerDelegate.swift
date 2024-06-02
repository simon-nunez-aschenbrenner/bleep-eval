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
    var notifications: [UInt32: Notification] = [:] // TODO: for each central? // TODO: rolling queue, list?
        
    // MARK: initializing methods
    
    init(bluetoothManager: BluetoothManager) {
        super.init()
        self.bluetoothManager = bluetoothManager
        self.peripheralManager = CBPeripheralManager(delegate: self, queue: nil, options: [CBPeripheralManagerOptionRestoreIdentifierKey: BluetoothConstants.peripheralIdentifierKey, CBPeripheralManagerOptionShowPowerAlertKey: true])
        self.service = CBMutableService(type: BluetoothConstants.serviceUUID, primary: true)
        self.notificationSource = CBMutableCharacteristic(type: BluetoothConstants.notificationSourceUUID, properties: [.notify], value: nil, permissions: [.readable])
        self.controlPoint = CBMutableCharacteristic(type: BluetoothConstants.controlPointUUID, properties: [.write], value: nil, permissions: [.writeable])
        self.dataSource = CBMutableCharacteristic(type: BluetoothConstants.dataSourceUUID, properties: [.notify], value: nil, permissions: [.readable])
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
        Logger.bluetooth.debug("Peripheral attempts to \(#function) #\(notification.notificationID): '\(notification.attributes[0])'") // TODO: all attributes
        // TODO: category count
        sendNotification(eventID: notification.eventID, eventFlags: notification.eventFlags, categoryID: notification.categoryID, categoryCount: 0, notificationID: notification.notificationID)
    }
    
    // MARK: private methods
    
    private func sendNotification(eventID: UInt8, eventFlags: UInt8, categoryID: UInt8, categoryCount: UInt8, notificationID: UInt32) {
        var data = Data()
        data.append(eventID)
        data.append(eventFlags)
        data.append(categoryID)
        data.append(categoryCount)
        var notificationID = notificationID
        withUnsafeBytes(of: &notificationID) { bytes in data.append(contentsOf: bytes) }
        Logger.bluetooth.debug("Peripheral attempts to updateValue of '\(BluetoothConstants.getName(of: self.notificationSource.uuid))' with: '\(data.map { String($0) }.joined(separator: " "))'")
        if peripheralManager.updateValue(data, for: self.notificationSource, onSubscribedCentrals: nil) {
            Logger.bluetooth.notice("Peripheral updated value for characteristic '\(BluetoothConstants.getName(of: self.notificationSource.uuid))' to '\(data.map { String($0) }.joined(separator: " "))'")
        } else {
            Logger.bluetooth.warning("Peripheral did not update value of characteristic '\(BluetoothConstants.getName(of: self.notificationSource.uuid)))' to '\(data.map { String($0) }.joined(separator: " "))'")
        }
    }
    
    private func handleControlPointWrite(request: CBATTRequest) {
        Logger.bluetooth.debug("Peripheral attempts to \(#function) from central '\(request.central.identifier.uuidString.suffix(BluetoothConstants.UUIDSuffixLength))'")
        guard let data = request.value else { // TODO: handle
            Logger.bluetooth.fault("ControlPointWrite command from central '\(request.central.identifier.uuidString.suffix(BluetoothConstants.UUIDSuffixLength))' is nil")
            return
        }
        guard data.count == 6 else { // TODO: handle
            Logger.bluetooth.fault("ControlPointWrite command from central '\(request.central.identifier.uuidString.suffix(BluetoothConstants.UUIDSuffixLength))' is not 6 bytes long: '\(data.map { String($0) }.joined(separator: " "))'")
            return
        }
        Logger.bluetooth.debug("ControlPointWrite command from central '\(request.central.identifier.uuidString.suffix(BluetoothConstants.UUIDSuffixLength))' is: '\(data.map { String($0) }.joined(separator: " "))'")
        if data[0] == 0 { // TODO: handle other CommandIDs
            let notificationIDData = data.subdata(in: 1..<5)
            let notificationID: UInt32 = notificationIDData.withUnsafeBytes { $0.load(as: UInt32.self) }
            let attributeID = Int(data[5]) // TODO: handle multiple attributes
            Logger.bluetooth.trace("Attempting to retrieve attribute #\(attributeID) of notification #\(notificationID)")
            let attribute: String = notifications[notificationID]?.attributes[attributeID] ?? ""
            sendData(notificationID: notificationID, attribute: attribute)
        }
        peripheralManager.respond(to: request, withResult: .success)
    }
    
    private func sendData(commandID: UInt8 = 0, notificationID: UInt32, attribute: String) { // TODO: handle multiple attributes
        Logger.bluetooth.debug("Peripheral attempts to \(#function) for notification #\(notificationID): '\(attribute)'")
        var data = Data()
        data.append(commandID)
        var notificationID = notificationID
        withUnsafeBytes(of: &notificationID) { bytes in data.append(contentsOf: bytes) }
        data.append(0) // AttributeID
        assert (attribute.count <= UInt16.max) // TODO: handle
        var attributeLength = UInt16(attribute.count)
        withUnsafeBytes(of: &attributeLength) { bytes in data.append(contentsOf: bytes) }
        var attribute = attribute
        withUnsafeBytes(of: &attribute) { bytes in data.append(contentsOf: bytes) }
        if peripheralManager.updateValue(data, for: self.dataSource, onSubscribedCentrals: nil) {
            Logger.bluetooth.notice("Peripheral updated value for characteristic '\(BluetoothConstants.getName(of: self.dataSource.uuid))' to '\(data.map { String($0) }.joined(separator: " "))'")
        } else {
            Logger.bluetooth.warning("Peripheral did not update value of characteristic '\(BluetoothConstants.getName(of: self.dataSource.uuid)))' to '\(data.map { String($0) }.joined(separator: " "))'")
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
    
    func peripheralManager(_ peripheral: CBPeripheralManager, central: CBCentral, didSubscribeTo characteristic: CBCharacteristic) {
        Logger.bluetooth.info("Central '\(central.identifier.uuidString.suffix(BluetoothConstants.UUIDSuffixLength))' didSubscribeTo characteristic '\(BluetoothConstants.getName(of: characteristic.uuid))'")
        self.central = central
        stopAdvertising()
    }
    
    func peripheralManager(_ peripheral: CBPeripheralManager, central: CBCentral, didUnsubscribeFrom characteristic: CBCharacteristic) {
        Logger.bluetooth.info("Central '\(central.identifier.uuidString.suffix(BluetoothConstants.UUIDSuffixLength))' didUnsubscribeFrom characteristic '\(BluetoothConstants.getName(of: characteristic.uuid))'")
        self.central = nil
        startAdvertising()
    }
    
    func peripheralManagerIsReady(toUpdateSubscribers peripheral: CBPeripheralManager) {
        Logger.bluetooth.notice("\(#function):toUpdateSubscribers") // TODO: handle
    }
}
