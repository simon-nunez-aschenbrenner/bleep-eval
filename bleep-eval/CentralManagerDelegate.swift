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
    let notificationSourceUUID = BluetoothConstants.notificationSourceUUID
    let notificationAcknowledgementUUID = BluetoothConstants.notificationAcknowledgementUUID
    
    var peripheral: CBPeripheral? // TODO: multiple peripherals
    var notificationAcknowledgement: CBCharacteristic?
    
    var recentIdentifiers: [String] = [] // TODO: should be property of the connectionManager
    
    // MARK: initializing methods
            
    init(notificationManager: NotificationManager, bluetoothManager: BluetoothManager) {
        super.init()
        self.notificationManager = notificationManager
        self.bluetoothManager = bluetoothManager
        self.centralManager = CBCentralManager(delegate: self, queue: nil, options: [CBCentralManagerOptionRestoreIdentifierKey: BluetoothConstants.centralIdentifierKey, CBCentralManagerOptionShowPowerAlertKey: true])
        Logger.central.trace("CentralManagerDelegate initialized")
    }
    
    deinit {
        Logger.peripheral.trace("CentralManagerDelegate deinitializes")
        centralManager.stopScan()
        if peripheral != nil { centralManager.cancelPeripheralConnection(peripheral!) }
    }
    
    // MARK: public methods
        
    func scan() {
        Logger.central.debug("CentralManager may attempt to \(#function): centralManagerState is \(self.centralManager.state == .poweredOn ? "poweredOn" : "NOT poweredOn") and connectionManagerMode is \(self.bluetoothManager.mode.isConsumer ? "consumer" : "NOT consumer")")
        if centralManager.isScanning {
            Logger.central.trace("CentralManager is already scanning and attempts to stopScan")
            centralManager.stopScan()
        }
        if centralManager.state == .poweredOn && bluetoothManager.mode.isConsumer {
            centralManager.registerForConnectionEvents()
            Logger.central.debug("Central attempts to \(#function) for peripherals with service '\(getName(of: self.serviceUUID))'")
            centralManager.scanForPeripherals(withServices: [self.serviceUUID], options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
            centralManager.isScanning ? Logger.central.info("Central started scanning") : Logger.central.warning("Central did not start scanning") // TODO: handle?
        } else { // TODO: handle?
            Logger.central.warning("Central won't attempt to \(#function)")
        }

    }
    
    // MARK: delegate methods
    
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            Logger.central.debug("\(#function) to 'poweredOn'")
            scan()
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
        scan()
    }
    
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        Logger.central.info("Central didDiscover peripheral '\(printID(peripheral.identifier.uuidString))' (RSSI: \(RSSI.intValue)) and attempts to connect to it")
        guard let identifier = advertisementData[CBAdvertisementDataLocalNameKey] as? String else {
            Logger.central.error("Central will ignore peripheral '\(printID(peripheral.identifier.uuidString))' as did not advertise an identifier")
            return
        }
        guard !recentIdentifiers.contains(identifier) else {
            Logger.central.warning("Central will ignore peripheral '\(printID(peripheral.identifier.uuidString))' as it has been connected recently")
            return
        }
        Logger.central.debug("Central appends identifier '\(identifier)' of peripheral '\(printID(peripheral.identifier.uuidString)) to the recentIdentifiers array")
        recentIdentifiers.append(identifier)
        self.peripheral = peripheral
        peripheral.delegate = self
        notificationAcknowledgement = nil
        centralManager.stopScan()
        centralManager.connect(peripheral, options: nil)
    }
    
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        Logger.central.debug("Central didConnect to peripheral '\(printID(peripheral.identifier.uuidString))' and attempts to discoverServices")
        peripheral.discoverServices([self.serviceUUID])
    }
    
    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        Logger.central.warning("Central didFailToConnect to peripheral '\(printID(peripheral.identifier.uuidString))': '\(error?.localizedDescription ?? "")'")
        notificationManager.decide()
    }
    
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: (any Error)?) {
        if (error != nil) { // TODO: handle
            Logger.central.error("Central did not didDiscoverServices on peripheral '\(printID(peripheral.identifier.uuidString))': '\(error!.localizedDescription)'")
        } else {
            Logger.central.debug("Central didDiscoverServices on peripheral '\(printID(peripheral.identifier.uuidString))' and may attempt to discoverCharacteristics")
            guard let discoveredServices = peripheral.services else { // TODO: handle
                Logger.central.fault("Central can't discoverCharacteristics, because the services array of peripheral '\(printID(peripheral.identifier.uuidString))' is nil")
                return
            }
            var discoveredService = false
            for service in discoveredServices {
                Logger.central.trace("Central discovered '\(getName(of: service.uuid))'")
                if service.uuid.uuidString == self.serviceUUID.uuidString {
                    Logger.central.trace("Central attempts to discoverCharacteristics")
                    discoveredService = true
                    peripheral.discoverCharacteristics(nil, for: service)
                }
            }
            if !discoveredService { // TODO: handle
                Logger.central.error("Central can't discoverCharacteristics, because it did not discover '\(getName(of: self.serviceUUID))' on peripheral '\(printID(peripheral.identifier.uuidString))'")
//                centralManager.cancelPeripheralConnection(peripheral)
            }
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didModifyServices invalidatedServices: [CBService]) { // TODO: handle
        Logger.central.error("\(#function) invalidatedServices: \(invalidatedServices)")
        centralManager.cancelPeripheralConnection(peripheral)
    }
    
    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        if (error != nil) { // TODO: handle
            Logger.central.error("Central did not discoverCharacteristicsFor '\(getName(of: service.uuid))' on peripheral '\(printID(peripheral.identifier.uuidString))': '\(error!.localizedDescription)'")
        } else {
            Logger.central.debug("Central didDiscoverCharacteristicsFor '\(getName(of: service.uuid))' on peripheral '\(printID(peripheral.identifier.uuidString))' and may attempt to setNotifyValue")
            guard let discoveredCharacteristics = service.characteristics else { // TODO: handle
                Logger.central.fault("Central can't setNotifyValue because the characteristics array for '\(getName(of: service.uuid))' on peripheral '\(printID(peripheral.identifier.uuidString)) is nil")
                return
            }
            var discoveredNotificationSourceCharacteristic = false
            for characteristic in discoveredCharacteristics {
                Logger.central.trace("Central discovered '\(getName(of: characteristic.uuid))'")
                if characteristic.uuid.uuidString == self.notificationSourceUUID.uuidString {
                    Logger.central.debug("Central attempts to setNotifyValue for '\(getName(of: characteristic.uuid))'")
                    discoveredNotificationSourceCharacteristic = true
                    peripheral.setNotifyValue(true, for: characteristic)
                } else if characteristic.uuid.uuidString == self.notificationAcknowledgementUUID.uuidString {
                    self.notificationAcknowledgement = characteristic
                    Logger.central.debug("Central added '\(getName(of: characteristic.uuid))'")
                }
            }
            if self.notificationAcknowledgement == nil { // TODO: handle
                Logger.central.warning("Central did not discover '\(getName(of: self.notificationAcknowledgementUUID))' for '\(getName(of: service.uuid))' on peripheral '\(printID(peripheral.identifier.uuidString))'")
            }
            if !discoveredNotificationSourceCharacteristic { // TODO: handle
                Logger.central.error("Central can't attempt to setNotifyValue, because it did not discover '\(getName(of: self.notificationSourceUUID))' for '\(getName(of: service.uuid))' on peripheral '\(printID(peripheral.identifier.uuidString))'")
//                centralManager.cancelPeripheralConnection(peripheral)
            } else {
                Logger.central.info("Central successfully subscribed to '\(getName(of: self.notificationSourceUUID))' for '\(getName(of: service.uuid))' on peripheral '\(printID(peripheral.identifier.uuidString))'")
            }
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        if (error != nil) { // TODO: handle
            Logger.central.error("Central did not receive UpdateValueFor '\(getName(of: characteristic.uuid))' on peripheral '\(printID(peripheral.identifier.uuidString))': '\(error!.localizedDescription)'")
        } else {
            guard let data = characteristic.value else { // TODO: handle
                Logger.central.error("Central can't handleNotificationSourceUpdate, because value property of characteristic '\(getName(of: characteristic.uuid))' on peripheral '\(printID(peripheral.identifier.uuidString)) is nil")
                return
            }
            Logger.central.debug("Central did receive UpdateValueFor '\(getName(of: characteristic.uuid))' on peripheral '\(printID(peripheral.identifier.uuidString))' with \(data.count-minNotificationLength)+\(minNotificationLength)=\(data.count) bytes")
            if characteristic.uuid.uuidString == self.notificationSourceUUID.uuidString {
                notificationManager.receiveNotification(data: data)
            } else {
                Logger.central.warning("Central did receive UpdateValueFor unknown characteristic \(getName(of: characteristic.uuid))")
            }
        }
    }
    
    // TODO: needed?
    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        if (error != nil) { // TODO: handle
            Logger.central.error("Central did not receive WriteValueFor '\(getName(of: characteristic.uuid))' on peripheral '\(printID(peripheral.identifier.uuidString))': '\(error!.localizedDescription)'")
        } else {
            Logger.central.warning("Central did receive WriteValueFor \(getName(of: characteristic.uuid)) on peripheral '\(printID(peripheral.identifier.uuidString))'")
        }
    }

    // TODO: needed?
    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        if (error != nil) { // TODO: handle
            Logger.central.error("Central did not receive UpdateNotificationStateFor '\(getName(of: characteristic.uuid))': '\(error!.localizedDescription)' on peripheral '\(printID(peripheral.identifier.uuidString))'")
        } else {
            Logger.central.debug("Central did receive UpdateNotificationStateFor '\(getName(of: characteristic.uuid))' to \(characteristic.isNotifying) on peripheral '\(printID(peripheral.identifier.uuidString))'")
        }
    }
    
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, timestamp: CFAbsoluteTime, isReconnecting: Bool, error: (any Error)?) {
        if (error != nil) { // TODO: handle
            Logger.central.error("Central did not disconnectPeripheral '\(printID(peripheral.identifier.uuidString))': '\(error!.localizedDescription)'")
        } else {
            Logger.central.info("Central didDisconnectPeripheral '\(printID(peripheral.identifier.uuidString))'")
            isReconnecting ? Logger.central.warning("Central isReconnecting to peripheral '\(printID(peripheral.identifier.uuidString))'") : notificationManager.decide()
        }
    }
    
    func centralManager(_ central: CBCentralManager, connectionEventDidOccur event: CBConnectionEvent, for peripheral: CBPeripheral) {
        Logger.central.info("\(#function) peripheral '\(printID(peripheral.identifier.uuidString)): \(event.description)'")
        switch event {
        case .peerDisconnected:
            notificationManager.decide()
        case .peerConnected:
            return
        @unknown default:
            return
        }
    }
}

extension CBConnectionEvent: CustomStringConvertible {
    
    public var description: String {
        switch self {
        case .peerConnected: return "connected"
        case .peerDisconnected: return "disconnected"
        @unknown default: return "connectionEvent unknown"
        }
    }
}
