//
//  Helper.swift
//  bleep-eval
//
//  Created by Simon Núñez Aschenbrenner on 13.06.24.
//

import CoreBluetooth
import Foundation

let minMessageLength: Int = 105
let maxMessageLength: Int = 524 - minMessageLength
let suffixLength: Int = 5
let version: Int = 1

enum BleepError: Error {
    case invalidControlByteValue
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
    default:
        return "'\(cbuuid.uuidString)'"
    }
}

func maxSupportedControlByteValue(for notificationManager: NotificationManager) -> Int {
    switch notificationManager {
    case is SimpleNotificationManager:
        return 63
    default:
        return -1
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
