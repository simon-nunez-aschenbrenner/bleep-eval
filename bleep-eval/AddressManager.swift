//
//  AddressManager.swift
//  bleep-eval
//
//  Created by Simon Núñez Aschenbrenner on 12.06.24.
//

import Foundation
import CryptoKit
import OSLog
import SwiftData

@Model
class Address {
    
    static let Broadcast = Address(0)
    
    let rawValue: UInt64!
    @Transient var data: Data {
        return withUnsafeBytes(of: rawValue.littleEndian) { Data($0) }
    }
    @Transient var hashed: Data {
        return Data(SHA256.hash(data: String(rawValue).data(using: .utf8)!))
    }
    @Transient var base58Encoded: String {
        return Address.encode(rawValue)
    }
    @Transient var other: Data {
        let otherAddress = UInt64(rawValue &- UInt64.random(in: 1...UInt64.max))
        return withUnsafeBytes(of: otherAddress.littleEndian) { Data($0) }
    }
    
    init() {
        self.rawValue = UInt64.random(in: 1...UInt64.max) // 0 reserved for Broadcast
        Logger.notification.trace("Address \(printID(self.rawValue)) initialized")
    }
    
    init(_ value: UInt64) {
        self.rawValue = value
        Logger.notification.trace("Address \(printID(self.rawValue)) initialized")
    }
    
    static func encode(_ integer: UInt64) -> String {
        Logger.notification.trace("In Address.\(#function)")
        let alphabet = Array("123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz")
        var integer = integer
        var result = ""
        while integer > 0 {
            let remainder = Int(integer % 58)
            integer /= 58
            result.append(alphabet[remainder])
        }
        return String(result.reversed())
    }
    
    static func encode(_ data: Data) -> String {
        let integer = data.withUnsafeBytes { $0.load(as: UInt64.self).littleEndian }
        return Address.encode(integer)
    }
    
    static func hash(_ data: Data) -> Data {
        Logger.notification.trace("In Address.\(#function)")
        return Data(SHA256.hash(data: data))
    }
}

// TODO: Persistence, address manager
