//
//  PeripheralManager.swift
//  bleep-eval
//
//  Created by Simon Núñez Aschenbrenner on 04.05.24.
//

import Foundation
import CoreBluetooth

class PeripheralManager: NSObject, ObservableObject, CBPeripheralManagerDelegate {
    static let shared = PeripheralManager()
    var peripheralManager: CBPeripheralManager = CBPeripheralManager()
    
    let serviceUUID: CBUUID = CBUUID(string: "d50cfc1b-9fc7-4f07-9fa0-fe7cd33f3e92")
    let characteristicUUID: CBUUID = CBUUID(string: "f03a20be-b7e9-44cf-b156-685fe9762504")
    let advertisementDataLocalNameKey: String = "max8Chars"
    
    func start() {
        if !peripheralManager.isAdvertising {
            peripheralManager = CBPeripheralManager(delegate: self, queue: nil, options: [CBPeripheralManagerOptionRestoreIdentifierKey: "com.simon.bleep-eval.peripheral"])
        }
    }
    
    func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        
        switch self.peripheralManager.state {
            
        case .unknown:
            print("Peripheral state unknown")
        case .resetting:
            print("Peripheral state resetting")
        case .unsupported:
            print("Peripheral state unsupported")
        case .unauthorized:
            print("Peripheral state unauthorized")
        case .poweredOff:
            print("Peripheral state poweredOff")
        case .poweredOn:
            print("Peripheral state poweredOn")
            
            let mutableService: CBMutableService = CBMutableService(type: serviceUUID, primary: true)
            let mutableCharacteristic: CBMutableCharacteristic = CBMutableCharacteristic(type: characteristicUUID, properties: [.write, .read], value: nil, permissions: [.writeable, .readable])
            mutableService.characteristics = [mutableCharacteristic]
            self.peripheralManager.add(mutableService)
            self.peripheralManager.startAdvertising([CBAdvertisementDataServiceUUIDsKey: [serviceUUID], CBAdvertisementDataLocalNameKey: advertisementDataLocalNameKey])
            
        @unknown default:
            fatalError()
        }
    }
    
    func peripheralManager(_ peripheral: CBPeripheralManager, willRestoreState dict: [String : Any]) {
        peripheral.delegate = self
        self.peripheralManager = peripheral
        
        if !self.peripheralManager.isAdvertising {
            self.peripheralManager.startAdvertising([CBAdvertisementDataServiceUUIDsKey: [serviceUUID], CBAdvertisementDataLocalNameKey: advertisementDataLocalNameKey])
        }
    }
    
    func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveRead request: CBATTRequest) {
        var arr: [UInt8] = [0,1,2,3,4]
        let value: Data = Data(bytes: &arr, count: arr.count)
        request.value = value
        self.peripheralManager.respond(to: request, withResult: .success)
    }
    
    func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveWrite requests: [CBATTRequest]) {
        if let request = requests.first {
            if let value = request.value {
                let valueBytes: [UInt8] = [UInt8](value)
                print("Received data: \(valueBytes)")
            }
        }
    }
    
}

