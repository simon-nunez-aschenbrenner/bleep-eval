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

struct BluetoothConstants {
    static let serviceUUID = CBUUID(string: "08373f8c-3635-4b88-8664-1ccc65a60aae")
    static let notificationSourceUUID = CBUUID(string: "c44f6cf4-5bdd-4c8a-b72c-2931be44af0a")
    
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
}
