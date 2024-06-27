//
//  BluetoothManager.swift
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
    var notificationManager: NotificationManager! { get }
    
    init(notificationManager: NotificationManager)
    
    func advertise()
    func send(notification data: Data) -> Bool
    func acknowledge(hashedID data: Data)
    func disconnect()
}

// MARK: BluetoothManager

@Observable
class BluetoothManager: ConnectionManager {
    
    static let serviceUUID = CBUUID(string: "08373f8c-3635-4b88-8664-1ccc65a60aae")
    static let notificationSourceUUID = CBUUID(string: "c44f6cf4-5bdd-4c8a-b72c-2931be44af0a")
    static let notificationAcknowledgementUUID = CBUUID(string: "9e201989-0725-4fa6-8991-5a1ed1c084b1")
    static let centralIdentifierKey = "com.simon.bleep-eval.central"
    static let peripheralIdentifierKey = "com.simon.bleep-eval.peripheral"
    
    static func getName(of cbuuid: CBUUID) -> String {
        switch cbuuid.uuidString {
        case BluetoothManager.serviceUUID.uuidString:
            return "Bleep Notification Service"
        case BluetoothManager.notificationSourceUUID.uuidString:
            return "Notification Source Characteristic"
        case BluetoothManager.notificationAcknowledgementUUID.uuidString:
            return "Notification Acknowledgement Characteristic"
        default:
            return "\(cbuuid.uuidString)"
        }
    }
    
    let maxNotificationLength: Int! = 524
    
    unowned var notificationManager: NotificationManager!
    private var peripheralManagerDelegate: PeripheralManagerDelegate! // Provider
    private var centralManagerDelegate: CentralManagerDelegate! // Consumer
    
    required init(notificationManager: NotificationManager) {
        Logger.bluetooth.trace("BluetoothManager initializes")
        self.notificationManager = notificationManager
        self.peripheralManagerDelegate = PeripheralManagerDelegate(notificationManager: notificationManager, bluetoothManager: self)
        self.centralManagerDelegate = CentralManagerDelegate(notificationManager: notificationManager, bluetoothManager: self)
        Logger.bluetooth.trace("BluetoothManager initialized")
    }
    
    func advertise() {
        Logger.bluetooth.trace("BluetoothManager attempts to \(#function)")
        peripheralManagerDelegate.advertise()
    }
    
    func send(notification data: Data) -> Bool {
        Logger.bluetooth.trace("BluetoothManager attempts to \(#function)")
        return peripheralManagerDelegate.peripheralManager.updateValue(data, for: peripheralManagerDelegate!.notificationSource, onSubscribedCentrals: nil)
    }
    
    func acknowledge(hashedID data: Data) {
        Logger.bluetooth.debug("BluetoothManager attempts to \(#function) #\(Utils.printID(data))")
        guard let peripheral = centralManagerDelegate.peripheral else { // TODO: handle
            Logger.central.error("BluetoothManager can't \(#function) because the centralManagerDelegate peripheral property is nil")
            return
        }
        guard let notificationAcknowledgement = centralManagerDelegate.notificationAcknowledgement else { // TODO: handle
            Logger.bluetooth.error("BluetoothManager can't \(#function) because the centralManagerDelegate notificationAcknowledgement characteristic property is nil")
            return
        }
        peripheral.writeValue(data, for: notificationAcknowledgement, type: .withResponse)
    }
    
    func disconnect() {
        Logger.bluetooth.trace("BluetoothManager attempts to \(#function)")
        guard let peripheral = centralManagerDelegate.peripheral else { // TODO: handle
            Logger.central.error("BluetoothManager can't \(#function) because the centralManagerDelegate peripheral property is nil")
            return
        }
        centralManagerDelegate.centralManager.cancelPeripheralConnection(peripheral)
    }
}
