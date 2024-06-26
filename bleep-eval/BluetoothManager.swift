//
//  BluetoothManager.swift
//  bleep-eval
//
//  Created by Simon Núñez Aschenbrenner on 10.05.24.
//

import Foundation
import CoreBluetooth
import CryptoKit
import OSLog

// MARK: ConnectionManager protocol

enum ConnectionManagerMode: Int, CustomStringConvertible {
    case consumer = -1
    case undefined = 0
    case provider = 1
    
    var isConsumer: Bool { return !(self.rawValue > -1) }
    var isUndefined: Bool { return self.rawValue == 0 }
    var isProvider: Bool { return !(self.rawValue < 1) }
    
    var description: String {
        switch self {
        case .consumer: return "Consumer"
        case .undefined: return "Undefined"
        case .provider:  return "Provider"
        }
    }
    
}

protocol ConnectionManager {
    
    var notificationManager: NotificationManager! { get }
    var mode: ConnectionManagerMode! { get }

    init(notificationManager: NotificationManager)
    
    func setMode(to mode: ConnectionManagerMode)
    func send(notification data: Data) -> Bool
    func acknowledge(hashedID data: Data)
    func disconnect()
    
}

// MARK: BluetoothManager class

@Observable
class BluetoothManager: NSObject, ConnectionManager {

    unowned var notificationManager: NotificationManager!
    
    private var peripheralManagerDelegate: PeripheralManagerDelegate? // Provider
    private var centralManagerDelegate: CentralManagerDelegate? // Consumer
    
    private(set) var mode: ConnectionManagerMode! {
        didSet {
            Logger.bluetooth.info("BluetoothManager set mode to '\(self.mode)'")
        }
    }
    
    required init(notificationManager: NotificationManager) {
        Logger.bluetooth.trace("BluetoothManager initializes")
        super.init()
        self.notificationManager = notificationManager
        setMode(to: .undefined)
        Logger.bluetooth.trace("BluetoothManager initialized")
    }
    
    func setMode(to mode: ConnectionManagerMode) {
        Logger.bluetooth.trace("BluetoothManager attempts to \(#function) \(mode)")
        self.mode = mode
        switch mode {
        case .consumer:
            peripheralManagerDelegate = nil
            if centralManagerDelegate == nil {
                centralManagerDelegate = CentralManagerDelegate(notificationManager: notificationManager, bluetoothManager: self)
            } else {
                disconnect()
                centralManagerDelegate!.scan()
            }
        case .provider:
            centralManagerDelegate = nil
            if peripheralManagerDelegate == nil {
                peripheralManagerDelegate = PeripheralManagerDelegate(notificationManager: notificationManager, bluetoothManager: self)
            } else {
                peripheralManagerDelegate!.advertise()
            }
        case .undefined:
            centralManagerDelegate = nil
            peripheralManagerDelegate = nil
        }
    }
    
    func send(notification data: Data) -> Bool {
        Logger.bluetooth.trace("BluetoothManager attempts to \(#function)")
        guard peripheralManagerDelegate != nil else { // TODO: handle
            Logger.bluetooth.fault("BluetoothManager can't \(#function) because its peripheralManagerDelegate property is nil")
            return false
        }
        return peripheralManagerDelegate!.peripheralManager.updateValue(data, for: peripheralManagerDelegate!.notificationSource, onSubscribedCentrals: nil)
    }
    
    func acknowledge(hashedID data: Data) {
        Logger.bluetooth.debug("BluetoothManager attempts to \(#function) #\(printID(data))")
        guard centralManagerDelegate != nil else { // TODO: handle
            Logger.bluetooth.fault("BluetoothManager can't \(#function) because its centralManagerDelegate property is nil")
            return
        }
        guard let peripheral = centralManagerDelegate!.peripheral else { // TODO: handle
            Logger.central.error("BluetoothManager can't \(#function) because the centralManagerDelegate peripheral property is nil")
            return
        }
        guard let notificationAcknowledgement = centralManagerDelegate!.notificationAcknowledgement else { // TODO: handle
            Logger.bluetooth.error("BluetoothManager can't \(#function) because the centralManagerDelegate notificationAcknowledgement characteristic property is nil")
            return
        }
        peripheral.writeValue(data, for: notificationAcknowledgement, type: .withResponse)
    }
    
    func disconnect() {
        Logger.bluetooth.trace("BluetoothManager attempts to \(#function)")
        guard centralManagerDelegate != nil else { // TODO: handle
            Logger.bluetooth.fault("BluetoothManager can't \(#function) because its centralManagerDelegate property is nil")
            return
        }
        guard let peripheral = centralManagerDelegate!.peripheral else { // TODO: handle
            Logger.central.error("BluetoothManager can't \(#function) because the centralManagerDelegate peripheral property is nil")
            return
        }
        centralManagerDelegate!.centralManager.cancelPeripheralConnection(peripheral)
    }
    
}
