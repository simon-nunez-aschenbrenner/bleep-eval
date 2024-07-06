//
//  NotificationModel.swift
//  bleep-eval
//
//  Created by Simon Núñez Aschenbrenner on 18.06.24.
//

import Foundation
import CryptoKit
import SwiftData
import OSLog

// MARK: ControlByte

struct ControlByte: Codable, CustomStringConvertible, Equatable {
        
    private(set) var protocolValue: UInt8
    private(set) var destinationControlValue: UInt8
    private(set) var sequenceNumberValue: UInt8
    
    var value: UInt8 {
        var result = UInt8(0)
        result += protocolValue << 6
        result += destinationControlValue << 4
        result += sequenceNumberValue
        return result
    }
    
    var description: String {
        return "[P\(protocolValue) D\(destinationControlValue) S\(sequenceNumberValue)]"
    }
    
    init(protocolValue: UInt8, destinationControlValue: UInt8, sequenceNumberValue: UInt8) throws {
        guard protocolValue < 4 && destinationControlValue < 4 && sequenceNumberValue < 16 else { throw BleepError.invalidControlByteValue }
        self.protocolValue = protocolValue
        self.destinationControlValue = destinationControlValue
        self.sequenceNumberValue = sequenceNumberValue
//        try setProtocol(to: protocolValue)
//        try setDestinationControl(to: destinationControlValue)
//        try setSequenceNumber(to: sequenceNumberValue)
    }
    
    init(_ value: UInt8) {
        let protocolValue: UInt8 = (value >> 6) & 0b00000011
        let destinationControlValue: UInt8 = (value >> 4) & 0b00000011
        let sequenceNumberValue: UInt8 = value & 0b00001111
        try! self.init(protocolValue: protocolValue, destinationControlValue: destinationControlValue, sequenceNumberValue: sequenceNumberValue)
    }
    
    mutating func setProtocol(to value: UInt8) throws {
        guard value < 4 else { throw BleepError.invalidControlByteValue }
        self.protocolValue = value
    }
    
    mutating func setDestinationControl(to value: UInt8) throws {
        guard value < 4 else { throw BleepError.invalidControlByteValue }
        self.destinationControlValue = value
    }
    
    mutating func setSequenceNumber(to value: UInt8) throws {
        guard value < 16 else { throw BleepError.invalidControlByteValue }
        self.sequenceNumberValue = value
    }
    
}

// MARK: Notification

@Model
class Notification: Equatable, Comparable, CustomStringConvertible, Hashable {
    
//    private(set) var protocolValue: UInt8!
//    private(set) var destinationControlValue: UInt8!
//    private(set) var sequenceNumberValue: UInt8!
//    
//    var controlByte: UInt8 {
//        var result = UInt8(0)
//        result += protocolValue << 6
//        result += destinationControlValue << 4
//        result += sequenceNumberValue
//        return result
//    }
    
    var controlByte: ControlByte
    @Attribute(.unique) let hashedID: Data
    let hashedSourceAddress: Data
    let hashedDestinationAddress: Data
    var sentTimestampData: Data { return Notification.encodeTimestamp(date: sentTimestamp) }
    var message: String
    
    let sentTimestamp: Date
    let receivedTimestamp: Date?
    var hasBeenAcknowledged: Bool = false
    var lastRediscovery: Date? {
        didSet { Logger.notification.debug("Notification #\(self.hashedID) lastRediscovery set to \(self.lastRediscovery)") }
    }
    
    var description: String {
        return "#\(Utils.printID(hashedID)) \(controlByte.description) from (\(Utils.printID(hashedSourceAddress))) at \(Utils.printTimestamp(sentTimestamp)) to (\(Utils.printID(hashedDestinationAddress)))\(receivedTimestamp == nil ? "" : " at " + Utils.printTimestamp(receivedTimestamp!)) and message length \(message.count)"
    }
    
    // Used by provider
    init(controlByte: ControlByte, sourceAddress: Address, destinationAddress: Address, message: String) {
//        self.protocolValue = controlByte.protocolValue
//        self.destinationControlValue = controlByte.destinationControlValue
//        self.sequenceNumberValue = controlByte.sequenceNumberValue
        let id = String(sourceAddress.rawValue).appendingFormat("%064u", UInt64.random(in: UInt64.min...UInt64.max))
        self.hashedID = Data(SHA256.hash(data: id.data(using: .utf8)!))
        self.controlByte = controlByte
        self.hashedSourceAddress = sourceAddress.hashed
        self.hashedDestinationAddress = destinationAddress.hashed
        self.sentTimestamp = Date()
        self.receivedTimestamp = nil
        self.message = message
        Logger.notification.debug("Notification \(self.description) with message '\(self.message)' initialized")
    }
    
    // Used by consumer
    init(controlByte: ControlByte, hashedID: Data, hashedDestinationAddress: Data, hashedSourceAddress: Data, sentTimestampData: Data, message: String) {
//        self.protocolValue = controlByte.protocolValue
//        self.destinationControlValue = controlByte.destinationControlValue
//        self.sequenceNumberValue = controlByte.sequenceNumberValue
        self.hashedID = hashedID
        self.controlByte = controlByte
        self.hashedSourceAddress = hashedSourceAddress
        self.hashedDestinationAddress = hashedDestinationAddress
        self.sentTimestamp = Notification.decodeTimestamp(data: sentTimestampData)
        self.receivedTimestamp = Date.now
        self.message = message
        Logger.notification.debug("Notification \(self.description) with message '\(self.message)' initialized")
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(hashedID)
    }
    
    static func encodeTimestamp(date: Date) -> Data {
        return withUnsafeBytes(of: date.timeIntervalSinceReferenceDate.bitPattern.bigEndian) { Data($0) }
    }
    
    static func decodeTimestamp(data: Data) -> Date {
        assert(data.count == 8)
        return Date(timeIntervalSinceReferenceDate: TimeInterval(bitPattern: data.withUnsafeBytes { $0.load(as: UInt64.self).bigEndian }))
    }
    
    static func == (lhs: Notification, rhs: Notification) -> Bool {
        return lhs.hashedID == rhs.hashedID
    }
    
    static func < (lhs: Notification, rhs: Notification) -> Bool {
        return lhs.receivedTimestamp ?? lhs.sentTimestamp < rhs.receivedTimestamp ?? rhs.sentTimestamp
    }
}
