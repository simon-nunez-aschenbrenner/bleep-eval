//
//  Evaluation.swift
//  bleep-eval
//
//  Created by Simon Núñez Aschenbrenner on 26.06.24.
//

import Foundation
import OSLog
import UIKit

@Observable
class Simulator {
    
    static let minMessageLength = 77
    
    unowned var notificationManager: NotificationManager
    let runID: UInt
    let isSending: Bool
    let frequency: UInt
    let variance: UInt
    let destinations: [Address]
    var isRunning: Bool
    
    private var timer: DispatchSourceTimer?
    
    init(notificationManager: NotificationManager, runID: UInt, isSending: Bool, frequency: UInt = 0, variance: UInt = 0) {
        Logger.evaluation.trace("Simulator initializes")
        self.notificationManager = notificationManager
        self.runID = runID
        self.isSending = isSending
        self.frequency = frequency
        self.variance = variance
        self.destinations = Utils.addressBook.filter({ $0 != notificationManager.address })
        self.isRunning = false
        Logger.evaluation.debug("Simulator initialized with runID=\(runID), isSending=\(isSending),\(isSending ? " frequency=\(frequency)s, variance=±\(variance*25)%" : "")")
    }
    
    func start() {
        Logger.evaluation.trace("Simulator attempts to \(#function)")
        stop()
        self.notificationManager.evaluationLogger = EvaluationLogger(deviceName: notificationManager.address.name, runID: runID)
        self.isRunning = true
        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.global())
        self.timer = timer
        schedule(timer)
        timer.resume()
    }
    
    private func schedule(_ timer: DispatchSourceTimer) {
        Logger.evaluation.trace("Simulator attempts to \(#function)")
        let frequency = Double(self.frequency)
        let variance = Double(self.variance)
        let interval = frequency * Double.random(in: 1-variance/4...1+variance/4)
        timer.schedule(deadline: .now() + interval)
        timer.setEventHandler {
            let notification = self.notificationManager.create(destinationAddress: self.destinations.randomElement()!, message: Utils.generateText(with: Int.random(in: Simulator.minMessageLength...self.notificationManager.maxMessageLength)))
            self.notificationManager.insert(notification)
            self.notificationManager.save()
            self.schedule(timer)
        }
    }
    
    func stop() {
        Logger.evaluation.trace("Simulator attempts to \(#function)")
        self.timer?.cancel()
        self.timer = nil
        self.notificationManager.evaluationLogger = nil
        self.isRunning = false
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
        Logger.evaluation.trace("EvaluationLogger attempts to log notification #\(Utils.printID(notification.hashedID)) at (\(Utils.printID(address.hashed)))")
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
