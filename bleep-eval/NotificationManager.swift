//
//  NotificationManager.swift
//  bleep-eval
//
//  Created by Simon Núñez Aschenbrenner on 10.06.24.
//

import Foundation
import SwiftData
import OSLog

// MARK: NotificationManager protocol

protocol NotificationManager: AnyObject {
    
    var address: Address! { get }
    var receivedQueue: [Notification]! { get }
    var sendQueue: [Notification: Bool]! { get }
    
    var isPublishing: Bool! { get }
    var isSubscribing: Bool! { get }
    var isIdling: Bool! { get }
            
    func decide()
    func publish()
    func subscribe()
    func idle()
    
    func receiveNotification(data: Data, from peripheralUUID: String)
    func receiveAcknowledgement(data: Data)
    func sendNotifications()
    
    func create(destinationAddress: Address, message: String) -> Notification
    func insert(_ notification: Notification)
    func save()
    
}

// MARK: Epidemic superclass

@Observable
class Epidemic: NotificationManager {
    
    let protocolValue: UInt8!
        
    final private var container: ModelContainer!
    final private var context: ModelContext!
    final private let sendablePredicate = #Predicate<Notification> { return $0.destinationControlValue != 0 }
    
    final private(set) var address: Address!
    final fileprivate var connectionManager: ConnectionManager!
    
    final private(set) var sendQueue: [Notification: Bool]! = [:]
    final private(set) var receivedQueue: [Notification]! = []
    final fileprivate var acknowledgedHashedIDs: [Data]! = []
    final fileprivate var receivedHashedIDs: [Data]! = []
        
    final var isPublishing: Bool! { return connectionManager.mode.isProvider }
    final var isSubscribing: Bool! { return connectionManager.mode.isConsumer }
    final var isIdling: Bool! { return connectionManager.mode.isUndefined }
    
    // MARK: initializing methods
    
    fileprivate init(protocolValue: UInt8, connectionManagerType: ConnectionManager.Type) {
        self.protocolValue = protocolValue
        self.connectionManager = connectionManagerType.init(notificationManager: self)
        self.container = try! ModelContainer(for: Notification.self, Address.self)
        self.context = ModelContext(self.container)
        self.context.autosaveEnabled = true
        try! self.context.delete(model: Notification.self) // TODO: delete
//        try! self.context.delete(model: Address.self) // TODO: delete
        initAddress()
        Logger.notification.trace("NotificationManager with protocolValue \(self.protocolValue) initialized")
        self.decide()
    }
    
    convenience init(connectionManagerType: ConnectionManager.Type) {
        self.init(protocolValue: 0, connectionManagerType: connectionManagerType)
    }
    
    final private func initAddress() {
        let fetchResult = try? context.fetch(FetchDescriptor<Address>(predicate: #Predicate<Address> { return $0.isOwn == true }))
        if fetchResult == nil || fetchResult!.isEmpty {
            Logger.notification.info("NotificationManager is creating a new address for itself")
            let address = Address()
            context.insert(address)
            save()
            self.address = address
        } else {
            self.address = fetchResult![0]
            Logger.notification.trace("NotificationManager found its address in storage")
        }
        Logger.notification.debug("NotificationManager address: \(self.address!.description)")
    }
    
    // MARK: state changing methods
    
    final func decide() {
        Logger.notification.info("NotificationManager attempts to \(#function) whether to publish() or subscribe()")
        let sendableCount = fetchAllSendableCount()
        Logger.notification.debug("NotificationManager sendableCount = \(sendableCount)")
        if sendableCount > 0 && !isPublishing {
            publish()
        } else if !isSubscribing {
            subscribe()
        }
    }
    
    final func publish() {
        Logger.notification.trace("NotificationManager attempts to \(#function) notifications")
        populateSendQueue()
        connectionManager.setMode(to: .provider)
    }
    
    final func subscribe() {
        Logger.notification.trace("NotificationManager attempts to \(#function) to notifications")
        populateReceivedHashedIDsArray()
        connectionManager.setMode(to: .consumer)
    }
    
    final func idle() {
        Logger.notification.debug("NotificationManager attempts to \(#function)")
        connectionManager.setMode(to: .undefined)
    }
    
    // MARK: receiving methods
    
    final fileprivate func populateReceivedHashedIDsArray() {
        Logger.notification.trace("NotificationManager attempts to \(#function)")
        let hashedIDs = fetchAllHashedIDs()
        if hashedIDs == nil || hashedIDs!.isEmpty {
            Logger.notification.debug("NotificationManager has no hashedIDs to add to the receivedHashedIDs array")
        } else {
            self.receivedHashedIDs = hashedIDs!
            Logger.notification.debug("NotificationManager has successfully populated the receivedHashedIDs array with \(self.receivedHashedIDs.count) hashedIDs")
        }
    }
    
    final func receiveNotification(data: Data, from peripheralUUID: String) {
        Logger.notification.debug("NotificationManager attempts to \(#function) of \(data.count-minNotificationLength)+\(minNotificationLength)=\(data.count) bytes")
        guard data.count >= minNotificationLength else { // TODO: handle
            Logger.notification.warning("NotificationManager will ignore the notification data as it's not at least \(minNotificationLength) bytes long")
            return
        }
        let controlByte = ControlByte(value: UInt8(data[0]))
        let hashedID = data.subdata(in: 1..<33)
        let hashedDestinationAddress = data.subdata(in: 33..<65)
        let hashedSourceAddress = data.subdata(in: 65..<97)
        let sentTimestampData = data.subdata(in: 97..<105)
        let messageData = data.subdata(in: 105..<data.count)
        let message: String = String(data: messageData, encoding: .utf8) ?? ""
        guard controlByte.protocolValue == protocolValue else { // TODO: handle
            Logger.notification.error("NotificationManager can't process the notification data because its protocolValue \(self.protocolValue) doesn't match the notification's controlByte protocolValue \(controlByte.protocolValue)")
            return
        }
        guard controlByte.destinationControlValue > 0 else { // TODO: Needs timeout solution as well, so we are not dependent on the peripheral to disconnect
            Logger.notification.info("Received endOfNotificationsSignal")
            save()
            decide()
            return
        }
        guard receivedHashedIDs.contains(hashedID) else {
            Logger.notification.info("NotificationManager will ignore notification #\(printID(hashedID)) as it is already stored")
            return
        }
        guard controlByte.destinationControlValue == 2 && hashedDestinationAddress != self.address.hashed else {
            Logger.notification.info("NotificationManager will ignore notification #\(printID(hashedID)), as its hashedDestinationAddress (\(printID(hashedDestinationAddress))) doesn't match the hashed notificationManager address (\(printID(self.address.hashed)))")
            return
        }
        receivedHashedIDs.append(hashedID)
        receiveNotification(Notification(controlByte: controlByte, hashedID: hashedID, hashedDestinationAddress: hashedDestinationAddress, hashedSourceAddress: hashedSourceAddress, sentTimestampData: sentTimestampData, message: message), from: peripheralUUID)
    }
    
    fileprivate func receiveNotification(_ notification: Notification, from peripheralUUID: String) {
        insert(notification)
        Logger.notification.info("NotificationManager successfully received notification \(notification.description) with message: '\(notification.message)'")
    }
    
    func receiveAcknowledgement(data: Data) { // TODO: handle
        Logger.notification.warning("NotificationManager does not support \(#function)")
        return
    }
    
    // MARK: sending methods
    
    final fileprivate func populateSendQueue() {
        Logger.notification.trace("NotificationManager attempts to \(#function)")
        let notifications = fetchAllSendable()
        if notifications == nil || notifications!.isEmpty {
            Logger.notification.debug("NotificationManager has no notifications to add to the sendQueue")
        } else {
            self.sendQueue = notifications!.reduce(into: [Notification: Bool]()) { $0[$1] = false }
            Logger.notification.debug("NotificationManager has successfully populated the sendQueue with \(self.sendQueue.count) notification(s): \(self.sendQueue)")
        }
    }
    
    final func sendNotifications() {
        Logger.notification.trace("NotificationManager attempts to \(#function)")
        for element in sendQueue {
            guard !element.value || element.key.destinationControlValue > 0 else {
                Logger.notification.trace("NotificationManager skips sending notification #\(printID(element.key.hashedID)) in the sendQueue because\(element.value ? " it is marked as sent" : "")\(element.key.destinationControlValue == 0 ? " and/or its destinationControlValue is 0" : "")")
                continue
            }
            if sendNotification(element.key) {
                sendQueue[element.key] = true
                continue
            } else {
                return // peripheralManagerIsReady(toUpdateSubscribers) will call sendNotifications() again
            }
        }
        Logger.notification.trace("NotificationManager skipped or finished the \(#function) loop successfully, will remove all notifications from the sendQueue")
        self.sendQueue.removeAll()
        sendEndOfNotificationsSignal()
    }
    
    fileprivate func sendNotification(_ notification: Notification) -> Bool {
        Logger.notification.debug("NotificationManager attempts to \(#function) \(notification.description) with message: '\(notification.message)'")
        var data = Data()
        data.append(notification.controlByte)
        data.append(notification.hashedID)
        data.append(notification.hashedDestinationAddress)
        data.append(notification.hashedSourceAddress)
        data.append(notification.sentTimestampData)
        assert(data.count == minNotificationLength)
        if let messageData = notification.message.data(using: .utf8) { data.append(messageData) }
        if connectionManager.send(notification: data) {
            Logger.notification.info("NotificationManager successfully sent notification data of \(data.count-minNotificationLength)+\(minNotificationLength)=\(data.count) bytes")
            return true
        } else {
            Logger.notification.warning("NotificationManager did not send notification data of \(data.count-minNotificationLength)+\(minNotificationLength)=\(data.count) bytes")
            return false
        }
    }
    
    final fileprivate func sendEndOfNotificationsSignal() {
        Logger.notification.trace("NotificationManager attempts to \(#function)")
        let controlByte = try! ControlByte(protocolValue: self.protocolValue, destinationControlValue: 0, sequenceNumberValue: 0)
        var data = Data()
        data.append(controlByte.value)
        data.append(Data(count: minNotificationLength-data.count))
        assert(data.count == minNotificationLength)
        if connectionManager.send(notification: data) {
            Logger.notification.info("NotificationManager successfully sent \(data.count) zeros")
            decide()
        } else {
            Logger.notification.warning("NotificationManager did not send \(data.count) zeros")
            // peripheralManagerIsReady(toUpdateSubscribers) will call sendNotifications() again
        }
    }
    
    // MARK: view updating methods
    
    final fileprivate func updateView() {
        Logger.notification.trace("NotificationManager attempts to \(#function)")
        let countBefore = receivedQueue.count
        save()
        receivedQueue = fetchAll(for: self.address.hashed) ?? []
        Logger.notification.debug("NotificationManager added \(self.receivedQueue.count - countBefore) notification(s) to the notificationView")
    }
    
    final fileprivate func updateView(with notification: Notification) {
        Logger.notification.debug("NotificationManager attempts to \(#function) notification #\(printID(notification.hashedID))")
        guard notification.hashedDestinationAddress == self.address.hashed else { // TODO: handle
            Logger.notification.warning("NotificationManager won't \(#function) notification #\(printID(notification.hashedID)) because its hashedDestinationAddress doesn't match the hashed notificationManager address")
            return
        }
        let countBefore = receivedQueue.count
        save()
        receivedQueue.insert(notification, at: 0)
        Logger.notification.debug("NotificationManager added \(self.receivedQueue.count - countBefore) notification to the notificationView")
    }
    
    // MARK: creation methods
    
    func create(destinationAddress: Address, message: String) -> Notification {
        let controlByte = try! ControlByte(protocolValue: self.protocolValue, destinationControlValue: 2, sequenceNumberValue: 0)
        return Notification(controlByte: controlByte, sourceAddress: self.address, destinationAddress: destinationAddress, message: message)
    }
    
    // MARK: counting methods
    
    final fileprivate func fetchAllSendableCount() -> Int {
        Logger.notification.debug("NotificationManager attempts to \(#function)")
        let result = try? context.fetchCount(FetchDescriptor<Notification>(predicate: sendablePredicate))
        return result ?? 0
    }
    
    // MARK: fetching methods
    
    final fileprivate func fetchAll() -> [Notification]? {
        Logger.notification.trace("NotificationManager attempts to \(#function)")
        return try? context.fetch(FetchDescriptor<Notification>())
    }
    
    final fileprivate func fetchAllSendable() -> [Notification]? {
        Logger.notification.debug("NotificationManager attempts to \(#function)")
        return try? context.fetch(FetchDescriptor<Notification>(predicate: sendablePredicate))
    }
    
    final fileprivate func fetchAll(for hashedAddress: Data) -> [Notification]? {
        Logger.notification.debug("NotificationManager attempts to \(#function) for hashedAddress (\(printID(hashedAddress)))")
        let predicate = #Predicate<Notification> { $0.hashedDestinationAddress == hashedAddress }
        return try? context.fetch(FetchDescriptor<Notification>(predicate: predicate))
    }
    
    final fileprivate func fetchAllHashedIDs() -> [Data]? {
        Logger.notification.trace("NotificationManager attempts to \(#function)")
        guard let results = fetchAll() else { return nil }
        return results.map { $0.hashedID }
    }
    
    final fileprivate func fetch(with hashedID: Data) -> Notification? {
        Logger.notification.debug("NotificationManager attempts to \(#function) #\(printID(hashedID))")
        let fetchDescriptor = FetchDescriptor<Notification>(predicate: #Predicate { notification in notification.hashedID == hashedID })
        return try? context.fetch(fetchDescriptor)[0]
    }
    
    // MARK: insertion methods
    
    final func insert(_ notification: Notification) {
        Logger.notification.debug("NotificationManager attempts to \(#function) notification #\(printID(notification.hashedID)) with message '\(notification.message)'")
        if notification.hashedDestinationAddress == self.address.hashed {
            try! notification.setDestinationControl(to: 0)
            Logger.notification.info("NotificationManager has setDestinationControl(to: 0) for notification #\(printID(notification.hashedID)) because its hashedDestinationAddress matches the hashed notificationManager address")
        }
        context.insert(notification)
        updateView(with: notification)
    }
    
    final func save() {
        do {
            try context.save()
            Logger.notification.trace("NotificationManager saved the context")
        } catch {
            Logger.notification.fault("NotificationManager failed to save the context: \(error)")
        }
    }
    
    // TODO: deletion methods
}

// MARK: Spray and Wait subclass

@Observable
class BinarySprayAndWait: Epidemic {
    
    var numberOfCopies: Int! // L

    init?(connectionManagerType: ConnectionManager.Type, numberOfCopies: Int) {
        super.init(protocolValue: 1, connectionManagerType: connectionManagerType)
        guard numberOfCopies < 16 else {
            return nil
        }
        self.numberOfCopies = numberOfCopies
    }
    
    // MARK: receiving methods
    
    override fileprivate func receiveNotification(_ notification: Notification, from peripheralUUID: String) {
        insert(notification)
        connectionManager.acknowledge(hashedID: notification.hashedID, to: peripheralUUID)
        Logger.notification.info("BinarySprayAndWaitNotificationManager successfully received notification \(notification.description) with message: '\(notification.message)'")
    }
    
    override func receiveAcknowledgement(data: Data) {
        Logger.notification.debug("BinarySprayAndWaitNotificationManager attempts to \(#function) of \(data.count) bytes")
        guard data.count == acknowledgementLength else { // TODO: handle
            Logger.notification.warning("BinarySprayAndWaitNotificationManager will ignore the acknowledgement data as it's not \(acknowledgementLength) bytes long")
            return
        }
        guard let notification = fetch(with: data) else { // TODO: handle
            Logger.notification.warning("BinarySprayAndWaitNotificationManager did not find a matching notification in storage")
            return
        }
        do {
            try notification.setSequenceNumber(to: notification.sequenceNumberValue/2)
            Logger.notification.info("BinarySprayAndWaitNotificationManager halfed the sequenceNumberValue of notification \(notification.description)")
        } catch {
            try! notification.setDestinationControl(to: 2)
            Logger.notification.info("BinarySprayAndWaitNotificationManager could not half the sequenceNumberValue and therefore has set setDestinationControl(to: 2) for notification \(notification.description)")
        }
    }
    
    // MARK: sending methods
    
    override fileprivate func sendNotification(_ notification: Notification) -> Bool {
        Logger.notification.debug("BinarySprayAndWaitNotificationManager attempts to sendNotification \(notification.description) with message: '\(notification.message)' and a newControlByte")
        var newControlByte: ControlByte!
        do {
            newControlByte = try ControlByte(protocolValue: notification.protocolValue, destinationControlValue: notification.destinationControlValue, sequenceNumberValue: notification.sequenceNumberValue/2)
            Logger.notification.trace("BinarySprayAndWaitNotificationManager halfed the sequenceNumberValue of the newControlByte")
        } catch BleepError.invalidControlByteValue {
            newControlByte = try! ControlByte(protocolValue: notification.protocolValue, destinationControlValue: 2, sequenceNumberValue: notification.sequenceNumberValue)
            Logger.notification.trace("BinarySprayAndWaitNotificationManager could not half the sequenceNumberValue and has therefore setDestinationControl(to: 2) for the newControlByte")
        } catch {
            Logger.notification.error("BinarySprayAndWaitNotificationManager encountered an unexpected error while trying to create a newControlByte")
        }
        Logger.notification.debug("Notification #\(printID(notification.hashedID)) newControlByte: \(newControlByte.description)")
        var data = Data()
        data.append(newControlByte.value)
        data.append(notification.hashedID)
        data.append(notification.hashedDestinationAddress)
        data.append(notification.hashedSourceAddress)
        data.append(notification.sentTimestampData)
        assert(data.count == minNotificationLength)
        if let messageData = notification.message.data(using: .utf8) {
            data.append(messageData)
        }
        if connectionManager.send(notification: data) {
            Logger.notification.info("BinarySprayAndWaitNotificationManager successfully sent notification data of \(data.count-minNotificationLength)+\(minNotificationLength)=\(data.count) bytes")
            return true
        } else {
            Logger.notification.warning("BinarySprayAndWaitNotificationManager did not send notification data of \(data.count-minNotificationLength)+\(minNotificationLength)=\(data.count) bytes")
            return false
        }
    }
    
    // MARK: creation methods
    
    override func create(destinationAddress: Address, message: String) -> Notification {
        let controlByte = try! ControlByte(protocolValue: self.protocolValue, destinationControlValue: 1, sequenceNumberValue: UInt8(self.numberOfCopies))
        return Notification(controlByte: controlByte, sourceAddress: self.address, destinationAddress: destinationAddress, message: message)
    }
    
}
