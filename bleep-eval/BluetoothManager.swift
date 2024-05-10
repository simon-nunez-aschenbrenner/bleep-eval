//
//  BluetoothManager.swift
//  bleep-eval
//
//  Created by Simon Núñez Aschenbrenner on 10.05.24.
//

import Foundation
import CoreBluetooth
import Logging

private let logger = Logger(label: "com.simon.bleep-eval.logger.bluetooth")

let testPeripheralName: String = "bleep"
let testServiceUUID = CBUUID(string: "d50cfc1b-9fc7-4f07-9fa0-fe7cd33f3e92")
let testCharacteristicUUID = CBUUID(string: "f03a20be-b7e9-44cf-b156-685fe9762504")

enum BluetoothMode : Int {
    case central = -1
    case undefined = 0
    case peripheral = 1
}

class BluetoothManager: NSObject, BluetoothPublisher, BluetoothSubscriber {
    
    private(set) var peripheralName: String!
    private(set) var serviceUUID: CBUUID!
    private(set) var characteristicUUID: CBUUID!
    
    private(set) var peripheralManagerDelegate: PeripheralManagerDelegate!
    private(set) var centralManagerDelegate: CentralManagerDelegate!
    
    var outgoingTestMessage: String? {
        get {
            return peripheralManagerDelegate.testMessage
        }
        set(newOutgoingTestMessage) {
            peripheralManagerDelegate.testMessage = newOutgoingTestMessage
        }
    }
    var incomingTestMessage: String? {
        return centralManagerDelegate.testMessage
    }
    
    private(set) var mode: BluetoothMode! {
        didSet {
            logger.debug("Mode set to \(String(describing: mode))")
        }
    }
    
    override init() {
        super.init()
        peripheralName = testPeripheralName
        serviceUUID = testServiceUUID
        characteristicUUID = testCharacteristicUUID
        peripheralManagerDelegate = PeripheralManagerDelegate(bluetoothManager: self)
        centralManagerDelegate = CentralManagerDelegate(bluetoothManager: self)
        setMode()
        logger.info("BluetoothManager initialized")
    }
    
    private func setMode() {
        setMode(to: nil)
    }
    
    private func setMode(to mode: BluetoothMode?) {
        if mode != nil {
            self.mode = mode
        } else {
            let isScanning = centralManagerDelegate.centralManager.isScanning
            let isAdvertising = peripheralManagerDelegate.peripheralManager.isAdvertising
            if (!isAdvertising && !isScanning) || (isAdvertising && isScanning) { // TODO: XOR
                self.mode = BluetoothMode.undefined
            } else if isScanning {
                self.mode = BluetoothMode.central
            } else if isAdvertising {
                self.mode = BluetoothMode.peripheral
            }
        }
    }
    
    func publish(serviceUUID: CBUUID?, characteristicUUID: CBUUID?, message: String) {
        logger.debug("BluetoothManager.\(#function) called for service \(String(describing: serviceUUID)) and characteristic \(String(describing: characteristicUUID)) with message '\(message)'")
        let serviceUUID = serviceUUID ?? self.serviceUUID
        let characteristicUUID = characteristicUUID ?? self.characteristicUUID
        mode.rawValue < 1 ? startPeripheralMode(peripheralName: self.peripheralName, serviceUUID: serviceUUID, characteristicUUID: characteristicUUID) : ()
        peripheralManagerDelegate.testMessage = message
    }
        
    func subscribe(serviceUUID: CBUUID?, characteristicUUID: CBUUID?) {
        logger.debug("BluetoothManager.\(#function) called for service \(String(describing: serviceUUID)) and characteristic \(String(describing: characteristicUUID))")
        let serviceUUID = serviceUUID ?? self.serviceUUID
        let characteristicUUID = characteristicUUID ?? self.characteristicUUID
        // TODO: prepareScan
        mode.rawValue > -1 ? startCentralMode() : ()
    }
        
    private func startPeripheralMode(peripheralName: String!, serviceUUID: CBUUID!, characteristicUUID: CBUUID!) {
        stopCentralMode()
        setMode(to: .peripheral)
        peripheralManagerDelegate.prepareAdvertising(peripheralName: peripheralName, serviceUUID: serviceUUID, characteristicUUID: characteristicUUID)
        peripheralManagerDelegate.startAdvertising()
    }
    
    private func startCentralMode() {
        stopPeripheralMode()
        setMode(to: .central)
        centralManagerDelegate.startScan()
    }
    
    private func stopPeripheralMode() {
        peripheralManagerDelegate.stopAdvertising()
        setMode(to: .undefined)
    }
    
    private func stopCentralMode() {
        centralManagerDelegate.stopScan()
        setMode(to: .undefined)
    }
}
