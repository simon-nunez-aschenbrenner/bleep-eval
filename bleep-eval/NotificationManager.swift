//
//  NotificationManager.swift
//  bleep-eval
//
//  Created by Simon Núñez Aschenbrenner on 10.06.24.
//

import Foundation
import OSLog
import SwiftData

// MARK: NotificationManager

protocol NotificationManager: AnyObject {
    
    // For simulation/evaluation
    var evaluationLogger: EvaluationLogger? { get set }
    var rssiThreshold: Int8! { get set }
    var receivedHashedIDs: Set<Data>! { get }
    func setNumberOfCopies(to value: UInt8) throws

    var type: NotificationManagerType!{ get set }
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
    var id: Self { self }
    var description: String {
        switch self {
        case .direct: return "Direct"
        case .epidemic: return "Epidemic"
        case .binarySprayAndWait: return "Binary Spray and Wait"
        }
    }
}

@Observable
class BleepManager: NotificationManager {
    
    let minNotificationLength: Int = 105
    let acknowledgementLength: Int = 32
    
    var type: NotificationManagerType! {
        didSet {
            Logger.notification.info("NotificationManager type set to '\(self.type.description)'")
        }
    }
    var evaluationLogger: EvaluationLogger?
    var rssiThreshold: Int8! = -128 {
        didSet {
            Logger.notification.debug("NotificationManager rssiThreshold set to \(self.rssiThreshold)")
        }
    }
    
    private(set) var maxMessageLength: Int!
    private(set) var address: Address!
    private(set) var contacts: [Address]!
    private(set) var inbox: [Notification]! = []
    private(set) var receivedHashedIDs: Set<Data>! = []
    
    private var numberOfCopies: UInt8! { // L
        didSet {
            Logger.notification.debug("NotificationManager numberOfCopies set to \(self.numberOfCopies)")
        }
    }
    private var transmitQueue: [Notification: Bool]! = [:]
    private var connectionManager: ConnectionManager!
    private var container: ModelContainer!
    private var context: ModelContext!
    
    // MARK: initializing
    
    init(type: NotificationManagerType, connectionManagerType: ConnectionManager.Type, numberOfCopies: UInt8) throws {
        Logger.notification.trace("\(type) NotificationManager initializes")
        self.type = type
        self.container = try! ModelContainer(for: Notification.self, Address.self)
        self.context = ModelContext(self.container)
        self.context.autosaveEnabled = true
        resetContext(notifications: true)
        initAddress()
        initContacts()
        updateInbox()
        populateReceivedHashedIDsArray()
        try setNumberOfCopies(to: numberOfCopies)
        self.connectionManager = connectionManagerType.init(notificationManager: self)
        self.maxMessageLength = self.connectionManager.maxNotificationLength - self.minNotificationLength
        Logger.notification.trace("\(type) NotificationManager initialized")
    }
    
    convenience init(type: NotificationManagerType, connectionManagerType: ConnectionManager.Type) {
        try! self.init(type: type, connectionManagerType: connectionManagerType, numberOfCopies: 15)
    }
    
    private func resetContext(notifications: Bool = false, address: Bool = false) {
        Logger.notification.debug("NotificationManager attempts to \(#function): notifications=\(notifications), address=\(address)")
        if notifications { try! self.context.delete(model: Notification.self) }
        if address { try! self.context.delete(model: Address.self) }
    }
    
    private func initAddress() {
        Logger.notification.trace("NotificationManager initializes its address")
        let fetchResult = try? context.fetch(FetchDescriptor<Address>(predicate: #Predicate<Address> { return $0.isOwn == true }))
        if fetchResult == nil || fetchResult!.isEmpty {
            Logger.notification.info("NotificationManager is creating a new address for itself")
            let address = Address()
            context.insert(address)
            self.address = address
        } else {
            self.address = fetchResult![0]
            Logger.notification.trace("NotificationManager found its address in storage")
        }
        if let name = Utils.addressBook.first(where: { $0 == self.address })?.name {
            self.address.name = name
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
    
    func setNumberOfCopies(to value: UInt8) throws {
        Logger.notification.trace("NotificationManager attempts to \(#function)")
        guard value < 16 else {
            throw BleepError.invalidControlByteValue
        }
        self.numberOfCopies = value
    }
    
    // MARK: incoming
    
    func receiveNotification(_ data: Data) {
        Logger.notification.debug("NotificationManager attempts to \(#function) of \(data.count-self.minNotificationLength)+\(self.minNotificationLength)=\(data.count) bytes")
        guard data.count >= minNotificationLength else { // TODO: throw
            Logger.notification.error("NotificationManager will ignore the notification data as it's not at least \(self.minNotificationLength) bytes long")
            return
        }
        let controlByte = ControlByte(value: UInt8(data[0]))
        let hashedID = data.subdata(in: 1..<33)
        let hashedDestinationAddress = data.subdata(in: 33..<65)
        let hashedSourceAddress = data.subdata(in: 65..<97)
        let sentTimestampData = data.subdata(in: 97..<105)
        let messageData = data.subdata(in: 105..<data.count)
        let message: String = String(data: messageData, encoding: .utf8) ?? ""
        guard controlByte.destinationControlValue > 0 else {
            Logger.notification.info("NotificationManager successfully received endOfNotificationsSignal")
            connectionManager.disconnect()
            return
        }
        guard controlByte.protocolValue == type.rawValue else { // TODO: throw
            Logger.notification.error("NotificationManager will ignore notification #\(Utils.printID(hashedID)), as its protocolValue \(controlByte.protocolValue) doesn't match the type.rawValue \(self.type.rawValue)")
            return
        }
        guard !receivedHashedIDs.contains(hashedID) else {
            Logger.notification.info("NotificationManager will ignore notification #\(Utils.printID(hashedID)) as it is already stored")
            return
        }
        let notification = Notification(controlByte: controlByte, hashedID: hashedID, hashedDestinationAddress: hashedDestinationAddress, hashedSourceAddress: hashedSourceAddress, sentTimestampData: sentTimestampData, message: message)
        guard accept(notification) else {
            Logger.notification.info("NotificationManager will ignore notification #\(Utils.printID(hashedID)) as accept(notification) returned false")
            return
        }
        Logger.notification.trace("NotificationManager appends hashedID #\(Utils.printID(hashedID)) to the receivedHashedIDs set")
        receivedHashedIDs.insert(hashedID)
        Logger.notification.info("NotificationManager successfully received notification \(notification.description) with message: '\(notification.message)'")
        if notification.hashedDestinationAddress == self.address.hashed { // TODO: In the future we may want to handle the notification as any other and resend it to obfuscate it was meant for us
            try! notification.setDestinationControl(to: 0)
            Logger.notification.info("NotificationManager has setDestinationControl(to: 0) for notification #\(Utils.printID(notification.hashedID)) because it reached its destination")
            updateInbox(with: notification)
        }
        if evaluationLogger == nil {
            Logger.notification.warning("NotificationManager did not call evaluationLogger.log() because the evaluationLogger property is nil")
        } else {
            evaluationLogger!.log(notification, at: self.address)
        }
        insert(notification)
    }
    
    func receiveAcknowledgement(_ data: Data) -> Bool {
        guard type.rawValue > 1 else {
            Logger.notification.error("NotificationManager does not support \(#function)")
            return false
        }
        Logger.notification.debug("NotificationManager attempts to \(#function) of \(data.count) bytes")
        guard data.count == self.acknowledgementLength else { // TODO: throw
            Logger.notification.error("NotificationManager will ignore the acknowledgement data as it's not \(self.acknowledgementLength) bytes long")
            return false
        }
        guard let notification = fetch(with: data) else { // TODO: throw
            Logger.notification.error("NotificationManager did not find a matching notification in storage")
            return false
        }
        do {
            try notification.setSequenceNumber(to: notification.sequenceNumberValue/2)
            Logger.notification.info("NotificationManager halfed the sequenceNumberValue of notification \(notification.description)")
            return true
        } catch {
            try! notification.setDestinationControl(to: 2) // TODO: throw
            Logger.notification.error("NotificationManager could not half the sequenceNumberValue and therefore has set setDestinationControl(to: 2) for notification \(notification.description)")
            return false
        }
    }
    
    private func accept(_ notification: Notification) -> Bool {
        switch type! {
        case .direct:
            return notification.destinationControlValue == 2 && notification.hashedDestinationAddress == self.address.hashed
        case .epidemic:
            return notification.destinationControlValue == 1
        case .binarySprayAndWait:
            if notification.destinationControlValue == 1 || notification.hashedDestinationAddress == self.address.hashed {
                acknowledge(notification)
                return true
            } else {
                return false
            }
        }
    }
    
    private func populateReceivedHashedIDsArray() {
        Logger.notification.trace("NotificationManager attempts to \(#function)")
        let hashedIDs = fetchAllHashedIDs()
        if hashedIDs == nil || hashedIDs!.isEmpty {
            Logger.notification.debug("NotificationManager has no hashedIDs to add to the receivedHashedIDs set")
        } else {
            receivedHashedIDs = Set(hashedIDs!)
            Logger.notification.debug("NotificationManager has successfully populated the receivedHashedIDs set with \(self.receivedHashedIDs.count) hashedIDs")
        }
    }
    
    private func updateInbox() {
        Logger.notification.trace("NotificationManager attempts to \(#function)")
        let countBefore = inbox.count
        inbox = fetchAll(for: self.address.hashed) ?? []
        Logger.notification.debug("NotificationManager added \(self.inbox.count - countBefore) notification(s) to the inbox")
    }
    
    private func updateInbox(with notification: Notification) {
        Logger.notification.debug("NotificationManager attempts to \(#function) notification #\(Utils.printID(notification.hashedID))")
//        TODO: uncomment when check doesn't happen in receiveNotification(_ data: Data) anymore
//        guard notification.hashedDestinationAddress == self.address.hashed else {
//            Logger.notification.debug("NotificationManager won't \(#function) notification #\(Utils.printID(notification.hashedID)) because its hashedDestinationAddress doesn't match the hashed notificationManager address")
//            return
//        }
        let countBefore = inbox.count
        inbox.append(notification)
        Logger.notification.debug("NotificationManager added \(self.inbox.count - countBefore) notification to the inbox")
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
            controlByte = try! ControlByte(protocolValue: type.rawValue, destinationControlValue: 1, sequenceNumberValue: numberOfCopies)
        }
        insert(Notification(controlByte: controlByte, sourceAddress: address, destinationAddress: destinationAddress, message: message))
    }
    
    func transmitNotifications() {
        Logger.notification.trace("NotificationManager may attempt to \(#function)")
        if transmitQueue.isEmpty { populateTransmitQueue() }
        Logger.notification.debug("NotificationManager attempts to \(#function) with \(self.transmitQueue.values.filter { !$0 }.count)/\(self.transmitQueue.count) notifications in the transmitQueue")
        for element in transmitQueue {
            guard !element.value else {
                Logger.notification.trace("NotificationManager skips transmitting notification #\(Utils.printID(element.key.hashedID)) because it was already transmitted")
                continue
            }
            if transmit(element.key) {
                transmitQueue[element.key] = true
                if evaluationLogger == nil {
                    Logger.notification.warning("NotificationManager did not call evaluationLogger.log() because the evaluationLogger property is nil")
                } else {
                    evaluationLogger!.log(element.key, at: self.address)
                }
                continue
            } else {
                return // peripheralManagerIsReady(toUpdateSubscribers) will call transmitNotifications() again
            }
        }
        Logger.notification.trace("NotificationManager skipped or finished the \(#function) loop successfully")
        transmitEndOfNotificationsSignal()
    }
    
    private func transmit(_ notification: Notification) -> Bool {
        Logger.notification.debug("NotificationManager attempts to \(#function) \(notification.description) with message: '\(notification.message)'")
        var newControlByte: ControlByte?
        if type == .binarySprayAndWait {
            do {
                newControlByte = try ControlByte(protocolValue: notification.protocolValue, destinationControlValue: notification.destinationControlValue, sequenceNumberValue: notification.sequenceNumberValue/2)
                Logger.notification.trace("NotificationManager halfed the sequenceNumberValue of the newControlByte")
            } catch BleepError.invalidControlByteValue {
                newControlByte = try! ControlByte(protocolValue: notification.protocolValue, destinationControlValue: 2, sequenceNumberValue: notification.sequenceNumberValue)
                Logger.notification.trace("NotificationManager could not half the sequenceNumberValue and has therefore setDestinationControl(to: 2) for the newControlByte")
            } catch {
                Logger.notification.error("NotificationManager encountered an unexpected error while trying to create a newControlByte")
                return false
            }
            Logger.notification.debug("NotificationManager will \(#function) notification #\(Utils.printID(notification.hashedID)) with a newControlByte: \(newControlByte!.description)")
        }
        var data = Data()
        data.append(newControlByte?.value ?? notification.controlByte)
        data.append(notification.hashedID)
        data.append(notification.hashedDestinationAddress)
        data.append(notification.hashedSourceAddress)
        data.append(notification.sentTimestampData)
        assert(data.count == minNotificationLength)
        if let messageData = notification.message.data(using: .utf8) { data.append(messageData) }
        if connectionManager.transmit(notification: data) {
            Logger.notification.info("NotificationManager successfully transmitted notification data of \(data.count-self.minNotificationLength)+\(self.minNotificationLength)=\(data.count) bytes")
            return true
        } else {
            Logger.notification.warning("NotificationManager did not transmit notification data of \(data.count-self.minNotificationLength)+\(self.minNotificationLength)=\(data.count) bytes")
            return false
        }
    }
    
    private func transmitEndOfNotificationsSignal() {
        Logger.notification.trace("NotificationManager attempts to \(#function)")
        let controlByte = try! ControlByte(protocolValue: self.type.rawValue, destinationControlValue: 0, sequenceNumberValue: 0)
        var data = Data()
        data.append(controlByte.value)
        data.append(Data(count: minNotificationLength-data.count))
        assert(data.count == minNotificationLength)
        if connectionManager.transmit(notification: data) {
            Logger.notification.info("NotificationManager successfully transmitted \(data.count) zeros and will remove all notifications from the sendQueue")
            self.transmitQueue.removeAll()
        } else {
            Logger.notification.warning("NotificationManager did not transmit \(data.count) zeros")
            // peripheralManagerIsReady(toUpdateSubscribers) will call transmitNotifications() again
        }
    }
    
    private func populateTransmitQueue() {
        Logger.notification.trace("NotificationManager attempts to \(#function)")
        let notifications = fetchAllTransmittable()
        if notifications == nil || notifications!.isEmpty {
            Logger.notification.debug("NotificationManager has no notifications to add to the transmitQueue")
        } else {
            self.transmitQueue = notifications!.reduce(into: [Notification: Bool]()) { $0[$1] = false }
            Logger.notification.debug("NotificationManager has successfully populated the transmitQueue with \(self.transmitQueue.count) notification(s): \(self.transmitQueue)")
        }
    }
    
    private func acknowledge(_ notification: Notification) {
        Logger.notification.debug("NotificationManager attempts to \(#function) #\(Utils.printID(notification.hashedID))")
        connectionManager.acknowledge(hashedID: notification.hashedID)
    }
    
    // MARK: persisting
    
    func insert(_ notification: Notification) {
        Logger.notification.debug("NotificationManager attempts to \(#function) notification #\(Utils.printID(notification.hashedID))")
        context.insert(notification)
        save()
        connectionManager.advertise(with: String(Address().base58Encoded.suffix(8)))
    }
    
    private func fetchAll() -> [Notification]? {
        Logger.notification.trace("NotificationManager attempts to \(#function)")
        return try? context.fetch(FetchDescriptor<Notification>())
    }
    
    private func fetchAllTransmittable() -> [Notification]? {
        Logger.notification.debug("NotificationManager attempts to \(#function)")
        return try? context.fetch(FetchDescriptor<Notification>(predicate: #Predicate<Notification> { return $0.destinationControlValue != 0 }))
    }
    
    private func fetchAllTransmittableCount() -> Int {
        Logger.notification.debug("NotificationManager attempts to \(#function)")
        let result = try? context.fetchCount(FetchDescriptor<Notification>(predicate: #Predicate<Notification> { return $0.destinationControlValue != 0 }))
        return result ?? 0
    }
    
    private func fetchAll(for hashedAddress: Data) -> [Notification]? {
        Logger.notification.debug("NotificationManager attempts to \(#function) for hashedAddress (\(Utils.printID(hashedAddress)))")
        let predicate = #Predicate<Notification> { $0.hashedDestinationAddress == hashedAddress }
        return try? context.fetch(FetchDescriptor<Notification>(predicate: predicate))
    }
    
    private func fetchAllHashedIDs() -> [Data]? {
        Logger.notification.trace("NotificationManager attempts to \(#function)")
        guard let results = fetchAll() else { return nil }
        return results.map { $0.hashedID }
    }
    
    private func fetch(with hashedID: Data) -> Notification? {
        Logger.notification.debug("NotificationManager attempts to \(#function) #\(Utils.printID(hashedID))")
        let fetchDescriptor = FetchDescriptor<Notification>(predicate: #Predicate { notification in notification.hashedID == hashedID })
        return try? context.fetch(fetchDescriptor)[0]
    }
    
    private func save() {
        do {
            try context.save()
            Logger.notification.trace("NotificationManager saved the context")
        } catch { // TODO: throw
            Logger.notification.error("NotificationManager failed to save the context: \(error)")
        }
    }
    // TODO: deletion methods
}
