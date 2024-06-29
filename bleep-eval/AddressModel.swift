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
import UIKit

@Model
class Address: CustomStringConvertible, Equatable {
    
    static let base58Alphabet = [UInt8]("123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz".utf8)
    static let minRawValue: UInt64 = 1 // 0 reserved for Broadcast
    
    let rawValue: UInt64!
    @Attribute(.unique) let isOwn: Bool!
    var name: String?
    
    var data: Data {
        return withUnsafeBytes(of: rawValue.bigEndian) { Data($0) }
    }
    var hashed: Data {
        return Data(SHA256.hash(data: data))
    }
    var base58Encoded: String {
        return encode(rawValue)
    }
    var description: String {
        return "\(self.name == nil ? "" : "'\(self.name!)' ")\(self.base58Encoded) (\(Utils.printID(self.hashed)))\(self.isOwn ? " isOwn" : "")"
    }
    
    init() {
        self.rawValue = UInt64.random(in: Address.minRawValue...UInt64.max)
        self.isOwn = true
        Logger.notification.trace("Random address initialized: \(self.description)")
    }
    
    init(name: String) {
        self.rawValue = UInt64.random(in: Address.minRawValue...UInt64.max)
        self.isOwn = true
        self.name = name
        Logger.notification.trace("Random address initialized: \(self.description)")
    }
    
    init?(_ base58: String) {
        guard let value: UInt64 = self.decode(base58) else { return nil }
        self.rawValue = value
        self.isOwn = false
        Logger.notification.trace("Address initialized: \(self.description)")
    }
    
    init?(_ base58: String, name: String) {
        guard let value: UInt64 = self.decode(base58) else { return nil }
        self.rawValue = value
        self.isOwn = false
        self.name = name
        Logger.notification.trace("Address initialized: \(self.description)")
    }
    
    private func decode(_ base58: String) -> UInt64? {
        var result = UInt64(0)
        var integer = UInt64(1)
        let byteArray = [UInt8](base58.utf8)
        for char in byteArray.reversed() {
            guard let alphabetIndex = Address.base58Alphabet.firstIndex(of: char) else {
                return nil
            }
            result += (integer * UInt64(alphabetIndex))
            integer &*= 58
        }
        return result
    }
    
    private func encode(_ integer: UInt64) -> String {
        var integer = integer
        var result = ""
        if integer == 0 {
            return String(Character(Unicode.Scalar(Address.base58Alphabet[0])))
        }
        while integer > 0 {
            let remainder = Int(integer % 58)
            integer /= 58
            result.append(Character(Unicode.Scalar(Address.base58Alphabet[remainder])))
        }
        return String(result.reversed())
    }
    
    static func == (lhs: Address, rhs: Address) -> Bool {
        return lhs.rawValue == rhs.rawValue
    }

}
