//
//  AddressModel.swift
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
    static let Alphabet = [UInt8]("123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz".utf8)
    
    let rawValue: UInt64!
    
    @Transient var data: Data {
        return withUnsafeBytes(of: rawValue.bigEndian) { Data($0) }
    }
    @Transient var hashed: Data {
        return Data(SHA256.hash(data: data))
    }
    @Transient var base58Encoded: String {
        return Address.encode(rawValue)
    }
    
    init() {
        self.rawValue = UInt64.random(in: 1...UInt64.max) // 0 reserved for Broadcast
        Logger.notification.trace("Address initialized")
    }
    
    init(_ value: UInt64) {
        self.rawValue = value
        Logger.notification.trace("Address initialized")
    }
    
    init?(_ base58: String) {
        self.rawValue = Address.decode(base58)
    }
    
    static func decode(_ base58: String) -> Address? {
        return Address(base58)
    }
    
    static func decode(_ base58: String) -> UInt64? {
        var result = UInt64(0)
        var integer = UInt64(1)
        let byteArray = [UInt8](base58.utf8)
        for char in byteArray.reversed() {
            guard let alphabetIndex = Alphabet.firstIndex(of: char) else {
                return nil
            }
            result += (integer * UInt64(alphabetIndex))
            integer &*= 58
        }
        return result
    }
    
    static func encode(_ integer: UInt64) -> String {
        var integer = integer
        var result = ""
        if integer == 0 {
            return String(Character(Unicode.Scalar(Alphabet[0])))
        }
        while integer > 0 {
            let remainder = Int(integer % 58)
            integer /= 58
            result.append(Character(Unicode.Scalar(Alphabet[remainder])))
        }
        return String(result.reversed())
    }
    
    static func encode(_ data: Data) -> String {
        let integer = data.withUnsafeBytes { $0.load(as: UInt64.self).bigEndian }
        return Address.encode(integer)
    }
    
    static func hash(_ data: Data) -> Data {
        return Data(SHA256.hash(data: data))
    }
}

// TODO: Persistence, address manager
