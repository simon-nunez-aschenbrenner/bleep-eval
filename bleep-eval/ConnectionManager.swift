//
//  ConnectionManager.swift
//  bleep-eval
//
//  Created by Simon Núñez Aschenbrenner on 10.05.24.
//

import CoreBluetooth
import CryptoKit
import Foundation
import OSLog

// MARK: ConnectionManager

protocol ConnectionManager {
    var maxNotificationLength: Int! { get }
    init(notificationManager: NotificationManager)
    func advertise()
    func publish(_ data: Data) -> Bool
    func publish(_ data: Data, to id: String) -> Bool
    func write(_ data: Data, to id: String) -> Bool
    func disconnect(_ id: String)
    func disconnect()
    func reset()
}

// MARK: BluetoothManager

@Observable
class BluetoothManager: ConnectionManager {
    
    static let serviceUUID = CBUUID(string: "08373f8c-3635-4b88-8664-1ccc65a60aae")
    static let notificationSourceUUID = CBUUID(string: "c44f6cf4-5bdd-4c8a-b72c-2931be44af0a")
    static let notificationResponseUUID = CBUUID(string: "9e201989-0725-4fa6-8991-5a1ed1c084b1")
    static let centralIdentifierKey = "com.simon.bleep-eval.central"
    static let peripheralIdentifierKey = "com.simon.bleep-eval.peripheral"
    
    static func getName(of cbuuid: CBUUID) -> String {
        switch cbuuid.uuidString {
        case BluetoothManager.serviceUUID.uuidString:
            return "Bleep Notification Service"
        case BluetoothManager.notificationSourceUUID.uuidString:
            return "Bleep Notification Source Characteristic"
        case BluetoothManager.notificationResponseUUID.uuidString:
            return "Bleep Notification Response Characteristic"
        default:
            return cbuuid.uuidString
        }
    }
    
    let maxNotificationLength: Int! = 524
    var recentRandomIdentifiers: Set<String> = []
    private(set) var randomIdentifier: String = String(Address().base58Encoded.suffix(8))
    private var peripheralManagerDelegate: PeripheralManagerDelegate! // Provider
    private var centralManagerDelegate: CentralManagerDelegate! // Consumer
        
    required init(notificationManager: NotificationManager) {
        self.peripheralManagerDelegate = PeripheralManagerDelegate(notificationManager: notificationManager, bluetoothManager: self)
        self.centralManagerDelegate = CentralManagerDelegate(notificationManager: notificationManager, bluetoothManager: self)
        Logger.bluetooth.trace("BluetoothManager initialized with randomIdentifier '\(self.randomIdentifier)'")
    }
    
    private func getPeripheral(_ id: String) -> CBPeripheral? {
        Logger.bluetooth.debug("BluetoothManager attempts to \(#function) '\(Utils.printID(id))'")
        let peripherals = centralManagerDelegate.centralManager.retrievePeripherals(withIdentifiers: [UUID(uuidString: id)!])
        guard !peripherals.isEmpty else {
            Logger.central.error("BluetoothManager can't \(#function) because there is no matching peripheral")
            return nil
        }
        return peripherals[0]
    }
    
    func reset() {
        peripheralManagerDelegate.centrals.removeAll()
        disconnect()
        advertise()
    }
    
    // MARK: Provider
    
    func advertise() {
        Logger.bluetooth.trace("BluetoothManager attempts to \(#function)")
        randomIdentifier = String(Address().base58Encoded.suffix(8))
        peripheralManagerDelegate.advertise()
    }
    
    func publish(_ data: Data) -> Bool {
        Logger.bluetooth.debug("BluetoothManager attempts to \(#function) \(data.count) bytes")
        return peripheralManagerDelegate.peripheralManager.updateValue(data, for: peripheralManagerDelegate.notificationSource, onSubscribedCentrals: nil)
    }
    
    func publish(_ data: Data, to id: String) -> Bool {
        Logger.bluetooth.debug("BluetoothManager attempts to \(#function) \(data.count) bytes to '\(Utils.printID(id))'")
        guard let central = peripheralManagerDelegate.centrals.first(where: { $0.identifier.uuidString == id } ) else {
            Logger.central.error("BluetoothManager can't \(#function) because there is no matching central")
            return false
        }
        return peripheralManagerDelegate.peripheralManager.updateValue(data, for: peripheralManagerDelegate.notificationSource, onSubscribedCentrals: [central])
    }
    
    func write(_ data: Data, to id: String) -> Bool {
        Logger.bluetooth.debug("BluetoothManager attempts to \(#function) of \(data.count) bytes to '\(Utils.printID(id))'")
        guard let notificationResponse = centralManagerDelegate.notificationResponse else {
            Logger.bluetooth.error("BluetoothManager can't \(#function) because the centralManagerDelegate notificationResponse characteristic property is nil")
            return false
        }
        guard let peripheral = getPeripheral(id) else { return false }
        peripheral.writeValue(data, for: notificationResponse, type: .withResponse)
        return true
    }
    
    // MARK: Consumer
    
    func disconnect(_ id: String) {
        Logger.bluetooth.trace("BluetoothManager attempts to \(#function) from '\(Utils.printID(id))'")
        guard let peripheral = getPeripheral(id) else { return }
        centralManagerDelegate.centralManager.cancelPeripheralConnection(peripheral)
    }
    
    func disconnect() {
        Logger.bluetooth.debug("BluetoothManager attempts to \(#function) from all peripherals")
        let peripherals = centralManagerDelegate.centralManager.retrieveConnectedPeripherals(withServices: [BluetoothManager.serviceUUID])
        guard !peripherals.isEmpty else {
            Logger.bluetooth.debug("BluetoothManager can't \(#function) because there are no connected peripherals")
            return
        }
        for peripheral in peripherals {
            Logger.bluetooth.debug("BluetoothManager attempts to \(#function) from '\(Utils.printID(peripheral.identifier.uuidString))'")
            centralManagerDelegate.centralManager.cancelPeripheralConnection(peripheral)
        }
    }
}
