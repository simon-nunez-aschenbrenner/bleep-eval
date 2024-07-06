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
    var simulator: Simulator! { get }
    var lastRSSIValue: Int8? { get set }
    var rssiThreshold: Int8 { get set }
    var countHops: Bool { get set }
    var notificationTimeToLive: TimeInterval { get set }
    var utilityCollectionTimeout: TimeInterval { get set }
    var initialRediscoveryInterval: TimeInterval { get set }
    var storedHashedIDsCount: Int { get }
    func setInitialNumberOfCopies(to value: UInt8) throws
    func reset()

    var type: NotificationManagerType! { get set }
    var isReadyToAdvertise: Bool { get set }
    var address: Address! { get }
    var contacts: [Address] { get }
    var inbox: [Notification] { get }
    var maxMessageLength: Int! { get }
    func receiveNotification(_ data: Data, from id: String)
    func receiveAcknowledgement(_ data: Data, from id: String) -> Bool
    func sendNotification(_ message: String, to destinationAddress: Address)
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

struct BleepManagerDefault {
    
    static let rssiThreshold: Int8 = -128
    static let countHops: Bool = true
    static let notificationTimeToLive: TimeInterval = 300
    static let initialNumberOfCopies: UInt8 = 16
    static let utilityCollectionTimeout: TimeInterval = 10
    static let initialRediscoveryInterval: TimeInterval = 10
    static let hasResetRediscoveryIntervalSinceLastHello: Bool = false
    static let isRediscoveryIntervalResetDelayed: Bool = false
}

@Observable
class BleepManager: NotificationManager {
    
    let minNotificationLength: Int = 105
    let acknowledgementLength: Int = 33
    
    var type: NotificationManagerType! {
        didSet { Logger.notification.info("NotificationManager type set to '\(self.type.description)'") }
    }
    var isReadyToAdvertise: Bool = true {
        didSet { Logger.notification.debug("NotificationManager \(self.isReadyToAdvertise ? "isReadyToAdvertise" : "is not readyToAdvertise")") }
    }
    
    private(set) var simulator: Simulator!
    var lastRSSIValue: Int8?
    var rssiThreshold: Int8 = BleepManagerDefault.rssiThreshold {
        didSet { Logger.notification.debug("NotificationManager rssiThreshold set to \(self.rssiThreshold) dBM") }
    }
    var countHops: Bool = BleepManagerDefault.countHops {
        didSet { Logger.notification.debug("NotificationManager \(self.countHops ? "will countHops" : "will not countHops")") }
    }
    var notificationTimeToLive: TimeInterval = BleepManagerDefault.notificationTimeToLive {
        didSet { Logger.notification.debug("NotificationManager notificationTimeToLive set to \(String(format: "%u", self.notificationTimeToLive)) seconds") }
    }
    var utilityCollectionTimeout: TimeInterval = BleepManagerDefault.utilityCollectionTimeout {
        didSet { Logger.notification.debug("NotificationManager utilityCollectionTimeout set to \(String(format: "%u", self.utilityCollectionTimeout)) seconds") }
    }
    var initialRediscoveryInterval: TimeInterval = BleepManagerDefault.initialRediscoveryInterval {
        didSet { Logger.notification.debug("NotificationManager initialRediscoveryInterval set to \(String(format: "%u", self.initialRediscoveryInterval)) seconds") }
    }
    var storedHashedIDsCount: Int { return storedHashedIDs.count }

    private(set) var address: Address!
    private(set) var contacts: [Address] = []
    private(set) var inbox: [Notification] = []
    private(set) var maxMessageLength: Int!
    
    private var isResetting: Bool = false
    private var container: ModelContainer!
    private var context: ModelContext!
    private var connectionManager: ConnectionManager!
    private var storedHashedIDs: Set<Data> = []
    private var transmitQueue: [Notification: Bool] = [:]
    private var initialNumberOfCopies: UInt8 = BleepManagerDefault.initialNumberOfCopies {
        didSet { Logger.notification.debug("NotificationManager initialNumberOfCopies set to \(self.initialNumberOfCopies)") }
    }
    private var rediscoveryInterval: TimeInterval = BleepManagerDefault.initialRediscoveryInterval {
        didSet { Logger.notification.debug("NotificationManager rediscoveryInterval set to \(String(format: "%u", self.rediscoveryInterval)) seconds") }
    }
    private var hasResetRediscoveryIntervalSinceLastHello: Bool = BleepManagerDefault.hasResetRediscoveryIntervalSinceLastHello {
        didSet { Logger.notification.debug("NotificationManager \(self.hasResetRediscoveryIntervalSinceLastHello ? "hasResetRediscoveryIntervalSinceLastHello" : "has not resetRediscoveryIntervalSinceLastHello")") }
    }
    private var isRediscoveryIntervalResetDelayed: Bool = BleepManagerDefault.isRediscoveryIntervalResetDelayed {
        didSet { Logger.notification.debug("NotificationManager \(self.isRediscoveryIntervalResetDelayed ? "rediscoveryIntervalReset is delayed" : "rediscoveryIntervalReset is not delayed")") }
    }
    
    // MARK: initializing
    
    init(type: NotificationManagerType, connectionManagerType: ConnectionManager.Type) throws {
        Logger.notification.trace("\(type) NotificationManager initializes")
        self.type = type
        container = try! ModelContainer(for: Notification.self, Address.self)
        context = ModelContext(container)
        context.autosaveEnabled = true
        resetContext(notifications: true, address: Utils.resetAddressContext)
        initAddress()
        contacts = Utils.addressBook.filter({ $0 != address })
        initStoredHashedIDsSet()
        initInbox()
        simulator = Simulator(notificationManager: self)
        connectionManager = connectionManagerType.init(notificationManager: self)
        maxMessageLength = connectionManager.maxNotificationLength - minNotificationLength
        Logger.notification.trace("\(type) NotificationManager initialized")
    }
    
    convenience init() {
        try! self.init(type: .binarySprayAndWait, connectionManagerType: BluetoothManager.self)
    }

    func reset() {
        Logger.notification.trace("NotificationManager attempts to \(#function)")
        isResetting = true
        isReadyToAdvertise = false
        connectionManager.disconnect()
        resetContext(notifications: true)
        transmitQueue.removeAll()
        storedHashedIDs.removeAll()
        inbox.removeAll()
        rssiThreshold = BleepManagerDefault.rssiThreshold
        countHops = BleepManagerDefault.countHops
        notificationTimeToLive = BleepManagerDefault.notificationTimeToLive
        initialRediscoveryInterval = BleepManagerDefault.initialRediscoveryInterval
        rediscoveryInterval = BleepManagerDefault.initialRediscoveryInterval
        initialNumberOfCopies = BleepManagerDefault.initialNumberOfCopies
        isResetting = false
        isReadyToAdvertise = true
        Logger.notification.info("NotificationManager is reset to defaults")
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
        Logger.notification.debug("NotificationManager address: \(self.address.description)")
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
    
    func setInitialNumberOfCopies(to value: UInt8) throws {
        Logger.notification.trace("NotificationManager attempts to \(#function)")
        guard value > 0 && value < 17 else {
            throw BleepError.invalidControlByteValue
        }
        initialNumberOfCopies = value
    }
    
    // MARK: receiving
    
    func receiveNotification(_ data: Data, from id: String) {
        Logger.notification.debug("NotificationManager attempts to \(#function) of \(data.count-self.minNotificationLength)+\(self.minNotificationLength)=\(data.count) bytes from '\(Utils.printID(id))'")
        guard !isResetting else {
            Logger.notification.error("NotificationManager is currently resetting and will ignore the notification data")
            return
        }
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
            connectionManager.disconnect(id)
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
        guard accept(notification, from: id) else {
            Logger.notification.info("NotificationManager will ignore notification #\(Utils.printID(hashedID)) as accept(notification) returned false")
            return
        }
        Logger.notification.info("NotificationManager accepted notification \(notification.description) with message: '\(notification.message)'")
        if countHops, let hopCount = Int(notification.message) {
            notification.message = String(hopCount) // Increment hop count
            Logger.notification.info("NotificationManager did increment hop count of notification #\(Utils.printID(hashedID)) to: '\(notification.message)'")
        }
        if simulator.evaluationLogger == nil {
            Logger.notification.warning("NotificationManager did not log for evaluation because the evaluationLogger property of the simulator is nil")
        } else {
            simulator.evaluationLogger!.log(notification, at: address)
        }
        if notification.hashedDestinationAddress == address.hashed {
            try! notification.controlByte.setDestinationControl(to: 0)
            Logger.notification.info("NotificationManager has setDestinationControl(to: 0) for notification #\(Utils.printID(notification.hashedID)) because it reached its destination")
            inbox.append(notification)
        }
        insert(notification)
        if isReadyToAdvertise { connectionManager.advertise() }
    }
    
    private func accept(_ notification: Notification, from id: String) -> Bool {
        Logger.notification.debug("NotificationManager attempts to \(#function) #\(Utils.printID(notification.hashedID)) from '\(Utils.printID(id))'")
        switch type! {
        case .direct:
            return notification.controlByte.destinationControlValue == 2 && notification.hashedDestinationAddress == address.hashed
        case .epidemic:
            return notification.controlByte.destinationControlValue == 1
        case .binarySprayAndWait:
            guard notification.controlByte.destinationControlValue == 1 || notification.hashedDestinationAddress == address.hashed else { return false }
            acknowledge(notification, to: id)
            return true
        case .disconnectedTransitiveCommunication:
            if notification.controlByte.destinationControlValue == 1 {
                Logger.notification.trace("NotificationManager received HELLO and may resetAllRediscoveryIntervals")
                if notification.controlByte.sequenceNumberValue > 0 || fetchAll(from: notification.hashedSourceAddress) == nil {
                    if !isRediscoveryIntervalResetDelayed {
                        rediscoveryInterval = initialRediscoveryInterval
                        hasResetRediscoveryIntervalSinceLastHello = true
                    }
                    isRediscoveryIntervalResetDelayed.toggle()
                }
                try! notification.controlByte.setDestinationControl(to: 0)
                Logger.notification.trace("NotificationManager has setDestinationControl(to: 0) for notification #\(Utils.printID(notification.hashedID)) so the HELLO message does not propagate")
                return true
            } else if notification.hashedDestinationAddress == address.hashed {
                var modifiedControlByte = notification.controlByte
                try! modifiedControlByte.setDestinationControl(to: 2)
                Logger.notification.trace("NotificationManager has setDestinationControl(to: 2) for the acknowledgement of notification #\(Utils.printID(notification.hashedID)) because it reached its destination")
                acknowledge(notification, to: id, with: modifiedControlByte)
                return true
            } else {
                let utility = computeUtility(for: notification.hashedDestinationAddress)
                if notification.controlByte.sequenceNumberValue <= utility {
                    Logger.notification.trace("NotificationManager utility >= notification utility threshold")
                    if notification.controlByte.destinationControlValue == 2 {
                        acknowledge(notification, to: id)
                        return true
                    } else { // notification.controlByte.destinationControlValue == 3
                        Logger.notification.trace("NotificationManager received utility probe and will attempt to send utility response")
                        acknowledge(notification, to: id, with: try! ControlByte(protocolValue: type.rawValue, destinationControlValue: 3, sequenceNumberValue: utility))
                        return false
                    }
                } else { return false }
            }
        }
    }
    
    private func computeUtility(for hashedDestinationAddress: Data) -> UInt8 {
        Logger.notification.debug("NotificationManager attempts to \(#function) hashedDestinationAddress (\(Utils.printID(hashedDestinationAddress)))")
        assert(address.hashed != hashedDestinationAddress) // else we'd be looking up notifications sent from this device that won't have a receivedTimestamp
        let now = Date.now
        let notificationsFromDestination = fetchAll(from: hashedDestinationAddress)?.sorted(by: >) ?? []
        let timeLastNoticed = notificationsFromDestination.first?.receivedTimestamp ?? now
        let mostRecentlyNoticedUtility = notificationsFromDestination.isEmpty ? 0 : max(1 - now.timeIntervalSince(timeLastNoticed) / notificationTimeToLive, 0)
        let mostFrequentlyNoticedUtility = notificationsFromDestination.isEmpty ? 0 : max(1 - now.timeIntervalSince(timeLastNoticed) / Double(notificationsFromDestination.count) * notificationTimeToLive, 0)
        let powerUtility = max(getBatteryLevel(), 0) // More basic approach than in the paper, but probably fine since all devices have roughly the same battery capacity
        let rediscoveryIntervalUtility: Double = max(initialRediscoveryInterval / rediscoveryInterval, 0)
        let utility = (mostRecentlyNoticedUtility + mostFrequentlyNoticedUtility + powerUtility + rediscoveryIntervalUtility) / 4
        let utilityBucket = min(UInt8(utility * 16), 15)
        Logger.notification.info("NotificationManager did compute utility for hashedDestinationAddress (\(Utils.printID(hashedDestinationAddress))) as \(utilityBucket)/15: (\(mostRecentlyNoticedUtility) + \(mostFrequentlyNoticedUtility) + \(powerUtility) + \(rediscoveryIntervalUtility)) / 4 = \(utility)")
        return utilityBucket
    }
    
    private func getBatteryLevel() -> Double {
        UIDevice.current.isBatteryMonitoringEnabled = true
        let batteryLevel = UIDevice.current.batteryLevel
        UIDevice.current.isBatteryMonitoringEnabled = false
        return Double(batteryLevel)
    }
    
    func receiveAcknowledgement(_ data: Data, from id: String) -> Bool { // TODO: parameter id needed?
        Logger.notification.debug("NotificationManager attempts to \(#function) of \(data.count) bytes from '\(Utils.printID(id))'")
        guard !isResetting else {
            Logger.notification.error("NotificationManager is currently resetting and will ignore the acknowledgement data")
            return false
        }
        guard data.count >= acknowledgementLength else { // TODO: throw
            Logger.notification.error("NotificationManager will ignore the acknowledgement data as it's not \(self.acknowledgementLength) bytes long")
            return false
        }
        let controlByte = ControlByte(UInt8(data[0]))
        let hashedID = data.subdata(in: 1..<33)
        switch type! {
        case .direct, .epidemic:
            Logger.notification.error("NotificationManager does not support \(#function)")
            return false
        case .binarySprayAndWait, .disconnectedTransitiveCommunication:
            Logger.notification.debug("NotificationManager attempts to \(#function) of #\(Utils.printID(hashedID)) \(controlByte.description)")
            guard controlByte.destinationControlValue > 0 else { // TODO: throw
                Logger.notification.error("NotificationManager does not support \(#function) with destinationControlValue 0")
                return false
            }
            guard let notification = fetch(with: data) else { // TODO: throw
                Logger.notification.error("NotificationManager did not find a matching notification in storage")
                return false
            }
            guard notification.controlByte.destinationControlValue > 0 else { // TODO: throw
                Logger.notification.error("NotificationManager will ignore the acknowledgement because it matches a notification with destinationControlValue 0")
                return false
            }
            guard !notification.hasBeenAcknowledged else {
                Logger.notification.error("NotificationManager will ignore the acknowledgement because it matches a notification that has already been acknowledged")
                return false
            }
            guard controlByte.destinationControlValue != 2 else {
                try! notification.controlByte.setDestinationControl(to: 0)
                notification.hasBeenAcknowledged = true
                Logger.notification.info("NotificationManager has set setDestinationControl(to: 0) for notification #\(Utils.printID(hashedID)) because it has been acknowledged by the destination")
                return true
            }
            if type == .binarySprayAndWait {
                guard controlByte.destinationControlValue != 3 else { // TODO: throw
                    Logger.notification.error("NotificationManager does not support \(#function) with destinationControlValue 3")
                    return false
                } // controlByte.destinationControlValue == 1
                do {
                    try notification.controlByte.setSequenceNumber(to: notification.controlByte.sequenceNumberValue / 2)
                    notification.hasBeenAcknowledged = true
                    Logger.notification.info("NotificationManager halfed the sequenceNumberValue for notification #\(Utils.printID(hashedID))")
                    return true
                } catch BleepError.invalidControlByteValue {
                    try! notification.controlByte.setDestinationControl(to: 2)
                    notification.hasBeenAcknowledged = true
                    Logger.notification.info("NotificationManager could not half the sequenceNumberValue and therefore has set setDestinationControl(to: 2) for notification #\(Utils.printID(hashedID))")
                    return true
                } catch {
                    Logger.notification.error("NotificationManager encountered an unexpected error while trying to modify the controlByte for notification #\(Utils.printID(hashedID))")
                    return false
                }
            } else { // type == .disconnectedTransitiveCommunication
                guard controlByte.destinationControlValue != 1 else { // TODO: throw
                    Logger.notification.error("NotificationManager does not support \(#function) with destinationControlValue 1")
                    return false
                } // controlByte.destinationControlValue == 3
                let utility = controlByte.sequenceNumberValue
                notification.collectedUtilites.append(utility)
                Logger.notification.info("NotificationManager has received an utility response and added it to the collectedUtilites array of notification #\(Utils.printID(hashedID))")
                return true
            }
        }
    }
    
    // MARK: sending
    
    func sendNotification(_ message: String, to destinationAddress: Address) {
        Logger.notification.debug("NotificationManager attempts to \(#function) message '\(message)' to \(destinationAddress.description)")
        guard !isResetting else {
            Logger.notification.error("NotificationManager is currently resetting and will not \(#function)")
            return
        }
        var controlByte: ControlByte!
        switch type! {
        case .direct:
            controlByte = try! ControlByte(protocolValue: type.rawValue, destinationControlValue: 2, sequenceNumberValue: 0)
        case .epidemic:
            controlByte = try! ControlByte(protocolValue: type.rawValue, destinationControlValue: 1, sequenceNumberValue: 0)
        case .binarySprayAndWait:
            controlByte = try! ControlByte(protocolValue: type.rawValue, destinationControlValue: 1, sequenceNumberValue: initialNumberOfCopies-1)
        case .disconnectedTransitiveCommunication:
            controlByte = try! ControlByte(protocolValue: type.rawValue, destinationControlValue: 3, sequenceNumberValue: 0)
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
    
    func transmitNotifications() { // Get's called after a consumer subscribed to this provider and each time a transmission fails
        Logger.notification.trace("NotificationManager may attempt to \(#function)")
        guard !isResetting else {
            Logger.notification.error("NotificationManager is currently resetting and will not \(#function)")
            return
        }
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
            Logger.notification.trace("NotificationManager attempts to transmit notification #\(Utils.printID(notification.hashedID))")
            if type == .disconnectedTransitiveCommunication {
                guard notification.lastRediscovery == nil || notification.lastRediscovery! < Date(timeIntervalSinceNow: -rediscoveryInterval) else {
                    Logger.notification.debug("NotificationManager skips transmitting notification #\(Utils.printID(notification.hashedID)) because its rediscoveryInterval has not yet elapsed")
                    continue
                }
                let utilityThreshold = computeUtility(for: notification.hashedDestinationAddress)
                try! notification.controlByte.setSequenceNumber(to: utilityThreshold)
                Logger.notification.debug("NotificationManager has setSequenceNumber(to:) utilityThreshold \(utilityThreshold) for notification #\(Utils.printID(notification.hashedID))")
            }
            if transmitNotification(notification) {
                transmitQueue[notification] = true
                notification.lastRediscovery = Date.now
                rediscoveryInterval *= 2
                if simulator.evaluationLogger == nil {
                    Logger.notification.warning("NotificationManager did not log for evaluation because the evaluationLogger property of the simulator is nil")
                } else {
                    simulator.evaluationLogger!.log(notification, at: address)
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
            // NotificationManager will start to advertise again, when sendNotification() or receiveNotification() get called
            transmitQueue.removeAll()
            isReadyToAdvertise = true
        } else {
            Logger.notification.warning("NotificationManager did not transmit GOODBYE")
            return // peripheralManagerIsReady(toUpdateSubscribers) will call transmitNotifications() again
        }
    }
    
    private func transmitNotification(_ notification: Notification) -> Bool {
        Logger.notification.debug("NotificationManager attempts to \(#function) \(notification.description) with message: '\(notification.message)'")
        var modifiedControlByte = notification.controlByte
        switch type! {
        case .direct, .epidemic:
            Logger.notification.trace("NotificationManager did not modify the controlByte")
        case .binarySprayAndWait:
            do {
                try modifiedControlByte.setSequenceNumber(to: modifiedControlByte.sequenceNumberValue / 2)
                Logger.notification.trace("NotificationManager halfed the sequenceNumberValue")
            } catch BleepError.invalidControlByteValue {
                try! modifiedControlByte.setDestinationControl(to: 2)
                Logger.notification.trace("NotificationManager could not half the sequenceNumberValue and has therefore setDestinationControl(to: 2)")
            } catch {
                Logger.notification.error("NotificationManager encountered an unexpected error while trying to modify the controlByte")
                return false
            }
            Logger.notification.debug("NotificationManager will \(#function) notification #\(Utils.printID(notification.hashedID)) with a modifiedControlByte: \(modifiedControlByte.description)")
        case .disconnectedTransitiveCommunication:
            Logger.notification.debug("NotificationManager attempts to determine the utilityThreshold of notification  #\(Utils.printID(notification.hashedID)) based on the following collectedUtilites: \(notification.collectedUtilites)")
            let utilityThreshold = notification.collectedUtilites.sorted(by: >).first ?? computeUtility(for: notification.hashedDestinationAddress)
            try! notification.controlByte.setSequenceNumber(to: utilityThreshold)
            Logger.notification.trace("NotificationManager setSequenceNumber(to:) utilityThreshold \(utilityThreshold)")
            if notification.lastRediscovery == nil || notification.lastRediscovery! < Date(timeIntervalSinceNow: -utilityCollectionTimeout) {
                try! notification.controlByte.setDestinationControl(to: 3)
            } else {
                try! notification.controlByte.setDestinationControl(to: 2)
            }
            modifiedControlByte = notification.controlByte
        }
        var data = Data()
        data.append(modifiedControlByte.value)
        data.append(notification.hashedID)
        data.append(notification.hashedDestinationAddress)
        data.append(notification.hashedSourceAddress)
        data.append(notification.sentTimestampData)
        assert(data.count == minNotificationLength)
        if let messageData = notification.message.data(using: .utf8) { data.append(messageData) }
        if connectionManager.publish(data) {
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
        return connectionManager.publish(data)
    }
    
    private func acknowledge(_ notification: Notification, to id: String, with controlByte: ControlByte? = nil) {
        Logger.notification.trace("NotificationManager attempts to \(#function)")
        let controlByte = controlByte ?? notification.controlByte
        var data = Data()
        data.append(controlByte.value)
        data.append(notification.hashedID)
        assert(data.count == acknowledgementLength)
        if connectionManager.acknowledge(data, to: id) {
            Logger.notification.info("NotificationManager did \(#function) #\(Utils.printID(notification.hashedID)) \(controlByte.description) to '\(Utils.printID(id))'")
        } else {
            Logger.notification.error("NotificationManager did not \(#function) #\(Utils.printID(notification.hashedID)) \(controlByte.description) to '\(Utils.printID(id))'")
        }
    }
    
    // MARK: persisting
    
    private func insert(_ notification: Notification) {
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
        return try? context.fetch(FetchDescriptor<Notification>(predicate: #Predicate<Notification> { return $0.controlByte.destinationControlValue > 0 }))
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
            try! notification.controlByte.setDestinationControl(to: 0)
            Logger.notification.trace("NotificationManager setDestinationControl(to: 0) for notification #\(Utils.printID(notification.hashedID)) because it exceeded the notificationTimeToLive")
        }
    }
}
