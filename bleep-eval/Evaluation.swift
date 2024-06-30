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
    
    unowned private var notificationManager: NotificationManager
    private let runID: UInt
    private let isSending: Bool
    private let frequency: UInt
    private let variance: Float
    private let destinations: Set<Address>
    
    private(set) var isRunning: Bool
    private(set) var logFileURL: URL?
    private var timer: DispatchSourceTimer?
    
    init(notificationManager: NotificationManager, runID: UInt, rssiThresholdFactor: Int8, isSending: Bool, frequency: UInt = 0, varianceFactor: UInt8 = 0, numberOfCopies: UInt8, destinations: Set<Address> = []) {
        Logger.evaluation.trace("Simulator initializes")
        
        notificationManager.evaluationLogger = EvaluationLogger(deviceName: notificationManager.address.name, runID: runID, clearExistingLog: true) // TODO: change to false
        notificationManager.rssiThreshold = Int8(rssiThresholdFactor * 8)
        try? notificationManager.setNumberOfCopies(to: numberOfCopies)
        self.notificationManager = notificationManager
        
        self.runID = runID
        self.isSending = isSending
        self.frequency = frequency
        self.variance = min(Float(varianceFactor), 4.0) * 0.25
        self.destinations = destinations
        self.isRunning = false
        Logger.evaluation.debug("Simulator initialized with runID=\(runID), rssiThreshold=\(rssiThresholdFactor * 8), isSending=\(isSending)\(isSending ? ", frequency=\(frequency)s, variance=±\(Int(self.variance*100))%, numberOfCopies=\(numberOfCopies), destinations=\(destinations)" : "")")
    }
    
    func start() {
        Logger.evaluation.debug("Simulator attempts to \(#function)")
        isRunning = true
        logFileURL = nil
        timer?.cancel()
        timer = nil
        if isSending {
            timer = DispatchSource.makeTimerSource(queue: DispatchQueue.global())
            schedule(timer!)
            timer!.resume()
        }
    }
    
    private func schedule(_ timer: DispatchSourceTimer) {
        Logger.evaluation.trace("Simulator attempts to \(#function)")
        let frequency = Double(self.frequency)
        let variance = Double(self.variance)
        let interval = frequency * Double.random(in: 1-variance...1+variance)
        timer.schedule(deadline: .now() + interval)
        timer.setEventHandler {
            let notification = self.notificationManager.create(destinationAddress: self.destinations.randomElement()!, message: Utils.generateText(with: Int.random(in: Simulator.minMessageLength...self.notificationManager.maxMessageLength)))
            self.notificationManager.insert(notification)
            self.schedule(timer)
        }
    }
    
    func stop() {
        Logger.evaluation.trace("Simulator attempts to \(#function)")
        logFileURL = notificationManager.evaluationLogger?.fileURL
        timer?.cancel()
        timer = nil
        notificationManager.evaluationLogger = nil
        notificationManager.rssiThreshold = Int8.min
        try! notificationManager.setNumberOfCopies(to: Utils.initialNumberOfCopies)
        isRunning = false
    }
    
}

class EvaluationLogger {
        
    private let deviceName: String!
    private let runID: UInt!
    private let fileManager: FileManager = FileManager.default
    var fileURL: URL

    init(deviceName: String?, runID: UInt!, clearExistingLog: Bool = false) {
        Logger.evaluation.debug("EvaluationLogger initializes with runID \(runID)")
        self.deviceName = deviceName ?? "unknown"
        self.runID = runID
        self.fileURL = self.fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("bleep-eval.\(self.deviceName!).\(String(format: "%02u", self.runID)).csv")
        if !fileManager.fileExists(atPath: fileURL.path) {
            fileManager.createFile(atPath: fileURL.path, contents: nil, attributes: nil)
            Logger.evaluation.trace("EvalutaionLogger created a new log file")
        }
        else if clearExistingLog {
            if let fileHandle = try? FileHandle(forWritingTo: fileURL) {
                do {
                    try fileHandle.truncate(atOffset: 0)
                    Logger.evaluation.warning("EvalutaionLogger cleared the existing log for runID \(runID)")
                } catch {
                    Logger.evaluation.fault("EvaluationLogger was unable to clear the existing log for runID \(runID)")
                    }
                fileHandle.closeFile()
            } else {
                Logger.evaluation.fault("EvaluationLogger was unable to clear the existing log for runID \(runID)")
            }
            
        }
        Logger.evaluation.debug("EvaluationLogger initialized with fileURL '\(self.fileURL.path())'")
    }

    func log(_ notification: Notification, at address: Address) {
        // log entry format:
        // deviceName;runID;currentAddress;currentTimestamp;status;notificationID;protocolValue;destinationControlValue;sequenceNumberValue;sourceAddress;sentTimestamp;destinationAddress;receivedTimestamp;messageLength\n
        let currentTimestamp = Date.now
        Logger.evaluation.trace("EvaluationLogger attempts to log notification #\(Utils.printID(notification.hashedID)) at (\(Utils.printID(address.hashed)))")
        var stringBuilder: [String] = []
        // Data provided by the device
        stringBuilder.append(self.deviceName)
        stringBuilder.append(String(self.runID))
        stringBuilder.append(address.hashed.base64EncodedString()) // currentAddress
        stringBuilder.append(String(currentTimestamp.timeIntervalSinceReferenceDate as Double))
        var status: String = "0" // unknown
        if notification.receivedTimestamp == nil { status = "1" } // created
        else if address.hashed == notification.hashedSourceAddress { status = "2" } // forwarded
        else if address.hashed == notification.hashedDestinationAddress { status = "3" } // received
        if notification.destinationControlValue == 0 { status = "4" } // arrived
        stringBuilder.append(status)
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
