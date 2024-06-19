//
//  SimpleNotificationManager.swift
//  bleep-eval
//
//  Created by Simon Núñez Aschenbrenner on 10.06.24.
//

import Foundation
import SwiftData
import OSLog

@Observable
class SimpleNotificationManager: NotificationManager {
        
    private(set) var container: ModelContainer!
    private(set) var context: ModelContext!
    
    private(set) var address: Address!
    private(set) var connectionManager: ConnectionManager!
    
    private(set) var view: [Notification] = []
    
    var isPublishing: Bool { return connectionManager.mode.isProvider }
    var isSubscribing: Bool { return connectionManager.mode.isConsumer }
    var isIdling: Bool { return connectionManager.mode.isUndefined }
    var state: String { return connectionManager.mode.description }
    
    // MARK: initializing methods
    
    required init(connectionManagerType: ConnectionManager.Type) {
        self.connectionManager = connectionManagerType.init(notificationManager: self)
        self.container = try! ModelContainer(for: Notification.self, Address.self)
        self.context = ModelContext(self.container)
        self.context.autosaveEnabled = true
        try! self.context.delete(model: Notification.self) // TODO: delete
        initAddress()
        Logger.notification.trace("SimpleNotificationManager initialized")
    }
    
    private func initAddress() {
        let fetchResult = try? context.fetch(FetchDescriptor<Address>())
        if fetchResult == nil || fetchResult!.isEmpty {
            Logger.notification.info("SimpleNotificationManager is creating a new address")
            let address = Address()
            context.insert(address)
            save()
            self.address = address
        } else {
            self.address = fetchResult![0]
            Logger.notification.trace("NotificationManager found its address in storage")
        }
        Logger.notification.debug("SimpleNotificationManager address: \(self.address!.base58Encoded) (\(printID(self.address!.hashed)))")
        assert(self.address!.rawValue == Address.decode(self.address!.base58Encoded)) // TODO: delete
    }
    
    // MARK: state changing methods
    
    func publish() {
        Logger.notification.trace("SimpleNotificationManager attempts to \(#function) notifications")
        connectionManager.setMode(to: .provider)
    }
    
    func subscribe() {
        Logger.notification.trace("SimpleNotificationManager attempts to \(#function) to notifications")
        connectionManager.setMode(to: .consumer)
    }
    
    func idle() {
        Logger.notification.debug("SimpleNotificationManager attempts to \(#function)")
        connectionManager.setMode(to: .undefined)
    }
    
    // MARK: view related methods
    
    func updateView() {
        Logger.notification.trace("SimpleNotificationManager attempts to \(#function)")
        let countBefore = view.count
        save()
        view = fetchAll(for: self.address.hashed, includingBroadcast: true) ?? []
        Logger.notification.debug("SimpleNotificationManager added \(self.view.count - countBefore) notification(s) to the notificationView")
    }
    
    func updateView(with notification: Notification) {
        Logger.notification.debug("SimpleNotificationManager attempts to \(#function) notification #\(printID(notification.hashedID))")
        let countBefore = view.count
        save()
        view.insert(notification, at: 0)
        Logger.notification.debug("SimpleNotificationManager added \(self.view.count - countBefore) notification to the notificationView")
    }
    
    // MARK: counting methods
    
    func fetchCount() -> Int {
        Logger.notification.trace("SimpleNotificationManager attempts to \(#function)")
        let result = try? context.fetchCount(FetchDescriptor<Notification>())
        return result ?? 0
    }
    
    func fetchCount(with destinationControlValues: [UInt8]) -> Int {
        Logger.notification.debug("SimpleNotificationManager attempts to \(#function) destinationControlValues \(destinationControlValues)")
        let descriptor = FetchDescriptor<Notification>(predicate: #Predicate { notification in destinationControlValues.contains(notification.destinationControlValue) })
        let result = try? context.fetchCount(descriptor)
        return result ?? 0
    }
    
    // MARK: fetching methods
    
    func fetchAll() -> [Notification]? {
        Logger.notification.trace("SimpleNotificationManager attempts to \(#function)")
        return try? context.fetch(FetchDescriptor<Notification>())
    }
    
    func fetchAll(with destinationControlValues: [UInt8]) -> [Notification]? {
        Logger.notification.debug("SimpleNotificationManager attempts to \(#function) destinationControlValues \(destinationControlValues)")
        let descriptor = FetchDescriptor<Notification>(predicate: #Predicate { notification in destinationControlValues.contains(notification.destinationControlValue) })
        return try? context.fetch(descriptor)
    }
    
    func fetchAll(for hashedAddress: Data, includingBroadcast: Bool = false) -> [Notification]? {
        Logger.notification.debug("SimpleNotificationManager attempts to \(#function) for hashedAddress '\(printID(hashedAddress))'\(includingBroadcast ? " and broadcasts" : "")")
        let hashedBroadcastAddress = Data(Address.Broadcast.hashed)
        let predicate = #Predicate<Notification> {
            if $0.hashedDestinationAddress == hashedAddress {
                return true
            } else if includingBroadcast {
                return $0.hashedDestinationAddress == hashedBroadcastAddress
            } else {
                return false
            }
        }
        let descriptor = FetchDescriptor<Notification>(predicate: predicate)
        return try? context.fetch(descriptor)
    }
    
    func fetchAllHashedIDs() -> [Data]? {
        Logger.notification.trace("SimpleNotificationManager attempts to \(#function)")
        guard let results = fetchAll() else {
            return nil
        }
        return results.map { $0.hashedID }
    }
    
    func fetch(with hashedID: Data) -> Notification? {
        Logger.notification.trace("SimpleNotificationManager attempts to \(#function) #\(printID(hashedID))")
        let fetchDescriptor = FetchDescriptor<Notification>(predicate: #Predicate { notification in notification.hashedID == hashedID })
        return try? context.fetch(fetchDescriptor)[0]
    }
    
    // MARK: insertion methods
    
    func insert(_ notification: Notification, andSave: Bool = false) {
        Logger.notification.debug("SimpleNotificationManager attempts to \(#function) notification #\(printID(notification.hashedID)) with message '\(notification.message)'")
        context.insert(notification)
        andSave ? save() : ()
    }
    
    func save() {
        do {
            try context.save()
            Logger.notification.trace("SimpleNotificationManager saved the context")
        } catch {
            Logger.notification.fault("SimpleNotificationManager failed to save the context: \(error)")
        }
    }
    
    // TODO: deletion methods
}

// MARK: Spray and Wait extension

extension NotificationManager {
    
}
