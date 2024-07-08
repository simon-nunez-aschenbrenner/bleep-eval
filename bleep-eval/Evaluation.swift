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
        
    unowned private var notificationManager: EvaluableNotificationManager
    
    private var isSending: Bool = false
    private var frequency: Double = 0
    private var variance: Double = 0
    private var destinations: Set<Address> = []
    private var timer: DispatchSourceTimer?
    
    private(set) var isRunning: Bool = false
    private(set) var evaluationLogger: EvaluationLogger?
    private(set) var logFileURL: URL?
    
    init(notificationManager: EvaluableNotificationManager) {
        self.notificationManager = notificationManager
        Logger.evaluation.trace("Simulator initialized")
    }
    
    func prepare(runID: UInt, isSending: Bool, frequency: UInt = 0, varianceFactor: UInt8 = 0, destinations: Set<Address> = []) throws {
        Logger.evaluation.debug("Simulator attempts to \(#function) with runID \(runID) \(isSending ? "receiving and sending wth frequency=\(frequency)s, variance=±\(Int(self.variance*100))%, destinations=\(destinations)" : "and will only receive")")
        guard !isSending || !destinations.isEmpty else { throw BleepError.missingDestination }
        self.isSending = isSending
        self.frequency = Double(frequency)
        self.variance = min(Double(varianceFactor), 4.0) * 0.25
        self.destinations = destinations
        self.logFileURL = nil
        self.timer?.cancel()
        self.timer = nil
        self.evaluationLogger = EvaluationLogger(deviceName: notificationManager.address.name, runID: runID, clearExistingLog: true) // TODO: change to false
    }
    
    func start() {
        Logger.evaluation.debug("Simulator attempts to \(#function)")
        isRunning = true
        if isSending {
            timer = DispatchSource.makeTimerSource(queue: DispatchQueue.global())
            schedule(timer!)
            timer!.resume()
        }
    }
    
    private func schedule(_ timer: DispatchSourceTimer) {
        Logger.evaluation.trace("Simulator attempts to \(#function) sending a notification")
        let interval = frequency * Double.random(in: 1-variance...1+variance)
        timer.schedule(deadline: .now() + interval)
        timer.setEventHandler {
            let message: String = self.notificationManager.countHops ? "0" : Utils.generateText(with: Int.random(in: 0...self.notificationManager.maxMessageLength), testPattern: false)
            self.notificationManager.send(message, to: self.destinations.randomElement()!)
            self.schedule(timer)
        }
    }
    
    func stop() {
        Logger.evaluation.trace("Simulator attempts to \(#function)")
        logFileURL = evaluationLogger?.fileURL
        timer?.cancel()
        timer = nil
        evaluationLogger = nil
        isRunning = false
    }
}

class EvaluationLogger {
        
    private let deviceName: String
    private let runID: UInt
    private let fileManager: FileManager = FileManager.default
    var fileURL: URL

    init(deviceName: String?, runID: UInt, clearExistingLog: Bool = false) {
        Logger.evaluation.debug("EvaluationLogger initializes with runID \(runID)")
        self.deviceName = deviceName?.lowercased() ?? "unknown"
        self.runID = runID
        self.fileURL = self.fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("bleep-eval.\(self.deviceName).\(String(format: "%02u", self.runID)).csv")
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
        let currentTimestamp = Date.now
        Logger.evaluation.trace("EvaluationLogger attempts to log notification #\(Utils.printID(notification.hashedID)) at (\(Utils.printID(address.hashed)))")
        var stringBuilder: [String] = []
        // Data provided by the logger
        stringBuilder.append(self.deviceName)
        stringBuilder.append(String(self.runID))
        stringBuilder.append(address.hashed.base64EncodedString()) // currentAddress
        stringBuilder.append(String(currentTimestamp.timeIntervalSinceReferenceDate as Double))
        stringBuilder.append("notification") // type
        // Data provided by the notification
        stringBuilder.append(notification.hashedID.base64EncodedString())
        stringBuilder.append(String(notification.controlByte.protocolValue)) // 0 = Direct, 1 = Epidemic, 2 = Replicating, 3 = Forwarding
        stringBuilder.append(String(notification.controlByte.destinationControlValue)) // 0 = Nobody/Goodbye, 1 = Anybody/Hello, 2 = Destination only/Better utility, 3 = Destination only/Utility probe
        stringBuilder.append(String(notification.controlByte.sequenceNumberValue)) // 0...15 = Copies/Utility threshold
        stringBuilder.append(notification.hashedSourceAddress.base64EncodedString())
        stringBuilder.append(String(notification.sentTimestamp.timeIntervalSinceReferenceDate as Double))
        stringBuilder.append(notification.hashedDestinationAddress.base64EncodedString())
        stringBuilder.append(notification.receivedTimestamp != nil ? String(notification.receivedTimestamp!.timeIntervalSinceReferenceDate as Double) : "")
        stringBuilder.append(String(notification.message)) // 0...Int.max = hopCount
        let logEntry: String = stringBuilder.joined(separator: ";")
        Logger.evaluation.debug("EvaluationLogger attempts to append logEntry '\(logEntry)'")
        log(logEntry.appending("\n").data(using: .utf8)!)
    }
    
    func log(_ response: Response, at address: Address) {
        let currentTimestamp = Date.now
        Logger.evaluation.trace("EvaluationLogger attempts to log response #\(Utils.printID(response.hashedID)) at (\(Utils.printID(address.hashed)))")
        var stringBuilder: [String] = []
        // Data provided by the logger
        stringBuilder.append(self.deviceName)
        stringBuilder.append(String(self.runID))
        stringBuilder.append(address.hashed.base64EncodedString()) // currentAddress
        stringBuilder.append(String(currentTimestamp.timeIntervalSinceReferenceDate as Double))
        stringBuilder.append("response") // type
        // Data provided by the notification
        stringBuilder.append(response.hashedID.base64EncodedString())
        stringBuilder.append(String(response.controlByte.protocolValue)) // 0 = Direct, 1 = Epidemic, 2 = Replicating, 3 = Forwarding
        stringBuilder.append(String(response.controlByte.destinationControlValue)) // 1 = Accepted, 2 = Accepted by destination, 3 = Utility response
        stringBuilder.append(String(response.controlByte.sequenceNumberValue)) // 0...15 = Utility
        stringBuilder.append("") // sourceAddress
        stringBuilder.append("") // sentTimestamp
        stringBuilder.append("") // destinationAddress
        stringBuilder.append(String(response.receivedTimestamp.timeIntervalSinceReferenceDate as Double))
        stringBuilder.append("") // hopCount
        let logEntry: String = stringBuilder.joined(separator: ";")
        Logger.evaluation.debug("EvaluationLogger attempts to append logEntry '\(logEntry)'")
        log(logEntry.appending("\n").data(using: .utf8)!)
    }
    
    private func log(_ data: Data) {
        // log entry format
        // deviceName;runID;currentAddress;currentTimestamp;type;hashedID;protocolValue;destinationControlValue;sequenceNumberValue;sourceAddress;sentTimestamp;destinationAddress;receivedTimestamp;hopCount\n
        if let fileHandle = try? FileHandle(forWritingTo: fileURL) {
            fileHandle.seekToEndOfFile()
            fileHandle.write(data)
            fileHandle.closeFile()
            Logger.evaluation.trace("EvaluationLogger successfully appended the logEntry to the log file")
        } else {
            Logger.evaluation.fault("EvaluationLogger was unable to append the logEntry to the log file")
        }
    }
}
