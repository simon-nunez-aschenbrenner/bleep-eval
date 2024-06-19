//
//  NotificationManager.swift
//  bleep-eval
//
//  Created by Simon Núñez Aschenbrenner on 10.06.24.
//

import Foundation
import SwiftData
import OSLog

// MARK: Superclass

@Observable
class NotificationManager {
    
    let protocolValue: UInt8!
        
    final internal var container: ModelContainer!
    final internal var context: ModelContext!
    final internal let sendablePredicate = #Predicate<Notification> { return $0.destinationControlValue != 0 }
    
    final private(set) var address: Address!
    final internal var connectionManager: ConnectionManager!
    
    final private(set) var view: [Notification] = []
    final private(set) var receivedHashedIDs: [Data] = []
    final private(set) var sendQueue: [Notification] = []
        
    final var isPublishing: Bool { return connectionManager.mode.isProvider }
    final var isSubscribing: Bool { return connectionManager.mode.isConsumer }
    final var isIdling: Bool { return connectionManager.mode.isUndefined }
    
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
    
    func publish() {
        Logger.notification.trace("NotificationManager attempts to \(#function) notifications")
        connectionManager.setMode(to: .provider)
    }
    
    func subscribe() {
        Logger.notification.trace("NotificationManager attempts to \(#function) to notifications")
        populateReceivedArray()
        connectionManager.setMode(to: .consumer)
    }
    
    func idle() {
        Logger.notification.debug("NotificationManager attempts to \(#function)")
        connectionManager.setMode(to: .undefined)
    }
    
    // MARK: receiving methods
    
    func receiveNotification(data: Data) {
        Logger.notification.debug("NotificationManager attempts to \(#function) of \(data.count-minNotificationLength)+\(minNotificationLength)=\(data.count) bytes")
        guard data.count >= minNotificationLength else { // TODO: handle
            Logger.notification.warning("NotificationManager will ignore the notification data as it's not at least \(minNotificationLength) bytes long")
            return
        }
        let controlByte = ControlByte(value: UInt8(data[0]))
        guard controlByte.protocolValue == protocolValue else { // TODO: handle
            Logger.notification.error("NotificationManager can't process the notification data because its protocolValue \(self.protocolValue) doesn't match the notification's controlByte protocolValue \(controlByte.protocolValue)")
            return
        }
        if controlByte.destinationControlValue == 0 { // TODO: Needs timeout solution as well, so we are not dependent on the peripheral to disconnect
            Logger.notification.info("Received data indicates no more notifications")
            save()
            idle()
        } else {
            let hashedID = data.subdata(in: 1..<33)
            Logger.notification.trace("NotificationManager checks if there's already a notification #\(printID(hashedID)) in storage")
            if receivedHashedIDs.contains(hashedID) {
                Logger.notification.info("NotificationManager will ignore notification #\(printID(hashedID)) as it is already stored")
                return
            }
            let hashedDestinationAddress = data.subdata(in: 33..<65)
            if controlByte.destinationControlValue == 2 && !(hashedDestinationAddress == Address.Broadcast.hashed || hashedDestinationAddress == self.address.hashed) {
                Logger.notification.info("NotificationManager will ignore notification #\(printID(hashedID)), as its hashedDestinationAddress (\(printID(hashedDestinationAddress))) doesn't match the hashed notificationManager address (\(printID(self.address.hashed))) or the hashed broadcast address (\(printID(Address.Broadcast.hashed)))")
                return
            }
            let hashedSourceAddress = data.subdata(in: 65..<97)
            let sentTimestampData = data.subdata(in: 97..<105)
            let messageData = data.subdata(in: 105..<data.count)
            let message: String = String(data: messageData, encoding: .utf8) ?? ""
            let notification = Notification(controlByte: controlByte, hashedID: hashedID, hashedDestinationAddress: hashedDestinationAddress, hashedSourceAddress: hashedSourceAddress, sentTimestampData: sentTimestampData, message: message)
            insert(notification)
            receivedHashedIDs.append(notification.hashedID)
            Logger.notification.info("Central successfully received notification #\(notification.description) with message: '\(notification.message)'")
        }
    }
    
    func populateReceivedArray() {
        Logger.notification.trace("NotificationManager attempts to \(#function) array")
        let hashedIDs = fetchAllHashedIDs()
        if hashedIDs == nil || hashedIDs!.isEmpty {
            Logger.notification.debug("NotificationManager has no hashedIDs to add to the receivedHashedIDs array")
        } else {
            self.receivedHashedIDs = hashedIDs!
            Logger.notification.debug("NotificationManager has successfully populated the receivedHashedIDs array with \(self.receivedHashedIDs.count) hashedIDs")
        }
    }
    
    // MARK: sending methods
    
    func sendNotifications() {
        Logger.notification.trace("NotificationManager attempts to \(#function)")
        if sendQueue.isEmpty {
            populateSendQueue()
        }
        var endedSuccessfully = true // To sendNoNotificationSignal() in case there are no (more) notifications in the sendQueue
        for notification in sendQueue {
            guard notification.destinationControlValue > 0 else {
                Logger.notification.trace("Skipping notification #\(printID(notification.hashedID)) because its destinationControlValue is 0")
                continue
            }
            Logger.notification.debug("NotificationManager attempts to sendNotification #\(notification.description) with message: '\(notification.message)'")
            var data = Data()
            data.append(notification.controlByte)
            data.append(notification.hashedID)
            data.append(notification.hashedDestinationAddress)
            data.append(notification.hashedSourceAddress)
            data.append(notification.sentTimestampData)
            assert(data.count == minNotificationLength)
            if let messageData = notification.message.data(using: .utf8) {
                data.append(messageData)
            }
            if connectionManager.send(notification: data) {
                Logger.notification.info("NotificationManager successfully sent notification data of \(data.count-minNotificationLength)+\(minNotificationLength)=\(data.count) bytes")
                try! notification.setDestinationControl(to: 0)
                endedSuccessfully = true
                continue
            } else {
                Logger.notification.warning("NotificationManager did not send notification data of \(data.count-minNotificationLength)+\(minNotificationLength)=\(data.count) bytes")
                endedSuccessfully = false
                break
                // peripheralManagerIsReady(toUpdateSubscribers) will call sendNotifications() again
            }
        }
        if endedSuccessfully {
            Logger.notification.trace("NotificationManager skipped or ended the \(#function) loop successfully and is removing all notifications from the sendQueue")
            self.sendQueue.removeAll()
            sendNoNotificationSignal()
        }
    }
    
    private func populateSendQueue() {
        Logger.notification.trace("NotificationManager attempts to \(#function)")
        let notifications = fetchAllSendable()
        if notifications == nil || notifications!.isEmpty {
            Logger.notification.debug("NotificationManager has no notifications to add to the sendQueue")
        } else {
            self.sendQueue = notifications!
            Logger.notification.debug("NotificationManager has successfully populated the sendQueue with \(self.sendQueue.count) notifications")
        }
    }
    
    private func sendNoNotificationSignal() {
        Logger.notification.trace("NotificationManager attempts to \(#function)")
        let data = Data(count: minNotificationLength)
        if connectionManager.send(notification: data) {
            Logger.notification.info("NotificationManager successfully sent \(data.count) zeros")
        } else {
            Logger.notification.warning("NotificationManager did not send \(data.count) zeros")
            // peripheralManagerIsReady(toUpdateSubscribers) will call sendNotifications() again
        }
    }
    
    // MARK: view updating methods
    
    final func updateView() {
        Logger.notification.trace("NotificationManager attempts to \(#function)")
        let countBefore = view.count
        save()
        view = fetchAll(for: self.address.hashed, includingBroadcast: true) ?? []
        Logger.notification.debug("NotificationManager added \(self.view.count - countBefore) notification(s) to the notificationView")
    }
    
    final func updateView(with notification: Notification) {
        Logger.notification.debug("NotificationManager attempts to \(#function) notification #\(printID(notification.hashedID))")
        guard notification.hashedDestinationAddress == self.address.hashed || notification.hashedDestinationAddress == Data(Address.Broadcast.hashed) else { // TODO: handle
            Logger.notification.warning("NotificationManager won't \(#function) notification #\(printID(notification.hashedID)) because its hashedDestinationAddress doesn't match the NotificationManager address or the Broadcast address")
            return
        }
        let countBefore = view.count
        save()
        view.insert(notification, at: 0)
        Logger.notification.debug("NotificationManager added \(self.view.count - countBefore) notification to the notificationView")
    }
    
    // MARK: creation methods
    
    func create(destinationAddress: Address, message: String) -> Notification {
        let controlByte = try! ControlByte(protocolValue: self.protocolValue, destinationControlValue: 1, sequenceNumberValue: 0)
        return Notification(controlByte: controlByte, sourceAddress: self.address, destinationAddress: destinationAddress, message: message)
    }
    
    // MARK: counting methods
    
    final func fetchAllSendableCount() -> Int {
        Logger.notification.debug("NotificationManager attempts to \(#function)")
        let result = try? context.fetchCount(FetchDescriptor<Notification>(predicate: sendablePredicate))
        return result ?? 0
    }
    
    // MARK: fetching methods
    
    final func fetchAll() -> [Notification]? {
        Logger.notification.trace("NotificationManager attempts to \(#function)")
        return try? context.fetch(FetchDescriptor<Notification>())
    }
    
    final func fetchAllSendable() -> [Notification]? {
        Logger.notification.debug("NotificationManager attempts to \(#function)")
        return try? context.fetch(FetchDescriptor<Notification>(predicate: sendablePredicate))
    }
    
    final func fetchAll(for hashedAddress: Data, includingBroadcast: Bool = false) -> [Notification]? {
        Logger.notification.debug("NotificationManager attempts to \(#function) for hashedAddress (\(printID(hashedAddress)))\(includingBroadcast ? " includingBroadcasts" : "")")
        let hashedBroadcastAddress = Data(Address.Broadcast.hashed)
        let predicate = #Predicate<Notification> {
            if $0.hashedDestinationAddress == hashedAddress { return true }
            else if includingBroadcast { return $0.hashedDestinationAddress == hashedBroadcastAddress }
            else { return false }
        }
        return try? context.fetch(FetchDescriptor<Notification>(predicate: predicate))
    }
    
    final func fetchAllHashedIDs() -> [Data]? {
        Logger.notification.trace("NotificationManager attempts to \(#function)")
        guard let results = fetchAll() else { return nil }
        return results.map { $0.hashedID }
    }
    
    // MARK: insertion methods
    
    final func insert(_ notification: Notification) {
        Logger.notification.debug("NotificationManager attempts to \(#function) notification #\(printID(notification.hashedID)) with message '\(notification.message)'")
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

// MARK: Spray and Wait

@Observable
class SprayAndWait: NotificationManager {

    init(connectionManagerType: ConnectionManager.Type) {
        super.init(protocolValue: 1, connectionManagerType: connectionManagerType)
    }
    
}
