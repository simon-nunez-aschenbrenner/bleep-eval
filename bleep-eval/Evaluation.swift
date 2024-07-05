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
        
    unowned private var notificationManager: NotificationManager
    private let runID: UInt
    private let isSending: Bool
    private let countHops: Bool
    private let frequency: UInt
    private let variance: Float
    private let destinations: Set<Address>
    
    private(set) var isRunning: Bool
    private(set) var logFileURL: URL?
    private var timer: DispatchSourceTimer?
    
    init(notificationManager: NotificationManager, runID: UInt, countHops: Bool, isSending: Bool, frequency: UInt = 0, varianceFactor: UInt8 = 0, destinations: Set<Address> = []) throws {
        Logger.evaluation.trace("Simulator initializes")
        notificationManager.evaluationLogger = EvaluationLogger(deviceName: notificationManager.address.name, runID: runID, clearExistingLog: true) // TODO: change to false
        self.notificationManager = notificationManager
        self.runID = runID
        self.countHops = countHops
        self.isSending = isSending
        self.frequency = frequency
        self.variance = min(Float(varianceFactor), 4.0) * 0.25
        guard !destinations.isEmpty else {
            throw BleepError.missingDestination
        }
        self.destinations = destinations
        self.isRunning = false
        Logger.evaluation.debug("Simulator initialized with runID=\(runID), isSending=\(isSending)\(isSending ? ", frequency=\(frequency)s, variance=±\(Int(self.variance*100))%, destinations=\(destinations)" : "")")
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
        Logger.evaluation.trace("Simulator attempts to \(#function) sending a notification")
        let frequency = Double(self.frequency)
        let variance = Double(self.variance)
        let interval = frequency * Double.random(in: 1-variance...1+variance)
        timer.schedule(deadline: .now() + interval)
        timer.setEventHandler {
            let message = self.countHops ? "0" : Utils.generateText(with: Int.random(in: 0...self.notificationManager.maxMessageLength), testPattern: false)
            self.notificationManager.send(message, to: self.destinations.randomElement()!)
            self.schedule(timer)
        }
    }
    
    func stop() {
        Logger.evaluation.trace("Simulator attempts to \(#function)")
        logFileURL = notificationManager.evaluationLogger?.fileURL
        timer?.cancel()
        timer = nil
        notificationManager.evaluationLogger = nil
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
        self.fileURL = self.fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("bleep-eval.\(self.deviceName!.lowercased()).\(String(format: "%02u", self.runID)).csv")
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
        // deviceName;runID;currentAddress;currentTimestamp;status;notificationID;protocolValue;destinationControlValue;sequenceNumberValue;sourceAddress;sentTimestamp;destinationAddress;receivedTimestamp;messageLength;message/hopCount\n
        let currentTimestamp = Date.now
        Logger.evaluation.trace("EvaluationLogger attempts to log notification #\(Utils.printID(notification.hashedID)) at (\(Utils.printID(address.hashed)))")
        var stringBuilder: [String] = []
        // Data provided by the device
        stringBuilder.append(self.deviceName)
        stringBuilder.append(String(self.runID))
        stringBuilder.append(address.hashed.base64EncodedString()) // currentAddress
        stringBuilder.append(String(currentTimestamp.timeIntervalSinceReferenceDate as Double))
        var status: String = "0" // undefined
        if notification.receivedTimestamp == nil { status = "1" } // created
        else if address.hashed == notification.hashedSourceAddress { status = "2" } // forwarded
        else if address.hashed == notification.hashedDestinationAddress { status = "3" } // received
        stringBuilder.append(status)
        // Data provided by the notification
        stringBuilder.append(notification.hashedID.base64EncodedString()) // notificationID
        stringBuilder.append(String(notification.protocolValue)) // 0 = Direct, 1 = Epidemic, 2 = Binary Spray and Wait, TODO: 3 = ???
        stringBuilder.append(String(notification.destinationControlValue)) // 0 = Nobody (Reached Destination), 1 = Anybody, 2 = Destination only, TODO: 3 = ???
        stringBuilder.append(String(notification.sequenceNumberValue)) // 0...15
        stringBuilder.append(notification.hashedSourceAddress.base64EncodedString())
        stringBuilder.append(String(notification.sentTimestamp.timeIntervalSinceReferenceDate as Double))
        stringBuilder.append(notification.hashedDestinationAddress.base64EncodedString())
        stringBuilder.append(notification.receivedTimestamp != nil ? String(notification.receivedTimestamp!.timeIntervalSinceReferenceDate as Double) : "")
        stringBuilder.append(String(notification.message.count)) // 0...419
        stringBuilder.append(String(notification.message)) // hop count 0...Int.max
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
