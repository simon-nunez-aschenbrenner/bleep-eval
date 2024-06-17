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

enum BluetoothMode: Int, CustomStringConvertible {
    case central = -1 // Subscriber / Notification Consumer (NC)
    case undefined = 0
    case peripheral = 1 // Publisher / Notification Provider (NP)
    
    var description: String {
        switch self {
        case .central: return "Central"
        case .undefined: return "Undefined"
        case .peripheral:  return "Peripheral"
        }
    }
}

@Observable
class BluetoothManager: NSObject {
    
    unowned var notificationManager: NotificationManager!
    
    private var peripheralManagerDelegate: PeripheralManagerDelegate!
    private var centralManagerDelegate: CentralManagerDelegate!
    
    private(set) var mode: BluetoothMode! {
        didSet {
            Logger.bluetooth.notice("BluetoothManager set mode to '\(self.mode)'")
        }
    }
    
    var modeIsPeripheral: Bool { return !(mode.rawValue < 1) }
    var modeIsCentral: Bool { return !(mode.rawValue > -1) }
    var modeIsUndefined: Bool { return mode.rawValue == 0 }
    
    init(notificationManager: NotificationManager) {
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
        Logger.bluetooth.trace("BluetoothManager will \(#function) based on centralManager.isScanning = \(isScanning) and peripheralManager.isAdvertising = \(isAdvertising)")
        if isAdvertising && isScanning { // TODO: handle
            Logger.bluetooth.fault("Could not \(#function): isScanning = \(isScanning), isAdvertising = \(isAdvertising)")
            self.mode = .undefined
        } else if !isAdvertising && !isScanning {
            self.mode = .undefined
        } else if isScanning {
            self.mode = .central
        } else if isAdvertising {
            self.mode = .peripheral
        }
    }
    
    func setMode(to mode: BluetoothMode) {
        self.mode = mode
        switch mode {
        case .central:
            peripheralManagerDelegate.stopAdvertising()
            centralManagerDelegate.startScan()
        case .peripheral:
            centralManagerDelegate.stopScan()
            centralManagerDelegate.disconnect()
            peripheralManagerDelegate.startAdvertising()
            
        case .undefined:
            centralManagerDelegate.stopScan()
            centralManagerDelegate.disconnect()
            peripheralManagerDelegate.stopAdvertising()
        }
    }
}
