//
//  BluetoothPublisherSubscriber.swift
//  bleep-eval
//
//  Created by Simon Núñez Aschenbrenner on 10.05.24.
//

import Foundation
import CoreBluetooth

protocol BluetoothDevice {
    
    var serviceUUID: CBUUID! { get }
    var characteristicUUID: CBUUID! { get }
    
}

protocol BluetoothPublisher: BluetoothDevice {
    
    var peripheralManagerDelegate: PeripheralManagerDelegate! { get }
    var peripheralName: String! { get }
    var outgoingTestMessage: String? { get }
    
    func publish(serviceUUID: CBUUID?, characteristicUUID: CBUUID?, message: String)

}

protocol BluetoothSubscriber: BluetoothDevice {
    
    var centralManagerDelegate: CentralManagerDelegate! { get }
    var incomingTestMessage: String? { get }
    
    func subscribe(serviceUUID: CBUUID?, characteristicUUID: CBUUID?)
    
}
