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
        Logger.central.trace("Central may attempt to \(#function)")
        Logger.central.debug("CentralManager is \(self.centralManager.state == .poweredOn ? "poweredOn" : "NOT poweredOn") and \(self.centralManager.isScanning ? "SCANNING" : "not scanning"), DeviceMode is \(self.bluetoothManager.mode.isConsumer ? "consumer" : "NOT consumer"), CentralManagerDelegate peripheral property is \(self.peripheral == nil ? "nil" : "NOT nil")")
        if centralManager.isScanning {
            Logger.central.debug("Central is already scanning")
        } else if centralManager.state == .poweredOn && bluetoothManager.mode.isConsumer && peripheral == nil {
            Logger.central.debug("Central attempts to \(#function) for peripherals with service '\(getName(of: self.serviceUUID))'")
            centralManager.scanForPeripherals(withServices: [self.serviceUUID], options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
        } else {
            Logger.central.info("Central won't attempt to \(#function)")
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
        
    func disconnect(from peripheral: CBPeripheral) {
        Logger.central.debug("Central attempts to \(#function) from peripheral '\(printID(peripheral.identifier.uuidString))'")
        centralManager.cancelPeripheralConnection(peripheral)
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
            Logger.central.debug("Central did receive UpdateValueFor characteristic \(getName(of: characteristic.uuid)) on peripheral '\(printID(peripheral.identifier.uuidString))' with \(data.count-minNotificationLength)+\(minNotificationLength)=\(data.count) bytes")
            if characteristic.uuid.uuidString == self.characteristicUUID.uuidString {
                notificationManager.receiveNotification(data: data)
            } else {
                Logger.central.warning("Central did receive UpdateValueFor unknown characteristic \(getName(of: characteristic.uuid))")
            }
        }
    }
    
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
