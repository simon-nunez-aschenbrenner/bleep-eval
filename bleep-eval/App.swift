//
//  App.swift
//  bleep-eval
//
//  Created by Simon Núñez Aschenbrenner on 03.05.24.
//

import Foundation
import SwiftData
import SwiftUI
import OSLog

let addressBook: [Address] = [Address("XVQ6uh5nTLN", name: "Simon")!, Address("3NHph2xbJS4", name: "A")!, Address("4nhPH3XBjs5", name: "X")!] // TODO: needs better solution

let suffixLength: Int = 5
let base58Alphabet = [UInt8]("123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz".utf8)
let minAddressRawValue: UInt64 = 1 // 0 reserved for Broadcast
let minNotificationLength: Int = 105
let maxMessageLength: Int = 524 - minNotificationLength
let acknowledgementLength: Int = 32

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

@main
struct bleepEvalApp: App {

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
