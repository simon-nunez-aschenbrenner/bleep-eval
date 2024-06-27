//
//  Evaluation.swift
//  bleep-eval
//
//  Created by Simon Núñez Aschenbrenner on 26.06.24.
//

import Foundation
import OSLog
import UIKit

struct Simulator {
    
    static var isRunning = false
    
    static func start(with notificationManager: NotificationManager, runID: UInt, isSending: Bool, frequency: UInt = 0, variance: UInt = 0) {
        Simulator.isRunning = true
        notificationManager.evaluationLogger = EvaluationLogger(deviceName: notificationManager.address.name, runID: runID)
        Logger.evaluation.info("Simulator attempts to start(runID=\(runID), isSending=\(isSending),\(isSending ? " frequency=\(frequency)s, variance=±\(variance*25)%" : ""))")
        let destinations = Utils.addressBook.filter({ $0 != notificationManager.address })
        while Simulator.isRunning && isSending {// TODO: make non blocking!
            let destinationAddress = destinations.randomElement()!
            let message = Utils.generateText(with: Int.random(in: 77...notificationManager.maxMessageLength))
            let notification = notificationManager.create(destinationAddress: destinationAddress, message: message)
            notificationManager.insert(notification)
            notificationManager.save()
            sleep(UInt32(frequency+UInt(Float(frequency)*Float.random(in: Float(-Int(variance))/4...Float(variance)/4))))
        }
    }
    
    static func stop(with notificationManager: NotificationManager) {
        Logger.evaluation.info("Simulator attempts to stop")
        Simulator.isRunning = false
        notificationManager.evaluationLogger = nil
    }
    
}

class EvaluationLogger {
        
    private let deviceName: String!
    private let runID: UInt!
    private let fileManager: FileManager = FileManager.default
    private var fileURL: URL

    init(deviceName: String?, runID: UInt!) {
        self.deviceName = deviceName ?? "X"
        self.runID = runID
        self.fileURL = self.fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("bleep-eval.\(self.deviceName!).\(String(format: "%03u", self.runID)).log")
        if !fileManager.fileExists(atPath: fileURL.path) { fileManager.createFile(atPath: fileURL.path, contents: nil, attributes: nil) }
        Logger.evaluation.debug("EvaluationLogger initialized with fileURL '\(self.fileURL.path())'")
    }

    func log(_ notification: Notification, at address: Address) {
        // log entry format:
        // deviceName;runID;status;currentAddress;currentTimestamp;notificationID;protocolValue;destinationControlValue;sequenceNumberValue;sourceAddress;sentTimestamp;destinationAddress;receivedTimestamp;messageLength\n
        let currentTimestamp = Date.now
        Logger.evaluation.trace("EvaluationLogger attempts to log #\(Utils.printID(notification.hashedID)) at (\(Utils.printID(address.hashed)))")
        var stringBuilder: [String] = []
        // Data provided by the device
        stringBuilder.append(self.deviceName)
        stringBuilder.append(String(self.runID))
        var status: String = "0" // unknown/in transit
        if notification.receivedTimestamp == nil { status = "1" } // created
        else if notification.destinationControlValue == 0 { status = "2" } // received
        stringBuilder.append(status)
        stringBuilder.append(address.hashed.base64EncodedString()) // currentAddress
        stringBuilder.append(String(currentTimestamp.timeIntervalSinceReferenceDate as Double))
        // Data provided by the notification
        stringBuilder.append(notification.hashedID.base64EncodedString()) // notificationID
        stringBuilder.append(String(notification.protocolValue)) // 0 = epidemic, 1 = binary spray and wait, TODO: 2 = ???, 3 = ???
        stringBuilder.append(String(notification.destinationControlValue)) // 0 = nobody/reached destination, 1 = anybody, 2 = destination only, TODO: 3 = ???
        stringBuilder.append(String(notification.sequenceNumberValue)) // 0...15
        stringBuilder.append(notification.hashedSourceAddress.base64EncodedString())
        stringBuilder.append(String(notification.sentTimestamp.timeIntervalSinceReferenceDate as Double))
        stringBuilder.append(notification.hashedDestinationAddress.base64EncodedString())
        stringBuilder.append(notification.receivedTimestamp != nil ? String(notification.receivedTimestamp!.timeIntervalSinceReferenceDate as Double) : "")
        stringBuilder.append(String(notification.message.count)) // 0...419
        assert(status != "1" || address.hashed == notification.hashedSourceAddress)
        assert(status != "2" || address.hashed == notification.hashedDestinationAddress)
        let logEntry: String = stringBuilder.joined(separator: ";")
        Logger.evaluation.debug("EvaluationLogger attempts to append logEntry '\(logEntry)'")
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
