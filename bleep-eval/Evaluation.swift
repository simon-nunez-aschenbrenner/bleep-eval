//
//  Evaluation.swift
//  bleep-eval
//
//  Created by Simon Núñez Aschenbrenner on 26.06.24.
//

import Foundation
import OSLog
import UIKit

class EvaluationLogger {
    
    static let instance = EvaluationLogger()
    
    var runID: Int = 0 {
        didSet {
            Logger.evaluation.debug("EvaluationLogger didSet runID to \(self.runID)")
        }
    }
    
    private let deviceName: String = UIDevice.current.name // TODO: wrong!
    private let fileManager: FileManager = FileManager.default
    private var fileURL: URL

    init() {
        self.fileURL = self.fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("bleep-eval.\(self.deviceName).log")
        if !fileManager.fileExists(atPath: fileURL.path) { fileManager.createFile(atPath: fileURL.path, contents: nil, attributes: nil) }
        Logger.evaluation.debug("EvaluationLogger initialized with fileURL '\(self.fileURL.path())'")
    }

    func log(_ notification: Notification, at address: Address) {
        let now = Date.now
        Logger.evaluation.trace("EvaluationLogger attempts to log #\(printID(notification.hashedID)) at (\(printID(address.hashed)))")
        // Data provided by the device
        let runID: String = String(self.runID)
        let deviceName: String = self.deviceName
        var status: String = "0" // unknown/in transit
        if notification.receivedTimestamp == nil { status = "1" } // created
        else if notification.destinationControlValue == 0 { status = "2" } // received
        let currentAddress: String = String(decoding: address.hashed, as: UTF8.self)
        let currentTimestamp: String = String(now.timeIntervalSinceReferenceDate as Double)
        // Data provided by the notification
        let notificationID: String = String(decoding: notification.hashedID, as: UTF8.self) // unique
        let protocolValue: String = String(notification.protocolValue) // 0 = epidemic, 1 = binary spray and wait, TODO: 2 = ???, 3 = ???
        let destinationControlValue: String = String(notification.destinationControlValue) // 0 = nobody/reached destination, 1 = anybody, 2 = destination only, TODO: 3 = ???
        let sequenceNumberValue: String = String(notification.sequenceNumberValue) // 0...15
        let sourceAddress: String = String(decoding: notification.hashedSourceAddress, as: UTF8.self)
        let sentTimestamp: String = String(notification.sentTimestamp.timeIntervalSinceReferenceDate as Double)
        let destinationAddress: String = String(decoding: notification.hashedDestinationAddress, as: UTF8.self)
        var receivedTimestamp: String = ""
        if notification.receivedTimestamp != nil { receivedTimestamp = String(notification.receivedTimestamp!.timeIntervalSinceReferenceDate as Double) }
        let messageLength = String(notification.message.count) // 0...419
        assert(status != "1" || currentAddress == sourceAddress)
        assert(status != "2" || currentAddress == destinationAddress)
        // TODO: logEntry not longer than "\(runID);\(deviceName);\(status);" why? rather work with Data?
        let logEntry: String = "\(runID);\(deviceName);\(status);\(currentAddress);\(currentTimestamp);\(notificationID);\(protocolValue);\(destinationControlValue);\(sequenceNumberValue);\(sourceAddress);\(sentTimestamp);\(destinationAddress);\(receivedTimestamp);\(messageLength)"
        Logger.evaluation.info("EvaluationLogger attempts to append logEntry '\(logEntry)'")
        let logEntryData = logEntry.appending("\n").data(using: .utf8)
        if let fileHandle = try? FileHandle(forWritingTo: fileURL) {
            fileHandle.seekToEndOfFile()
            fileHandle.write(logEntryData!)
            fileHandle.closeFile()
            Logger.evaluation.trace("EvaluationLogger successfully appended the logEntry to the log file")
        } else {
            Logger.evaluation.fault("EvaluationLogger was unable to append the logEntry to the log file")
        }
    }
}
