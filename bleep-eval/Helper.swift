//
//  Helper.swift
//  bleep-eval
//
//  Created by Simon Núñez Aschenbrenner on 13.06.24.
//

import CoreBluetooth
import Foundation

let addressBook: [Address] = [Address("XVQ6uh5nTLN", name: "Simon")!, Address("3NHph2xbJS4", name: "A")!]
let base58Alphabet = [UInt8]("123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz".utf8)
let minAddressRawValue: UInt64 = 1 // 0 reserved for Broadcast

let minNotificationLength: Int = 105
let maxMessageLength: Int = 524 - minNotificationLength
let acknowledgementLength: Int = 32

let suffixLength: Int = 5

enum BleepError: Error {
    case invalidControlByteValue
    case invalidAddress
}

struct BluetoothConstants {
    
    static let serviceUUID = CBUUID(string: "08373f8c-3635-4b88-8664-1ccc65a60aae")
    static let notificationSourceUUID = CBUUID(string: "c44f6cf4-5bdd-4c8a-b72c-2931be44af0a")
    static let notificationAcknowledgementUUID = CBUUID(string: "9e201989-0725-4fa6-8991-5a1ed1c084b1")
    
    static let peripheralName = "bleeper"
    static let centralIdentifierKey = "com.simon.bleep-eval.central"
    static let peripheralIdentifierKey = "com.simon.bleep-eval.peripheral"
    
}

func generateText(with length: Int = maxMessageLength) -> String {
    let end = " // This test message contains \(length) ASCII characters. The last visible digit indicates the number of characters missing: 9876543210"
    var result = ""
    if end.count > length {
        result = String(end.suffix(length))
    } else {
        for _ in 0..<length - end.count {
            result.append(Character(Unicode.Scalar(UInt8.random(in: 21...126))))
        }
        result.append(end)
    }
    assert(result.count == length)
    return result
}

func getName(of cbuuid: CBUUID) -> String {
    switch cbuuid.uuidString {
    case BluetoothConstants.serviceUUID.uuidString:
        return "Bleep Notification Service"
    case BluetoothConstants.notificationSourceUUID.uuidString:
        return "Notification Source Characteristic"
    case BluetoothConstants.notificationAcknowledgementUUID.uuidString:
        return "Notification Acknowledgement Characteristic"
    default:
        return "\(cbuuid.uuidString)"
    }
}

func printID(_ data: Data?) -> String {
    return printID(data?.map { String($0) }.joined() ?? "")
}

func printID(_ int: UInt64) -> String {
    return printID(String(int))
}

func printID(_ string: String?) -> String {
    return String(string?.suffix(suffixLength) ?? "")
}

func printTimestamp(_ date: Date) -> String {
    return String(date.description.dropLast(6))
}
