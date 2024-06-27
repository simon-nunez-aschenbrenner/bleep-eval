//
//  Utils.swift
//  bleep-eval
//
//  Created by Simon Núñez Aschenbrenner on 13.06.24.
//

import CoreBluetooth
import Foundation
import OSLog

enum BleepError: Error {
    case invalidControlByteValue, invalidAddress
}

extension Logger {
    private static var subsystem = Bundle.main.bundleIdentifier!
    static let view = Logger(subsystem: subsystem, category: "view")
    static let evaluation = Logger(subsystem: subsystem, category: "evaluation")
    static let notification = Logger(subsystem: subsystem, category: "notification")
    static let bluetooth = Logger(subsystem: subsystem, category: "bluetooth")
    static let peripheral = Logger(subsystem: subsystem, category: "peripheral")
    static let central = Logger(subsystem: subsystem, category: "central")
}

struct Utils {
    
    static let addressBook: [Address] = [
        Address("XVQ6uh5nTLN", name: "Simon")!,
        Address("3NHph2xbJS4", name: "A")!
    ]

    static let suffixLength: Int = 5
    
    static func generateText(with length: Int) -> String {
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
    
    static func printID(_ data: Data?) -> String {
        return printID(data?.map { String($0) }.joined() ?? "")
    }
    
    static func printID(_ int: UInt64) -> String {
        return printID(String(int))
    }
    
    static func printID(_ string: String?) -> String {
        return String(string?.suffix(suffixLength) ?? "")
    }
    
    static func printTimestamp(_ date: Date) -> String {
        return String(date.description.dropLast(6))
    }
}
