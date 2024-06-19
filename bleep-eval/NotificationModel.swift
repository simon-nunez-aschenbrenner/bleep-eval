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

struct ControlByte {
    
    let protocolValue: UInt8
    let destinationControlValue: UInt8
    let sequenceNumberValue: UInt8
    
    var value: UInt8 {
        var result = UInt8(0)
        result += protocolValue << 6
        result += destinationControlValue << 4
        result += sequenceNumberValue
        return result
    }
    
    init(protocolValue: UInt8, destinationControlValue: UInt8, sequenceNumberValue: UInt8) throws {
        guard protocolValue < 4, destinationControlValue < 4, sequenceNumberValue < 16 else { throw BleepError.invalidControlByteValue }
        self.protocolValue = protocolValue
        self.destinationControlValue = destinationControlValue
        self.sequenceNumberValue = sequenceNumberValue
    }
    
    init(value: UInt8) {
        let protocolValue: UInt8 = (value >> 6) & 0b00000011
        let destinationControlValue: UInt8 = (value >> 4) & 0b00000011
        let sequenceNumberValue: UInt8 = value & 0b00001111
        try! self.init(protocolValue: protocolValue, destinationControlValue: destinationControlValue, sequenceNumberValue: sequenceNumberValue)
    }
}

// MARK: Notification

@Model
class Notification: CustomStringConvertible {
    
    private(set) var protocolValue: UInt8!
    private(set) var destinationControlValue: UInt8!
    private(set) var sequenceNumberValue: UInt8!
    
    var controlByte: UInt8 {
        var result = UInt8(0)
        result += protocolValue << 6
        result += destinationControlValue << 4
        result += sequenceNumberValue
        return result
    }
    
    @Attribute(.unique) let hashedID: Data!
    
    let hashedSourceAddress: Data!
    let hashedDestinationAddress: Data!
    let sentTimestamp: Date!
    var sentTimestampData: Data { return Notification.encodeTimestamp(date: sentTimestamp) }
    let receivedTimestamp: Date?
    let message: String!
    
    var description: String {
        return "#\(printID(hashedID)) [P=\(protocolValue!) D=\(destinationControlValue!) S=\(sequenceNumberValue!)] from (\(printID(hashedSourceAddress))) at \(printTimestamp(sentTimestamp)) to (\(printID(hashedDestinationAddress)))\(receivedTimestamp == nil ? "" : " at " + printTimestamp(receivedTimestamp!)) and message length \(message.count)"
    }
    
    // Used by sender
    init(controlByte: ControlByte!, sourceAddress: Address!, destinationAddress: Address!, message: String!) {
        self.protocolValue = controlByte.protocolValue
        self.destinationControlValue = controlByte.destinationControlValue
        self.sequenceNumberValue = controlByte.sequenceNumberValue
        let id = String(sourceAddress.rawValue).appendingFormat("%064u", UInt64.random(in: UInt64.min...UInt64.max)) // TODO: replace with UInt128 in the future
        self.hashedID = Data(SHA256.hash(data: id.data(using: .utf8)!))
        self.hashedSourceAddress = sourceAddress.hashed
        self.hashedDestinationAddress = destinationAddress.hashed
        self.sentTimestamp = Date()
        self.receivedTimestamp = nil
        self.message = message
        Logger.notification.debug("Initialized Notification \(self.description) with message '\(self.message)'")
    }
    
    // Used by receiver
    init(controlByte: ControlByte!, hashedID: Data!, hashedDestinationAddress: Data!, hashedSourceAddress: Data!, sentTimestampData: Data!, message: String!) {
        self.protocolValue = controlByte.protocolValue
        self.destinationControlValue = controlByte.destinationControlValue
        self.sequenceNumberValue = controlByte.sequenceNumberValue
        self.hashedID = hashedID
        self.hashedSourceAddress = hashedSourceAddress
        self.hashedDestinationAddress = hashedDestinationAddress
        self.sentTimestamp = Notification.decodeTimestamp(data: sentTimestampData)
        self.receivedTimestamp = Date()
        self.message = message
        Logger.notification.debug("Initialized Notification \(self.description) with message '\(self.message)'")
    }
    
    static func encodeTimestamp(date: Date) -> Data {
        return withUnsafeBytes(of: date.timeIntervalSinceReferenceDate.bitPattern.bigEndian) { Data($0) }
    }
    
    static func decodeTimestamp(data: Data) -> Date {
        assert(data.count == 8)
        return Date(timeIntervalSinceReferenceDate: TimeInterval(bitPattern: data.withUnsafeBytes { $0.load(as: UInt64.self).bigEndian }))
    }
    
    func setDestinationControl(to value: UInt8) throws {
        guard value < 4 else { throw BleepError.invalidControlByteValue }
        self.destinationControlValue = value
    }
    
    func setSequenceNumber(to value: UInt8) throws {
        guard value < 16 else { throw BleepError.invalidControlByteValue }
        self.sequenceNumberValue = value
    }
    
    func incrementSequenceNumber() throws {
        guard self.sequenceNumberValue < 15 else { throw BleepError.invalidControlByteValue }
        self.sequenceNumberValue += 1
    }
    
    func decrementSequenceNumber() throws {
        guard self.sequenceNumberValue > 0 else { throw BleepError.invalidControlByteValue }
        self.sequenceNumberValue -= 1
    }
}
