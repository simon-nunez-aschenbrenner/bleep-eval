//
//  NotificationManager.swift
//  bleep-eval
//
//  Created by Simon Núñez Aschenbrenner on 10.06.24.
//

import Foundation
import OSLog
import SwiftData
import UIKit

// MARK: NotificationManager

protocol NotificationManager: AnyObject {
    
    // For simulation/evaluation
    var evaluationLogger: EvaluationLogger? { get set }
    var rssiThreshold: Int8! { get set }
    var lastRSSIValue: Int8? { get set }
    var storedHashedIDs: Set<Data>! { get }
    func setInitialNumberOfCopies(to value: UInt8) throws

    var type: NotificationManagerType! { get set }
    var isReadyToAdvertise: Bool! { get set }
    var address: Address! { get }
    var contacts: [Address]! { get }
    var maxMessageLength: Int! { get }
    var inbox: [Notification]! { get }
    func receiveNotification(_ data: Data)
    func receiveAcknowledgement(_ data: Data) -> Bool
    func send(_ message: String, to destinationAddress: Address)
    func transmitNotifications()
}

// MARK: BleepManager

enum NotificationManagerType: UInt8, CaseIterable, Identifiable, CustomStringConvertible {
    case direct = 0
    case epidemic = 1
    case binarySprayAndWait = 2
    case disconnectedTransitiveCommunication = 3
    var id: Self { self }
    var description: String {
        switch self {
        case .direct: return "Direct"
        case .epidemic: return "Epidemic"
        case .binarySprayAndWait: return "Replicating"
        case .disconnectedTransitiveCommunication: return "Forwarding"
        }
    }
}

@Observable
class BleepManager: NotificationManager {
    
    let minNotificationLength: Int = 105
    let acknowledgementLength: Int = 32
    
    var type: NotificationManagerType! { didSet { Logger.notification.info("NotificationManager type set to '\(self.type.description)'") } }
    var isReadyToAdvertise: Bool! = true { didSet { Logger.notification.debug("NotificationManager \(self.isReadyToAdvertise ? "isReadyToAdvertise" : "is not readyToAdvertise")") } }
    
    var evaluationLogger: EvaluationLogger?
    var rssiThreshold: Int8! = -128 { didSet { Logger.notification.debug("NotificationManager rssiThreshold set to \(self.rssiThreshold) dBM") } }
    var lastRSSIValue: Int8?
    var notificationTimeToLive: TimeInterval! { didSet { Logger.notification.debug("NotificationManager notificationTimeToLive set to \(self.notificationTimeToLive) seconds") } }
    var initialRediscoveryInterval: TimeInterval! { didSet { Logger.notification.debug("NotificationManager initialRediscoveryInterval set to \(self.initialRediscoveryInterval) seconds") } }

    private(set) var maxMessageLength: Int!
    private(set) var address: Address!
    private(set) var contacts: [Address]!
    private(set) var inbox: [Notification]! = []
    private(set) var storedHashedIDs: Set<Data>! = []
    
    private var initialNumberOfCopies: UInt8! { didSet { Logger.notification.debug("NotificationManager numberOfCopies set to \(self.initialNumberOfCopies)") } }
    private var rediscoveryInterval: TimeInterval! { didSet { Logger.notification.debug("NotificationManager rediscoveryInterval set to \(self.rediscoveryInterval)") } }
    private var hasResetRediscoveryIntervalSinceLastHello: Bool! = false { didSet { Logger.notification.debug("NotificationManager \(self.hasResetRediscoveryIntervalSinceLastHello ? "hasResetRediscoveryIntervalSinceLastHello" : "has not resetRediscoveryIntervalSinceLastHello")") } }
    private var isRediscoveryIntervalResetDelayed: Bool! = false { didSet { Logger.notification.debug("NotificationManager \(self.isRediscoveryIntervalResetDelayed ? "rediscoveryIntervalReset is delayed" : "rediscoveryIntervalReset is not delayed")") } }
    private var transmitQueue: [Notification: Bool]! = [:]
    private var connectionManager: ConnectionManager!
    private var container: ModelContainer!
    private var context: ModelContext!
    
    // MARK: initializing
    
    init(type: NotificationManagerType, connectionManagerType: ConnectionManager.Type, notificationTimeToLive: TimeInterval, initialNumberOfCopies: UInt8, initialRediscoveryInterval: TimeInterval) throws {
        Logger.notification.trace("\(type) NotificationManager initializes")
        self.type = type
        self.notificationTimeToLive = notificationTimeToLive
        self.initialRediscoveryInterval = initialRediscoveryInterval
        try setInitialNumberOfCopies(to: initialNumberOfCopies)
        container = try! ModelContainer(for: Notification.self, Address.self)
        context = ModelContext(container)
        context.autosaveEnabled = true
        resetContext(notifications: true)
        initAddress()
        initContacts()
        initStoredHashedIDsSet()
        initInbox()
        connectionManager = connectionManagerType.init(notificationManager: self)
        maxMessageLength = connectionManager.maxNotificationLength - minNotificationLength
        Logger.notification.trace("\(type) NotificationManager initialized")
    }
    
    convenience init() {
        try! self.init(type: .binarySprayAndWait, connectionManagerType: BluetoothManager.self, notificationTimeToLive: 60, initialNumberOfCopies: 16, initialRediscoveryInterval: 60) // TODO: adjust presets
    }
    
    func setInitialNumberOfCopies(to value: UInt8) throws {
        Logger.notification.trace("NotificationManager attempts to \(#function)")
        guard value > 0 && value < 17 else {
            throw BleepError.invalidControlByteValue
        }
        initialNumberOfCopies = value
    }
    
    private func resetContext(notifications: Bool = false, address: Bool = false) {
        Logger.notification.debug("NotificationManager attempts to \(#function): notifications=\(notifications), address=\(address)")
        if notifications { try! context.delete(model: Notification.self) }
        if address { try! context.delete(model: Address.self) }
    }
    
    private func initAddress() {
        Logger.notification.trace("NotificationManager initializes its address")
        let fetchResult = try? context.fetch(FetchDescriptor<Address>(predicate: #Predicate<Address> { return $0.isOwn == true }))
        if fetchResult == nil || fetchResult!.isEmpty {
            Logger.notification.info("NotificationManager is creating a new address for itself")
            let newAddress = Address()
            context.insert(newAddress)
            address = newAddress
        } else {
            address = fetchResult![0]
            Logger.notification.trace("NotificationManager found its address in storage")
        }
        if let name = Utils.addressBook.first(where: { $0 == address })?.name {
            address.name = name
            Logger.notification.trace("NotificationManager found its name in the addressBook")
        } else {
            Logger.notification.fault("NotificationManager did not find its name in the addressBook")
        }
        save()
        Logger.notification.debug("NotificationManager address: \(self.address!.description)")
    }
    
    private func initContacts() {
        contacts = Utils.addressBook.filter({ $0 != address })
        Logger.notification.trace("NotificationManager initialized its contacts: \(self.contacts)")
    }
    
    private func initStoredHashedIDsSet() {
        Logger.notification.trace("NotificationManager attempts to \(#function)")
        let hashedIDs = fetchAllHashedIDs()
        if hashedIDs == nil || hashedIDs!.isEmpty {
            Logger.notification.debug("NotificationManager has no hashedIDs to add to the storedHashedIDs set")
        } else {
            storedHashedIDs = Set(hashedIDs!)
            Logger.notification.debug("NotificationManager has populated the storedHashedIDs set with \(self.storedHashedIDs.count) hashedIDs")
        }
    }
    
    private func initInbox() {
        Logger.notification.trace("NotificationManager attempts to \(#function)")
        let countBefore = inbox.count
        inbox = fetchAll(for: address.hashed) ?? []
        Logger.notification.debug("NotificationManager added \(self.inbox.count - countBefore) notification(s) to the inbox")
    }
    
    // MARK: incoming
    
    func receiveNotification(_ data: Data) {
        Logger.notification.debug("NotificationManager attempts to \(#function) of \(data.count-self.minNotificationLength)+\(self.minNotificationLength)=\(data.count) bytes")
        guard data.count >= minNotificationLength else { // TODO: throw
            Logger.notification.error("NotificationManager will ignore the notification data as it's not at least \(self.minNotificationLength) bytes long")
            return
        }
        let controlByte = ControlByte(UInt8(data[0]))
        let hashedID = data.subdata(in: 1..<33)
        let hashedDestinationAddress = data.subdata(in: 33..<65)
        let hashedSourceAddress = data.subdata(in: 65..<97)
        let sentTimestampData = data.subdata(in: 97..<105)
        let messageData = data.subdata(in: 105..<data.count)
        let message: String = String(data: messageData, encoding: .utf8) ?? ""
        guard controlByte.destinationControlValue > 0 else {
            Logger.notification.info("NotificationManager received GOODBYE")
            connectionManager.disconnect()
            return
        }
        guard controlByte.protocolValue == type.rawValue else { // TODO: throw
            Logger.notification.error("NotificationManager will ignore notification #\(Utils.printID(hashedID)), as its protocolValue \(controlByte.protocolValue) doesn't match the type.rawValue \(self.type.rawValue)")
            return
        }
        guard !storedHashedIDs.contains(hashedID) else {
            Logger.notification.info("NotificationManager will ignore notification #\(Utils.printID(hashedID)) as it is already stored")
            return
        }
        let notification = Notification(controlByte: controlByte, hashedID: hashedID, hashedDestinationAddress: hashedDestinationAddress, hashedSourceAddress: hashedSourceAddress, sentTimestampData: sentTimestampData, message: message)
        guard accept(notification) else {
            Logger.notification.info("NotificationManager will ignore notification #\(Utils.printID(hashedID)) as accept(notification) returned false")
            return
        }
        Logger.notification.info("NotificationManager accepted notification \(notification.description) with message: '\(notification.message)'")
        if notification.hashedDestinationAddress == address.hashed {
            try! notification.setDestinationControl(to: 0)
            Logger.notification.info("NotificationManager has setDestinationControl(to: 0) for notification #\(Utils.printID(notification.hashedID)) because it reached its destination")
            inbox.append(notification)
        }
        if evaluationLogger == nil {
            Logger.notification.warning("NotificationManager did not call evaluationLogger.log() because the evaluationLogger property is nil")
        } else {
            evaluationLogger!.log(notification, at: address)
        }
        insert(notification)
        if isReadyToAdvertise { connectionManager.advertise() }
    }
    
    private func accept(_ notification: Notification) -> Bool {
        Logger.notification.debug("NotificationManager attempts to \(#function) #\(Utils.printID(notification.hashedID))")
        switch type! {
        case .direct:
            return notification.destinationControlValue == 2 && notification.hashedDestinationAddress == address.hashed
        case .epidemic:
            return notification.destinationControlValue == 1
        case .binarySprayAndWait:
            guard notification.destinationControlValue == 1 || notification.hashedDestinationAddress == address.hashed else { return false }
            acknowledge(notification)
            return true
        case .disconnectedTransitiveCommunication:
            if notification.destinationControlValue == 1 {
                Logger.notification.trace("NotificationManager received HELLO and may resetAllRediscoveryIntervals")
                if notification.sequenceNumberValue > 0 || fetchAll(from: notification.hashedSourceAddress) == nil {
                    if !isRediscoveryIntervalResetDelayed {
                        rediscoveryInterval = initialRediscoveryInterval
                        hasResetRediscoveryIntervalSinceLastHello = true
                    }
                    isRediscoveryIntervalResetDelayed.toggle()
                }
                try! notification.setDestinationControl(to: 0)
                Logger.notification.trace("NotificationManager has setDestinationControl(to: 0) for notification #\(Utils.printID(notification.hashedID)) so the HELLO message does not propagate")
                return true
            } else if notification.hashedDestinationAddress == address.hashed || notification.sequenceNumberValue < computeUtility(for: notification.hashedDestinationAddress) {
                acknowledge(notification)
                return true
            } else { return false }
        }
    }
    
    private func computeUtility(for hashedDestinationAddress: Data) -> UInt8 {
        Logger.notification.debug("NotificationManager attempts to \(#function) hashedDestinationAddress (\(Utils.printID(hashedDestinationAddress)))")
        assert(address.hashed != hashedDestinationAddress) // else we'd be looking up notifications sent from this device that won't have a receivedTimestamp
        let now = Date.now
        let notificationsFromDestination: [Notification] = fetchAll(from: hashedDestinationAddress)?.sorted(by: >) ?? []
        let timeLastNoticed: Date = notificationsFromDestination.first?.receivedTimestamp ?? now
        let mostRecentlyNoticedUtility: Double = !notificationsFromDestination.isEmpty ? max(1 - now.timeIntervalSince(timeLastNoticed) / notificationTimeToLive, 0) : 0
        let mostFrequentlyNoticedUtility: Double = !notificationsFromDestination.isEmpty ? max(1 - now.timeIntervalSince(timeLastNoticed) / Double(notificationsFromDestination.count) * notificationTimeToLive, 0) : 0
        let powerUtility: Double = max(getBatteryLevel(), 0) // More basic approach than in the paper, but probably fine since all devices have roughly the same battery capacity
        let rediscoveryIntervalUtility: Double = max(initialRediscoveryInterval / rediscoveryInterval, 0)
        let utility: Double = (mostRecentlyNoticedUtility + mostFrequentlyNoticedUtility + powerUtility + rediscoveryIntervalUtility) / 4
        let utilityBucket: UInt8 = min(UInt8(utility * 16), 15)
        Logger.notification.info("NotificationManager did compute utility for hashedDestinationAddress (\(Utils.printID(hashedDestinationAddress))) as \(utilityBucket)/15: (\(mostRecentlyNoticedUtility) + \(mostFrequentlyNoticedUtility) + \(powerUtility) + \(rediscoveryIntervalUtility)) / 4 = \(utility)")
        return utilityBucket
    }
    
    private func getBatteryLevel() -> Double {
        UIDevice.current.isBatteryMonitoringEnabled = true
        let batteryLevel = UIDevice.current.batteryLevel
        UIDevice.current.isBatteryMonitoringEnabled = false
        return Double(batteryLevel)
    }
    
    func receiveAcknowledgement(_ data: Data) -> Bool {
        switch type! {
        case .direct, .epidemic:
            Logger.notification.error("NotificationManager does not support \(#function)")
            return false
        case .binarySprayAndWait, .disconnectedTransitiveCommunication:
            Logger.notification.debug("NotificationManager attempts to \(#function) of \(data.count) bytes")
            guard data.count == acknowledgementLength else { // TODO: throw
                Logger.notification.error("NotificationManager will ignore the acknowledgement data as it's not \(self.acknowledgementLength) bytes long")
                return false
            }
            guard let notification = fetch(with: data) else { // TODO: throw
                Logger.notification.error("NotificationManager did not find a matching notification in storage")
                return false
            }
            guard notification.destinationControlValue > 0 else { // TODO: throw
                Logger.notification.error("NotificationManager will ignore the acknowledgement because it matches a notification with destinationControlValue 0")
                return false
            }
            if type == .binarySprayAndWait {
                do {
                    try notification.setSequenceNumber(to: notification.sequenceNumberValue/2)
                    Logger.notification.info("NotificationManager halfed the sequenceNumberValue for notification \(notification.description)")
                    return true
                } catch BleepError.invalidControlByteValue {
                    try! notification.setDestinationControl(to: 2)
                    Logger.notification.info("NotificationManager could not half the sequenceNumberValue and therefore has set setDestinationControl(to: 2) for notification \(notification.description)")
                    return true
                } catch {
                    Logger.notification.error("NotificationManager encountered an unexpected error while trying to modify the controlByte for notification \(notification.description)")
                    return false
                }
            } else { // type == .disconnectedTransitiveCommunication
                guard notification.destinationControlValue > 1 else { // TODO: throw
                    Logger.notification.error("NotificationManager will ignore the acknowledgement because it matches a notification with destinationControlValue 1")
                    return false
                }
                try! notification.setDestinationControl(to: 0)
                Logger.notification.info("NotificationManager has set setDestinationControl(to: 0) for notification \(notification.description)")
                return true
            }
        }
    }
    
    // MARK: outgoing
    
    func send(_ message: String, to destinationAddress: Address) {
        var controlByte: ControlByte!
        switch type! {
        case .direct:
            controlByte = try! ControlByte(protocolValue: type.rawValue, destinationControlValue: 2, sequenceNumberValue: 0)
        case .epidemic:
            controlByte = try! ControlByte(protocolValue: type.rawValue, destinationControlValue: 1, sequenceNumberValue: 0)
        case .binarySprayAndWait:
            controlByte = try! ControlByte(protocolValue: type.rawValue, destinationControlValue: 1, sequenceNumberValue: initialNumberOfCopies-1)
        case .disconnectedTransitiveCommunication:
            controlByte = try! ControlByte(protocolValue: type.rawValue, destinationControlValue: 2, sequenceNumberValue: computeUtility(for: destinationAddress.hashed))
        }
        insert(Notification(controlByte: controlByte, sourceAddress: address, destinationAddress: destinationAddress, message: message))
        if isReadyToAdvertise { connectionManager.advertise() }
    }
    
    private func populateTransmitQueue() {
        Logger.notification.trace("NotificationManager attempts to \(#function)")
        let notifications = fetchAllTransmittables()
        if notifications == nil || notifications!.isEmpty {
            Logger.notification.debug("NotificationManager has no notifications to add to the transmitQueue")
        } else {
            transmitQueue = notifications!.reduce(into: [Notification: Bool]()) { $0[$1] = false }
            Logger.notification.debug("NotificationManager has populated the transmitQueue with \(self.transmitQueue.count) notification(s): \(self.transmitQueue)")
        }
    }
    
    func transmitNotifications() { // Get's called after a consumer subscribed to this publisher and each time a transmission fails
        Logger.notification.trace("NotificationManager may attempt to \(#function)")
        isReadyToAdvertise = false
        if transmitQueue.isEmpty { // Prepare a current transmitQueue only at the first call, meaning for each new subscription, not every time a transmission fails
            if type == .disconnectedTransitiveCommunication { // Each new subscription shall contain at least one current HELLO notification
                Logger.notification.trace("NotificationManager creates HELLO notification")
                let controlByte = try! ControlByte(protocolValue: type.rawValue, destinationControlValue: 1, sequenceNumberValue: hasResetRediscoveryIntervalSinceLastHello ? 1 : 0)
                insert(Notification(controlByte: controlByte, sourceAddress: address, destinationAddress: address, message: "HELLO"))
            }
            populateTransmitQueue()
        }
        Logger.notification.debug("NotificationManager attempts to \(#function) with \(self.transmitQueue.values.filter { !$0 }.count)/\(self.transmitQueue.count) notifications in the transmitQueue")
        for element in transmitQueue {
            let notification = element.key
            guard !element.value else {
                Logger.notification.trace("NotificationManager skips transmitting notification #\(Utils.printID(notification.hashedID)) because it was already transmitted")
                continue
            }
            guard type != .disconnectedTransitiveCommunication || notification.lastRediscovery == nil || notification.lastRediscovery! < Date(timeIntervalSinceNow: -rediscoveryInterval) else {
                Logger.notification.debug("NotificationManager skips transmitting notification #\(Utils.printID(notification.hashedID)) because its rediscoveryInterval has not yet elapsed")
                continue
            }
            if transmit(notification) {
                transmitQueue[notification] = true
                notification.lastRediscovery = Date.now
                rediscoveryInterval *= 2
                if evaluationLogger == nil {
                    Logger.notification.warning("NotificationManager did not call evaluationLogger.log() because the evaluationLogger property is nil")
                } else {
                    evaluationLogger!.log(notification, at: address)
                }
                continue
            } else {
                return // peripheralManagerIsReady(toUpdateSubscribers) will call transmitNotifications() again
            }
        }
        Logger.notification.trace("NotificationManager skipped or finished the \(#function) loop")
        hasResetRediscoveryIntervalSinceLastHello = false
        if transmitGoodbye() {
            Logger.notification.info("NotificationManager transmitted GOODBYE, will remove all notifications from the sendQueue and eventually start to advertise again")
            transmitQueue.removeAll()
            isReadyToAdvertise = true
        } else {
            Logger.notification.warning("NotificationManager did not transmit GOODBYE")
            return // peripheralManagerIsReady(toUpdateSubscribers) will call transmitNotifications() again
        }
    }
    
    private func transmit(_ notification: Notification) -> Bool {
        Logger.notification.debug("NotificationManager attempts to \(#function) \(notification.description) with message: '\(notification.message)'")
        var controlByte: ControlByte!
        switch type! {
        case .direct:
            controlByte = ControlByte(notification.controlByte)
            Logger.notification.trace("NotificationManager did not modify the controlByte")
        case .epidemic:
            controlByte = ControlByte(notification.controlByte)
            Logger.notification.trace("NotificationManager did not modify the controlByte")
        case .binarySprayAndWait:
            do {
                controlByte = try ControlByte(protocolValue: notification.protocolValue, destinationControlValue: notification.destinationControlValue, sequenceNumberValue: notification.sequenceNumberValue/2)
                Logger.notification.trace("NotificationManager halfed the sequenceNumberValue")
            } catch BleepError.invalidControlByteValue {
                controlByte = try! ControlByte(protocolValue: notification.protocolValue, destinationControlValue: 2, sequenceNumberValue: notification.sequenceNumberValue)
                Logger.notification.trace("NotificationManager could not half the sequenceNumberValue and has therefore setDestinationControl(to: 2)")
            } catch {
                Logger.notification.error("NotificationManager encountered an unexpected error while trying to modify the controlByte")
                return false
            }
            Logger.notification.debug("NotificationManager will \(#function) notification #\(Utils.printID(notification.hashedID)) with a modified controlByte: \(controlByte.description)")
        case .disconnectedTransitiveCommunication:
            controlByte = ControlByte(notification.controlByte) // TODO: CHANGE
        }
        var data = Data()
        data.append(controlByte.value)
        data.append(notification.hashedID)
        data.append(notification.hashedDestinationAddress)
        data.append(notification.hashedSourceAddress)
        data.append(notification.sentTimestampData)
        assert(data.count == minNotificationLength)
        if let messageData = notification.message.data(using: .utf8) { data.append(messageData) }
        if connectionManager.transmit(data) {
            Logger.notification.info("NotificationManager transmitted notification data of \(data.count-self.minNotificationLength)+\(self.minNotificationLength)=\(data.count) bytes")
            return true
        } else {
            Logger.notification.warning("NotificationManager did not transmit notification data of \(data.count-self.minNotificationLength)+\(self.minNotificationLength)=\(data.count) bytes")
            return false
        }
    }
    
    private func transmitGoodbye() -> Bool {
        Logger.notification.trace("NotificationManager attempts to \(#function)")
        let controlByte = try! ControlByte(protocolValue: type.rawValue, destinationControlValue: 0, sequenceNumberValue: 0)
        var data = Data()
        data.append(controlByte.value)
        data.append(Data(count: minNotificationLength-data.count))
        assert(data.count == minNotificationLength)
        return connectionManager.transmit(data)
    }
    
    private func acknowledge(_ notification: Notification) {
        Logger.notification.debug("NotificationManager attempts to \(#function) #\(Utils.printID(notification.hashedID))")
        connectionManager.acknowledge(notification.hashedID)
    }
    
    // MARK: persisting
    
    func insert(_ notification: Notification) {
        Logger.notification.debug("NotificationManager attempts to \(#function) notification #\(Utils.printID(notification.hashedID))")
        context.insert(notification)
        save()
        Logger.notification.trace("NotificationManager appends hashedID to the storedHashedIDs set")
        storedHashedIDs.insert(notification.hashedID)
    }
    
    private func save() {
        do {
            try context.save()
            Logger.notification.trace("NotificationManager saved the context")
        } catch { // TODO: throw
            Logger.notification.error("NotificationManager failed to save the context: \(error)")
        }
    }
    
    private func fetchAllTransmittables() -> [Notification]? {
        Logger.notification.trace("NotificationManager attempts to \(#function)")
        updateAllTransmittables()
        return try? context.fetch(FetchDescriptor<Notification>(predicate: #Predicate<Notification> { return $0.destinationControlValue != 0 }))
    }
    
    private func fetchAll(for hashedDestinationAddress: Data) -> [Notification]? {
        Logger.notification.debug("NotificationManager attempts to \(#function) for hashedAddress (\(Utils.printID(hashedDestinationAddress)))")
        let predicate = #Predicate<Notification> { $0.hashedDestinationAddress == hashedDestinationAddress }
        return try? context.fetch(FetchDescriptor<Notification>(predicate: predicate))
    }
    
    private func fetchAll(from hashedSourceAddress: Data) -> [Notification]? {
        Logger.notification.debug("NotificationManager attempts to \(#function) from hashedAddress (\(Utils.printID(hashedSourceAddress)))")
        let predicate = #Predicate<Notification> { $0.hashedSourceAddress == hashedSourceAddress }
        return try? context.fetch(FetchDescriptor<Notification>(predicate: predicate))
    }
    
    private func fetchAllHashedIDs() -> [Data]? {
        Logger.notification.trace("NotificationManager attempts to \(#function)")
        guard let results = fetchAll() else { return nil }
        return results.map { $0.hashedID }
    }
    
    private func fetchAll() -> [Notification]? {
        Logger.notification.trace("NotificationManager attempts to \(#function)")
        return try? context.fetch(FetchDescriptor<Notification>())
    }
    
    private func fetch(with hashedID: Data) -> Notification? {
        Logger.notification.debug("NotificationManager attempts to \(#function) #\(Utils.printID(hashedID))")
        let predicate = #Predicate<Notification> { $0.hashedID == hashedID }
        return try? context.fetch(FetchDescriptor<Notification>(predicate: predicate))[0]
    }
    
    private func updateAllTransmittables() {
        let threshold = Date(timeIntervalSinceNow: -notificationTimeToLive)
        Logger.notification.debug("NotificationManager attempts to \(#function) with the date threshold \(threshold)")
        let predicate = #Predicate<Notification> { $0.receivedTimestamp ?? $0.sentTimestamp < threshold }
        guard let notifications = try? context.fetch(FetchDescriptor<Notification>(predicate: predicate)) else {
            Logger.notification.debug("NotificationManager has no notifications to update")
            return
        }
        for notification in notifications {
            try! notification.setDestinationControl(to: 0)
            Logger.notification.trace("NotificationManager setDestinationControl(to: 0) for notification #\(Utils.printID(notification.hashedID)) because it exceeded the notificationTimeToLive")
        }
    }
}
