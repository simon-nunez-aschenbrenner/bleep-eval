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
    
    private let serviceUUID = BluetoothManager.serviceUUID
    private let notificationSourceUUID = BluetoothManager.notificationSourceUUID
    private let notificationResponseUUID = BluetoothManager.notificationResponseUUID
    private(set) var centralManager: CBCentralManager!
    private(set) var notificationResponse: CBCharacteristic?
    private var peripherals: Set<CBPeripheral> = []
    unowned private var notificationManager: NotificationConsumer!
    unowned private var bluetoothManager: BluetoothManager!
        
    // MARK: initializing methods
            
    init(notificationManager: NotificationConsumer, bluetoothManager: BluetoothManager) {
        super.init()
        self.notificationManager = notificationManager
        self.bluetoothManager = bluetoothManager
        self.centralManager = CBCentralManager(delegate: self, queue: nil, options: [CBCentralManagerOptionRestoreIdentifierKey: BluetoothManager.centralIdentifierKey, CBCentralManagerOptionShowPowerAlertKey: true])
        Logger.central.trace("CentralManagerDelegate initialized")
    }
    
    // MARK: public methods
        
    func scan() {
        Logger.central.debug("Central may attempt to \(#function)")
        guard centralManager.state == .poweredOn else {
            Logger.central.warning("Central won't attempt to \(#function) because the centralManager is not poweredOn")
            return
        }
        if centralManager.isScanning { centralManager.stopScan() }
        notificationResponse = nil
        Logger.central.debug("Central attempts to \(#function) for peripherals with service '\(BluetoothManager.getName(of: self.serviceUUID))'")
        centralManager.scanForPeripherals(withServices: [serviceUUID], options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
        centralManager.isScanning ? Logger.central.info("Central started scanning") : Logger.central.error("Central did not start scanning")
    }
    
    // MARK: delegate methods
    
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            Logger.central.debug("\(#function) to 'poweredOn'")
            scan()
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
        Logger.central.debug("Central didDiscover peripheral '\(Utils.printID(peripheral.identifier.uuidString))' (RSSI: \(Int8(RSSI.int8Value))) and attempts to connect to it")
        
        if let evaluableNotificationManager = notificationManager as? EvaluableNotificationManager {
            evaluableNotificationManager.lastRSSIValue = Int8(RSSI.int8Value)
            guard Int8(RSSI.int8Value) > evaluableNotificationManager.rssiThreshold else {
                Logger.central.warning("Central will ignore peripheral '\(Utils.printID(peripheral.identifier.uuidString))' as the RSSI \(Int8(RSSI.int8Value)) is below the threshold RSSI \(evaluableNotificationManager.rssiThreshold)")
                return
            }
        }
        guard let randomIdentifier = advertisementData[CBAdvertisementDataLocalNameKey] as? String else {
            Logger.central.error("Central will ignore peripheral '\(Utils.printID(peripheral.identifier.uuidString))' as it did not advertise an randomIdentifier")
            return
        }
        guard !bluetoothManager.recentRandomIdentifiers.contains(randomIdentifier) else {
            Logger.central.warning("Central will ignore peripheral '\(Utils.printID(peripheral.identifier.uuidString))' with randomIdentifier '\(randomIdentifier)' as it has been connected recently")
            return
        }
        Logger.central.debug("Central appends randomIdentifier '\(randomIdentifier)' of peripheral '\(Utils.printID(peripheral.identifier.uuidString)) to the recentIdentifiers array")
        bluetoothManager.add(randomIdentifier: randomIdentifier)
        peripherals.insert(peripheral)
        peripheral.delegate = self
        centralManager.connect(peripheral, options: nil)
    }
    
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        Logger.central.debug("Central didConnect to peripheral '\(Utils.printID(peripheral.identifier.uuidString))' and attempts to discoverServices")
        peripheral.discoverServices([serviceUUID])
    }
    
    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        Logger.central.error("Central didFailToConnect to peripheral '\(Utils.printID(peripheral.identifier.uuidString))': '\(error?.localizedDescription ?? "")'")
        peripheral.delegate = nil
        peripherals.remove(peripheral)
        scan()
    }
    
    func peripheral(_ peripheral: CBPeripheral, didModifyServices invalidatedServices: [CBService]) {
//        if invalidatedServices.contains(where: { $0.uuid.uuidString == self.serviceUUID.uuidString } ) {
//            Logger.central.warning("Central attempts to re-discoverServices on peripheral '\(Utils.printID(peripheral.identifier.uuidString))' because it didModifyService '\(BluetoothManager.getName(of: self.serviceUUID))'")
//            peripheral.discoverServices([serviceUUID])
//        } else {
//            Logger.central.error("Central will ignore didModifyServices on peripheral '\(Utils.printID(peripheral.identifier.uuidString))' because the invalidatedServices did not match '\(BluetoothManager.getName(of: self.serviceUUID))'")
//        }
        Logger.central.error("Central will disconnect peripheral '\(Utils.printID(peripheral.identifier.uuidString))' because it didModifyServices: \(invalidatedServices)")
        centralManager.cancelPeripheralConnection(peripheral)
    }
    
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: (any Error)?) {
        guard error == nil else {
            Logger.central.error("Central did not didDiscoverServices on peripheral '\(Utils.printID(peripheral.identifier.uuidString))': '\(error!.localizedDescription)'")
            centralManager.cancelPeripheralConnection(peripheral)
            return
        }
        Logger.central.debug("Central didDiscoverServices on peripheral '\(Utils.printID(peripheral.identifier.uuidString))' and may attempt to discoverCharacteristics")
        guard let discoveredServices = peripheral.services else {
            Logger.central.error("Central can't discoverCharacteristics, because the services array of peripheral '\(Utils.printID(peripheral.identifier.uuidString))' is nil")
            centralManager.cancelPeripheralConnection(peripheral)
            return
        }
        for service in discoveredServices {
            guard service.uuid.uuidString == serviceUUID.uuidString else {
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
    
    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard error == nil else {
            Logger.central.error("Central did not discoverCharacteristicsFor '\(BluetoothManager.getName(of: service.uuid))' on peripheral '\(Utils.printID(peripheral.identifier.uuidString))': '\(error!.localizedDescription)'")
            centralManager.cancelPeripheralConnection(peripheral)
            return
        }
        Logger.central.debug("Central didDiscoverCharacteristicsFor '\(BluetoothManager.getName(of: service.uuid))' on peripheral '\(Utils.printID(peripheral.identifier.uuidString))' and may attempt to setNotifyValue")
        guard let discoveredCharacteristics = service.characteristics else {
            Logger.central.error("Central can't setNotifyValue because the characteristics array for '\(BluetoothManager.getName(of: service.uuid))' on peripheral '\(Utils.printID(peripheral.identifier.uuidString)) is nil")
            centralManager.cancelPeripheralConnection(peripheral)
            return
        }
        var discoveredNotificationSourceCharacteristic = false
        for characteristic in discoveredCharacteristics {
            Logger.central.trace("Central discovered '\(BluetoothManager.getName(of: characteristic.uuid))'")
            if characteristic.uuid.uuidString == notificationSourceUUID.uuidString {
                Logger.central.debug("Central attempts to setNotifyValue for '\(BluetoothManager.getName(of: characteristic.uuid))'")
                discoveredNotificationSourceCharacteristic = true
                peripheral.setNotifyValue(true, for: characteristic)
            } else if characteristic.uuid.uuidString == notificationResponseUUID.uuidString {
                notificationResponse = characteristic
                Logger.central.debug("Central added '\(BluetoothManager.getName(of: characteristic.uuid))'")
            } else {
                Logger.central.trace("Central discovered unknown characteristic '\(BluetoothManager.getName(of: characteristic.uuid))' and will ignore it")
                continue
            }
        }
        guard notificationResponse != nil else {
            Logger.central.error("Central did not discover '\(BluetoothManager.getName(of: self.notificationResponseUUID))' for '\(BluetoothManager.getName(of: service.uuid))' on peripheral '\(Utils.printID(peripheral.identifier.uuidString))'")
            centralManager.cancelPeripheralConnection(peripheral)
            return
        }
        guard discoveredNotificationSourceCharacteristic else {
            Logger.central.error("Central can't setNotifyValue, because it did not discover '\(BluetoothManager.getName(of: self.notificationSourceUUID))' for '\(BluetoothManager.getName(of: service.uuid))' on peripheral '\(Utils.printID(peripheral.identifier.uuidString))'")
            centralManager.cancelPeripheralConnection(peripheral)
            return
        }
        Logger.central.info("Central successfully subscribed to '\(BluetoothManager.getName(of: self.notificationSourceUUID))' for '\(BluetoothManager.getName(of: service.uuid))' on peripheral '\(Utils.printID(peripheral.identifier.uuidString))'")
        notificationManager.blocked = true
    }
    
    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        guard error == nil else {
            Logger.central.error("Central did not receive UpdateNotificationStateFor '\(BluetoothManager.getName(of: characteristic.uuid))': '\(error!.localizedDescription)' on peripheral '\(Utils.printID(peripheral.identifier.uuidString))'")
            centralManager.cancelPeripheralConnection(peripheral)
            return
        }
        Logger.central.debug("Central did receive UpdateNotificationStateFor '\(BluetoothManager.getName(of: characteristic.uuid))' to \(characteristic.isNotifying) on peripheral '\(Utils.printID(peripheral.identifier.uuidString))'")
    }
    
    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard error == nil else {
            Logger.central.error("Central did not receive updateValueFor '\(BluetoothManager.getName(of: characteristic.uuid))' on peripheral '\(Utils.printID(peripheral.identifier.uuidString))': '\(error!.localizedDescription)'")
            centralManager.cancelPeripheralConnection(peripheral)
            return
        }
        guard characteristic.uuid.uuidString == notificationSourceUUID.uuidString else {
            Logger.central.warning("Central did receive updateValueFor unknown characteristic \(BluetoothManager.getName(of: characteristic.uuid)) on peripheral '\(Utils.printID(peripheral.identifier.uuidString))' and will ignore it")
            centralManager.cancelPeripheralConnection(peripheral)
            return
        }
        guard let data = characteristic.value else {
            Logger.central.error("Central can't process updateValue on peripheral '\(Utils.printID(peripheral.identifier.uuidString)), because the value property of '\(BluetoothManager.getName(of: characteristic.uuid))' is nil and will ignore it")
            centralManager.cancelPeripheralConnection(peripheral)
            return
        }
        Logger.central.debug("Central did receive updateValueFor '\(BluetoothManager.getName(of: characteristic.uuid))' on peripheral '\(Utils.printID(peripheral.identifier.uuidString))'")
        notificationManager.receiveNotification(data, from: peripheral.identifier.uuidString)
    }
    
    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: (any Error)?) {
        guard error == nil else {
            Logger.central.error("Central did not writeValueFor '\(BluetoothManager.getName(of: characteristic.uuid))' on peripheral '\(Utils.printID(peripheral.identifier.uuidString))': '\(error!.localizedDescription)'")
            return
        }
        Logger.central.debug("Central didWriteValueFor '\(BluetoothManager.getName(of: characteristic.uuid))' on peripheral '\(Utils.printID(peripheral.identifier.uuidString))'")
    }
    
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, timestamp: CFAbsoluteTime, isReconnecting: Bool, error: (any Error)?) {
        guard error == nil else {
            Logger.central.error("Central did not disconnectPeripheral '\(Utils.printID(peripheral.identifier.uuidString))': '\(error!.localizedDescription)'")
            centralManager.cancelPeripheralConnection(peripheral)
            return
        }
        guard !isReconnecting else {
            Logger.central.error("Central isReconnecting to peripheral '\(Utils.printID(peripheral.identifier.uuidString))'")
            centralManager.cancelPeripheralConnection(peripheral)
            return
        }
        Logger.central.info("Central didDisconnectPeripheral '\(Utils.printID(peripheral.identifier.uuidString))'")
        peripheral.delegate = nil
        peripherals.remove(peripheral)
        if peripherals.isEmpty { notificationManager.blocked = false }
        scan()
    }
}
