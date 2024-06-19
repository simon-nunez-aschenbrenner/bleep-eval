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
    
    final private(set) var address: Address!
    final internal var connectionManager: ConnectionManager!
    
    final private(set) var view: [Notification] = []
        
    final var isPublishing: Bool { return connectionManager.mode.isProvider }
    final var isSubscribing: Bool { return connectionManager.mode.isConsumer }
    final var isIdling: Bool { return connectionManager.mode.isUndefined }
    final var state: String { return connectionManager.mode.description }
    
    final let sendablePredicate = #Predicate<Notification> { return $0.destinationControlValue != 0 }
    
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
        connectionManager.setMode(to: .consumer)
    }
    
    func idle() {
        Logger.notification.debug("NotificationManager attempts to \(#function)")
        connectionManager.setMode(to: .undefined)
    }
    
    // MARK: view related methods
    
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
        let result = try? context.fetchCount(FetchDescriptor<Notification>(predicate: self.sendablePredicate))
        return result ?? 0
    }
    
    // MARK: fetching methods
    
    final func fetchAll() -> [Notification]? {
        Logger.notification.trace("NotificationManager attempts to \(#function)")
        return try? context.fetch(FetchDescriptor<Notification>())
    }
    
    final func fetchAllSendable() -> [Notification]? {
        Logger.notification.debug("NotificationManager attempts to \(#function)")
        return try? context.fetch(FetchDescriptor<Notification>(predicate: self.sendablePredicate))
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
    
    final func insert(_ notification: Notification, andSave: Bool = false) {
        Logger.notification.debug("NotificationManager attempts to \(#function) notification #\(printID(notification.hashedID)) with message '\(notification.message)'")
        context.insert(notification)
        andSave ? save() : ()
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

    override func publish() {
        Logger.notification.trace("SimpleNotificationManager attempts to \(#function) notifications")
        connectionManager.setMode(to: .provider)
    }
    
    override func subscribe() {
        Logger.notification.trace("SimpleNotificationManager attempts to \(#function) to notifications")
        connectionManager.setMode(to: .consumer)
    }
    
    override func idle() {
        Logger.notification.debug("SimpleNotificationManager attempts to \(#function)")
        connectionManager.setMode(to: .undefined)
    }

    override func create(destinationAddress: Address, message: String) -> Notification {
        let controlByte = try! ControlByte(protocolValue: self.protocolValue, destinationControlValue: 1, sequenceNumberValue: 0)
        return Notification(controlByte: controlByte, sourceAddress: self.address, destinationAddress: destinationAddress, message: message)
    }
    
}
