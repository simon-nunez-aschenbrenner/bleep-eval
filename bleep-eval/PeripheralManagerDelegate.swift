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
    var central: CBCentral?
    
    var notificationCounter: UInt32 = 0 // TODO: count notifications dict?
    var notifications: [UInt32: Notification] = [:]
        
    // MARK: initializing methods
    
    init(bluetoothManager: BluetoothManager) {
        super.init()
        self.bluetoothManager = bluetoothManager
        self.peripheralManager = CBPeripheralManager(delegate: self, queue: nil, options: [CBPeripheralManagerOptionRestoreIdentifierKey: BluetoothConstants.peripheralIdentifierKey, CBPeripheralManagerOptionShowPowerAlertKey: true])
        Logger.bluetooth.trace("PeripheralManagerDelegate initialized")
    }
    
    // MARK: public methods
    
    func startAdvertising() {
        Logger.bluetooth.debug("Peripheral attempts to \(#function) as '\(BluetoothConstants.peripheralName)' with service '\(BluetoothConstants.getName(of: self.bluetoothManager.service.uuid))' to centrals")
        peripheralManager.startAdvertising([CBAdvertisementDataServiceUUIDsKey: [self.bluetoothManager.service.uuid], CBAdvertisementDataLocalNameKey: BluetoothConstants.peripheralName])
    }
    
    func stopAdvertising() {
        Logger.bluetooth.trace("Peripheral attempts to \(#function)")
        peripheralManager.isAdvertising ? peripheralManager.stopAdvertising() : Logger.bluetooth.trace("Peripheral was not advertising")
    }
    
    func sendNotification(_ notification: Notification) {
        Logger.bluetooth.debug("Peripheral attempts to \(#function) #\(notification.notificationID)")
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
        Logger.bluetooth.debug("Peripheral attempts to updateValue of '\(BluetoothConstants.getName(of: self.bluetoothManager.notificationSource.uuid))' with: '\(data.map { String($0) }.joined(separator: " "))'")
        peripheralManager.updateValue(data, for: bluetoothManager.notificationSource, onSubscribedCentrals: nil)
    }
    
    private func handleControlPointWrite(request: CBATTRequest) {
        Logger.bluetooth.debug("Peripheral attempts to \(#function) from central '\(request.central.identifier.uuidString.suffix(BluetoothConstants.UUIDSuffixLength))'")
        guard let data = request.value else { // TODO: handle
            Logger.bluetooth.fault("ControlPointWrite command from central '\(request.central.identifier.uuidString.suffix(BluetoothConstants.UUIDSuffixLength))' is nil")
            return
        }
        guard data.count == 6 else { // TODO: handle
            Logger.bluetooth.fault("ControlPointWrite command from central '\(request.central.identifier.uuidString.suffix(BluetoothConstants.UUIDSuffixLength))' not 6 bytes long: '\(data.map { String($0) }.joined(separator: " "))'")
            return
        }
        if data[0] == 0 { // TODO: handle other CommandIDs
            let notificationIDData = data.subdata(in: 1..<5)
            let notificationID: UInt32 = notificationIDData.withUnsafeBytes { $0.load(as: UInt32.self) }
            let attributeID = Int(data[5]) // TODO: handle multiple attributes
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
        peripheralManager.updateValue(data, for: bluetoothManager.dataSource, onSubscribedCentrals: nil)
    }

    // MARK: delegate methods
    
    func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        switch peripheral.state {
        case .poweredOn:
            Logger.bluetooth.notice("\(#function) to 'poweredOn'")
            peripheralManager.add(bluetoothManager.service)
            if bluetoothManager.mode == .peripheral && !peripheralManager.isAdvertising {
                startAdvertising()
            }
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
        Logger.bluetooth.trace("In \(#function)")
        self.peripheralManager = peripheral
        peripheral.delegate = self
        if bluetoothManager.mode == .peripheral && !peripheralManager.isAdvertising {
            startAdvertising()
        }
    }
    
    func peripheralManager(_ peripheral: CBPeripheralManager, central: CBCentral, didSubscribeTo characteristic: CBCharacteristic) {
        Logger.bluetooth.info("Central '\(central.identifier.uuidString.suffix(BluetoothConstants.UUIDSuffixLength))' didSubscribeTo characteristic '\(BluetoothConstants.getName(of: characteristic.uuid))'")
        stopAdvertising()
    }
    
    func peripheralManager(_ peripheral: CBPeripheralManager, central: CBCentral, didUnsubscribeFrom characteristic: CBCharacteristic) {
        Logger.bluetooth.info("Central '\(central.identifier.uuidString.suffix(BluetoothConstants.UUIDSuffixLength))' didUnsubscribeFrom characteristic '\(BluetoothConstants.getName(of: characteristic.uuid))'")
        if bluetoothManager.mode == .peripheral && !peripheralManager.isAdvertising {
            startAdvertising()
        }
    }
    
    func peripheralManagerIsReady(toUpdateSubscribers peripheral: CBPeripheralManager) {
        Logger.bluetooth.notice("\(#function):toUpdateSubscribers") // TODO: handle
    }
    
    func peripheralManagerDidStartAdvertising(_ peripheral: CBPeripheralManager, error: (any Error)?) {
        if (error != nil) { // TODO: handle
            Logger.bluetooth.fault("Peripheral did not start advertising: \(error!.localizedDescription)")
        } else {
            Logger.bluetooth.notice("Peripheral started advertising")
        }
    }
    
    func peripheralManager(_ peripheral: CBPeripheralManager, didAdd service: CBService, error: (any Error)?) {
        if (error != nil) { // TODO: handle
            Logger.bluetooth.fault("Peripheral did not add service '\(BluetoothConstants.getName(of: service.uuid))': \(error!.localizedDescription)")
        } else {
            Logger.bluetooth.info("Peripheral added service '\(BluetoothConstants.getName(of: service.uuid))'")
        }
    }
}
