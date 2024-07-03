//
//  CentralManager.swift
//  bleep-eval
//
//  Created by Simon Núñez Aschenbrenner on 07.05.24.
//

import CoreBluetooth
import Foundation
import OSLog

@Observable
class CentralManagerDelegate: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate {
        
    unowned var notificationManager: NotificationManager!
    unowned var bluetoothManager: BluetoothManager!
    var centralManager: CBCentralManager!
    
    let serviceUUID = BluetoothManager.serviceUUID
    let notificationSourceUUID = BluetoothManager.notificationSourceUUID
    let notificationAcknowledgementUUID = BluetoothManager.notificationAcknowledgementUUID
    
    var peripheral: CBPeripheral? // TODO: multiple peripherals
    var notificationAcknowledgement: CBCharacteristic?
        
    // MARK: initializing methods
            
    init(notificationManager: NotificationManager, bluetoothManager: BluetoothManager) {
        super.init()
        self.notificationManager = notificationManager
        self.bluetoothManager = bluetoothManager
        self.centralManager = CBCentralManager(delegate: self, queue: nil, options: [CBCentralManagerOptionRestoreIdentifierKey: BluetoothManager.centralIdentifierKey, CBCentralManagerOptionShowPowerAlertKey: true])
        Logger.central.trace("CentralManagerDelegate initialized")
    }
    
    // MARK: public methods
        
    func scan() {
        Logger.central.debug("Central may attempt to \(#function)")
        guard peripheral == nil && centralManager.state == .poweredOn else {
            Logger.central.warning("Central won't attempt to \(#function): peripheral \(self.peripheral == nil ? "== nil" : "!= nil"), centralManager.state \(self.centralManager.state == .poweredOn ? "== poweredOn" : "!= poweredOn")")
            return
        }
        if centralManager.isScanning { centralManager.stopScan() } // TODO: needed?
        notificationAcknowledgement = nil
        Logger.central.debug("Central attempts to \(#function) for peripherals with service '\(BluetoothManager.getName(of: self.serviceUUID))'")
        centralManager.scanForPeripherals(withServices: [self.serviceUUID], options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
        centralManager.isScanning ? Logger.central.info("Central started scanning") : Logger.central.error("Central did not start scanning") // TODO: throw
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
        Logger.central.info("Central didDiscover peripheral '\(Utils.printID(peripheral.identifier.uuidString))' (RSSI: \(Int8(RSSI.int8Value))) and attempts to connect to it")
        notificationManager.lastRSSIValue = Int8(RSSI.int8Value)
        guard Int8(RSSI.int8Value) > notificationManager.rssiThreshold else {
            Logger.central.warning("Central will ignore peripheral '\(Utils.printID(peripheral.identifier.uuidString))' as the RSSI \(Int8(RSSI.int8Value)) is below the threshold RSSI \(self.notificationManager.rssiThreshold)")
            return
        }
        guard let randomIdentifier = advertisementData[CBAdvertisementDataLocalNameKey] as? String else {
            Logger.central.error("Central will ignore peripheral '\(Utils.printID(peripheral.identifier.uuidString))' as did not advertise an randomIdentifier")
            return
        }
        guard !bluetoothManager.recentRandomIdentifiers.contains(randomIdentifier) else {
            Logger.central.warning("Central will ignore peripheral '\(Utils.printID(peripheral.identifier.uuidString))' with randomIdentifier '\(randomIdentifier)' as it has been connected recently")
            return
        }
        Logger.central.debug("Central appends randomIdentifier '\(randomIdentifier)' of peripheral '\(Utils.printID(peripheral.identifier.uuidString)) to the recentIdentifiers array")
        bluetoothManager.add(randomIdentifier: randomIdentifier)
        self.peripheral = peripheral
        peripheral.delegate = self
        centralManager.connect(peripheral, options: nil)
    }
    
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        Logger.central.debug("Central didConnect to peripheral '\(Utils.printID(peripheral.identifier.uuidString))' and attempts to discoverServices")
        peripheral.discoverServices([self.serviceUUID])
    }
    
    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        Logger.central.error("Central didFailToConnect to peripheral '\(Utils.printID(peripheral.identifier.uuidString))': '\(error?.localizedDescription ?? "")'")
        peripheral.delegate = nil
        self.peripheral = nil
        scan()
    }
    
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: (any Error)?) {
        guard error == nil else { // TODO: handle
            Logger.central.error("Central did not didDiscoverServices on peripheral '\(Utils.printID(peripheral.identifier.uuidString))': '\(error!.localizedDescription)'")
            centralManager.cancelPeripheralConnection(peripheral)
            return
        }
        Logger.central.debug("Central didDiscoverServices on peripheral '\(Utils.printID(peripheral.identifier.uuidString))' and may attempt to discoverCharacteristics")
        guard let discoveredServices = peripheral.services else { // TODO: handle
            Logger.central.error("Central can't discoverCharacteristics, because the services array of peripheral '\(Utils.printID(peripheral.identifier.uuidString))' is nil")
            centralManager.cancelPeripheralConnection(peripheral)
            return
        }
        for service in discoveredServices {
            guard service.uuid.uuidString == self.serviceUUID.uuidString else {
                Logger.central.trace("Central discovered unknown service '\(BluetoothManager.getName(of: service.uuid))' and will ignore it")
                continue
            }
            Logger.central.trace("Central discovered '\(BluetoothManager.getName(of: service.uuid))' and attempts to discoverCharacteristics")
            peripheral.discoverCharacteristics(nil, for: service)
            return
        }
        Logger.central.error("Central can't discoverCharacteristics, because it did not discover '\(BluetoothManager.getName(of: self.serviceUUID))' on peripheral '\(Utils.printID(peripheral.identifier.uuidString))'")
        centralManager.cancelPeripheralConnection(peripheral)
    }
    
    func peripheral(_ peripheral: CBPeripheral, didModifyServices invalidatedServices: [CBService]) {
        Logger.central.error("Central will disconnect peripheral '\(Utils.printID(peripheral.identifier.uuidString))' because it didModifyServices: \(invalidatedServices)")
        centralManager.cancelPeripheralConnection(peripheral)
    }
    
    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard error == nil else { // TODO: handle
            Logger.central.error("Central did not discoverCharacteristicsFor '\(BluetoothManager.getName(of: service.uuid))' on peripheral '\(Utils.printID(peripheral.identifier.uuidString))': '\(error!.localizedDescription)'")
            centralManager.cancelPeripheralConnection(peripheral)
            return
        }
        Logger.central.debug("Central didDiscoverCharacteristicsFor '\(BluetoothManager.getName(of: service.uuid))' on peripheral '\(Utils.printID(peripheral.identifier.uuidString))' and may attempt to setNotifyValue")
        guard let discoveredCharacteristics = service.characteristics else { // TODO: handle
            Logger.central.error("Central can't setNotifyValue because the characteristics array for '\(BluetoothManager.getName(of: service.uuid))' on peripheral '\(Utils.printID(peripheral.identifier.uuidString)) is nil")
            centralManager.cancelPeripheralConnection(peripheral)
            return
        }
        var discoveredNotificationSourceCharacteristic = false
        for characteristic in discoveredCharacteristics {
            Logger.central.trace("Central discovered '\(BluetoothManager.getName(of: characteristic.uuid))'")
            if characteristic.uuid.uuidString == self.notificationSourceUUID.uuidString {
                Logger.central.debug("Central attempts to setNotifyValue for '\(BluetoothManager.getName(of: characteristic.uuid))'")
                discoveredNotificationSourceCharacteristic = true
                peripheral.setNotifyValue(true, for: characteristic)
            } else if characteristic.uuid.uuidString == self.notificationAcknowledgementUUID.uuidString {
                self.notificationAcknowledgement = characteristic
                Logger.central.debug("Central added '\(BluetoothManager.getName(of: characteristic.uuid))'")
            } else {
                Logger.central.trace("Central discovered unknown characteristic '\(BluetoothManager.getName(of: characteristic.uuid))' and will ignore it")
                continue
            }
        }
        if self.notificationAcknowledgement == nil { // TODO: handle
            Logger.central.warning("Central did not discover '\(BluetoothManager.getName(of: self.notificationAcknowledgementUUID))' for '\(BluetoothManager.getName(of: service.uuid))' on peripheral '\(Utils.printID(peripheral.identifier.uuidString))'")
        }
        guard discoveredNotificationSourceCharacteristic else { // TODO: handle
            Logger.central.error("Central can't setNotifyValue, because it did not discover '\(BluetoothManager.getName(of: self.notificationSourceUUID))' for '\(BluetoothManager.getName(of: service.uuid))' on peripheral '\(Utils.printID(peripheral.identifier.uuidString))'")
            centralManager.cancelPeripheralConnection(peripheral)
            return
        }
        Logger.central.info("Central successfully subscribed to '\(BluetoothManager.getName(of: self.notificationSourceUUID))' for '\(BluetoothManager.getName(of: service.uuid))' on peripheral '\(Utils.printID(peripheral.identifier.uuidString))'")
        notificationManager.isReadyToAdvertise = false
    }
    
    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard error == nil else { // TODO: handle
            Logger.central.error("Central did not receive updateValueFor '\(BluetoothManager.getName(of: characteristic.uuid))' on peripheral '\(Utils.printID(peripheral.identifier.uuidString))': '\(error!.localizedDescription)'")
            centralManager.cancelPeripheralConnection(peripheral)
            return
        }
        guard characteristic.uuid.uuidString == self.notificationSourceUUID.uuidString else {
            Logger.central.warning("Central did receive updateValueFor unknown characteristic \(BluetoothManager.getName(of: characteristic.uuid)) on peripheral '\(Utils.printID(peripheral.identifier.uuidString))' and will ignore it")
            centralManager.cancelPeripheralConnection(peripheral)
            return
        }
        guard let data = characteristic.value else { // TODO: handle
            Logger.central.error("Central can't process updateValue on peripheral '\(Utils.printID(peripheral.identifier.uuidString)), because the value property of '\(BluetoothManager.getName(of: characteristic.uuid))' is nil and will ignore it")
            centralManager.cancelPeripheralConnection(peripheral)
            return
        }
        Logger.central.debug("Central did receive updateValueFor '\(BluetoothManager.getName(of: characteristic.uuid))' on peripheral '\(Utils.printID(peripheral.identifier.uuidString))'")
        notificationManager.receiveNotification(data)
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        guard error == nil else { // TODO: handle
            Logger.central.error("Central did not receive UpdateNotificationStateFor '\(BluetoothManager.getName(of: characteristic.uuid))': '\(error!.localizedDescription)' on peripheral '\(Utils.printID(peripheral.identifier.uuidString))'")
            centralManager.cancelPeripheralConnection(peripheral)
            return
        }
        Logger.central.debug("Central did receive UpdateNotificationStateFor '\(BluetoothManager.getName(of: characteristic.uuid))' to \(characteristic.isNotifying) on peripheral '\(Utils.printID(peripheral.identifier.uuidString))'")
    }
    
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, timestamp: CFAbsoluteTime, isReconnecting: Bool, error: (any Error)?) {
        guard error == nil else { // TODO: handle
            Logger.central.error("Central did not disconnectPeripheral '\(Utils.printID(peripheral.identifier.uuidString))': '\(error!.localizedDescription)'")
            centralManager.cancelPeripheralConnection(peripheral)
            return
        }
        guard !isReconnecting else { // TODO: handle
            Logger.central.warning("Central isReconnecting to peripheral '\(Utils.printID(peripheral.identifier.uuidString))'")
            return
        }
        Logger.central.info("Central didDisconnectPeripheral '\(Utils.printID(peripheral.identifier.uuidString))'")
        peripheral.delegate = nil
        self.peripheral = nil
        notificationManager.isReadyToAdvertise = true
        scan()
    }
}
