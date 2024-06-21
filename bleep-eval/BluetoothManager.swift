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

protocol ConnectionManager {
    
    var notificationManager: NotificationManager! { get }
    var mode: DeviceMode! { get }

    init(notificationManager: NotificationManager)
    
    func setMode(to mode: DeviceMode)
    func send(notification data: Data) -> Bool
    func acknowledge(hashedID data: Data)
}

enum DeviceMode: Int, CustomStringConvertible {
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

struct BluetoothConstants {
    static let serviceUUID = CBUUID(string: "08373f8c-3635-4b88-8664-1ccc65a60aae")
    static let notificationSourceUUID = CBUUID(string: "c44f6cf4-5bdd-4c8a-b72c-2931be44af0a")
    static let notificationAcknowledgementUUID = CBUUID(string: "9e201989-0725-4fa6-8991-5a1ed1c084b1")
    
    static let peripheralName = "bleeper"
    static let centralIdentifierKey = "com.simon.bleep-eval.central"
    static let peripheralIdentifierKey = "com.simon.bleep-eval.peripheral"
}

@Observable
class BluetoothManager: NSObject, ConnectionManager {

    unowned var notificationManager: NotificationManager!
    
    private var peripheralManagerDelegate: PeripheralManagerDelegate! // Provider
    private var centralManagerDelegate: CentralManagerDelegate! // Consumer
    
    private(set) var mode: DeviceMode! {
        didSet {
            Logger.bluetooth.info("BluetoothManager set mode to '\(self.mode)'")
        }
    }
    
    required init(notificationManager: NotificationManager) {
        super.init()
        self.notificationManager = notificationManager
        self.peripheralManagerDelegate = PeripheralManagerDelegate(notificationManager: notificationManager, bluetoothManager: self)
        self.centralManagerDelegate = CentralManagerDelegate(notificationManager: notificationManager, bluetoothManager: self)
        initMode()
        Logger.bluetooth.trace("BluetoothManager initialized")
    }
    
    private func initMode() {
        let isScanning = centralManagerDelegate.centralManager.isScanning
        let isAdvertising = peripheralManagerDelegate.peripheralManager.isAdvertising
        Logger.bluetooth.trace("BluetoothManager will \(#function) based on isScanning=\(isScanning) and isAdvertising=\(isAdvertising)")
        if isAdvertising && isScanning { // TODO: handle
            Logger.bluetooth.fault("Could not \(#function): isScanning=\(isScanning), isAdvertising=\(isAdvertising)")
            self.mode = .undefined
        } else if !isAdvertising && !isScanning {
            self.mode = .undefined
        } else if isScanning {
            self.mode = .consumer
        } else if isAdvertising {
            self.mode = .provider
        }
    }
    
    func setMode(to mode: DeviceMode) {
        self.mode = mode
        switch mode {
        case .consumer:
            peripheralManagerDelegate.stopAdvertising()
            centralManagerDelegate.disconnect()
            centralManagerDelegate.startScan()
        case .provider:
            centralManagerDelegate.stopScan()
            centralManagerDelegate.disconnect()
            peripheralManagerDelegate.startAdvertising()
        case .undefined:
            centralManagerDelegate.stopScan()
            centralManagerDelegate.disconnect()
            peripheralManagerDelegate.stopAdvertising()
        }
    }
    
    func send(notification data: Data) -> Bool {
        return peripheralManagerDelegate.peripheralManager.updateValue(data, for: peripheralManagerDelegate.notificationSource, onSubscribedCentrals: nil)
    }
    
    func acknowledge(hashedID data: Data) {
        guard let peripheral = centralManagerDelegate.peripheral else { // TODO: handle
            Logger.central.error("Central can't \(#function) because the centralManagerDelegate peripheral property is nil")
            return
        }
        guard let notificationAcknowledgement = centralManagerDelegate.notificationAcknowledgement else { // TODO: handle
            Logger.central.error("Central can't \(#function) because the centralManagerDelegate notificationAcknowledgement property is nil")
            return
        }
        peripheral.writeValue(data, for: notificationAcknowledgement, type: .withResponse)
    }
}
