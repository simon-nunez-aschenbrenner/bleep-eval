//
//  NotificationManager.swift
//  bleep-eval
//
//  Created by Simon Núñez Aschenbrenner on 10.06.24.
//

import Foundation
import CryptoKit
import SwiftData
import OSLog

@Model
class Notification {
    
    var categoryID: UInt8!
    @Attribute(.unique) let hashedID: Data!
    let hashedSourceAddress: Data!
    let hashedDestinationAddress: Data!
    let message: String!
    
    init(categoryID: UInt8!, sourceAddress: Address!, destinationAddress: Address!, message: String!) {
        self.categoryID = categoryID
        let id = String(sourceAddress.rawValue).appendingFormat("%064u", UInt64.random(in: UInt64.min...UInt64.max)) // TODO: replace with UInt128 in the future
        self.hashedID = Data(SHA256.hash(data: id.data(using: .utf8)!))
        self.hashedSourceAddress = sourceAddress.hashed
        self.hashedDestinationAddress = destinationAddress.hashed
        self.message = message
        // Logger.notification.trace("Initialized Notification")
        Logger.notification.debug("Initialized Notification #\(printID(self.hashedID)) with destinationAddress rawValue '\(destinationAddress.rawValue)', hashedDestinationAddress '\(printID(self.hashedDestinationAddress))' and message '\(self.message)'") // TODO: delete
    }
    
    init(categoryID: UInt8!, hashedID: Data!, hashedDestinationAddress: Data!, hashedSourceAddress: Data!, message: String!) {
        self.categoryID = categoryID
        self.hashedID = hashedID
        self.hashedSourceAddress = hashedSourceAddress
        self.hashedDestinationAddress = hashedDestinationAddress
        self.message = message
        // Logger.notification.trace("Initialized Notification")
        Logger.notification.debug("Initialized Notification #\(printID(self.hashedID)) with hashedDestinationAddress '\(printID(self.hashedDestinationAddress))' and message '\(self.message)'") // TODO: delete
    }
}

@Observable
class NotificationManager: NSObject {
    
    let version: UInt8! // equivalent to maximum supported categoryID
    
    private var container: ModelContainer!
    private var context: ModelContext!
    
    private(set) var address: Address!
    private var bluetoothManager: BluetoothManager!
    
    var notificationsDisplay: [Notification] = []
    
    var isPublishing: Bool {
        return bluetoothManager.modeIsPeripheral
    }
    var isSubscribing: Bool {
        return bluetoothManager.modeIsCentral
    }
    var isIdling: Bool {
        return bluetoothManager.modeIsUndefined
    }
    var state: String {
        return bluetoothManager.mode.description
    }
    
    // MARK: initializing methods
    
    init(version: UInt8) {
        self.version = version
        super.init()
        self.bluetoothManager = BluetoothManager(notificationManager: self)
        self.container = try! ModelContainer(for: Notification.self, Address.self)
        self.context = ModelContext(self.container)
        self.context.autosaveEnabled = true
        try! self.context.delete(model: Notification.self) // TODO: delete
        initAddress()
        Logger.notification.trace("NotificationManager initialized")
    }
    
    private func initAddress() {
        let fetchResult = try? context.fetch(FetchDescriptor<Address>())
        if fetchResult == nil || fetchResult!.isEmpty {
            Logger.notification.info("NotificationManager is creating a new address")
            let address = Address()
            context.insert(address)
            saveContext()
            self.address = address
        } else {
            self.address = fetchResult![0]
            Logger.notification.trace("NotificationManager found its address in storage")
        }
        Logger.notification.debug("NotificationManager full rawValue '\(self.address!.rawValue)', full base58Encoded '\(self.address!.base58Encoded)' and shortened hashed '\(printID(self.address!.hashed))' address")
        assert(self.address!.rawValue == Address.decode(self.address!.base58Encoded)) // TODO: delete
    }
    
    // MARK: state changing methods
    
    func publish() {
        Logger.notification.trace("NotificationManager attempts to \(#function) notifications")
        bluetoothManager.setMode(to: .peripheral)
    }
    
    func subscribe() {
        Logger.notification.trace("NotificationManager attempts to \(#function) to notifications")
        bluetoothManager.setMode(to: .central)
    }
    
    func idle() {
        Logger.notification.debug("NotificationManager attempts to \(#function)")
        bluetoothManager.setMode(to: .undefined)
    }
    
    // MARK: view related methods
    
    func updateNotificationsDisplay() { // TODO: change name
        Logger.notification.trace("NotificationManager attempts to \(#function)")
        let countBefore = notificationsDisplay.count
        saveContext()
        notificationsDisplay = fetchAllNotifications(for: self.address.hashed, includingBroadcast: true) ?? []
        Logger.notification.debug("NotificationManager added \(self.notificationsDisplay.count - countBefore) notifications to the notificationsDisplay")
        Logger.notification.trace("NotificationManager notificationsDisplay: \(self.notificationsDisplay)")
    }
    
    // MARK: counting methods
    
    func fetchNotificationCount() -> Int {
        Logger.notification.trace("NotificationManager attempts to \(#function)")
        let result = try? context.fetchCount(FetchDescriptor<Notification>())
        return result ?? 0
    }
    
    func fetchNotificationCount(withCategoryIDs categoryIDs: [UInt8]) -> Int {
        Logger.notification.trace("NotificationManager attempts to \(#function)")
        let fetchDescriptor = FetchDescriptor<Notification>(predicate: #Predicate { notification in categoryIDs.contains(notification.categoryID) })
        let result = try? context.fetchCount(fetchDescriptor)
        return result ?? 0
    }
    
    // MARK: fetching methods
    
    func fetchAllNotifications() -> [Notification]? {
        Logger.notification.trace("NotificationManager attempts to \(#function)")
        return try? context.fetch(FetchDescriptor<Notification>())
    }
    
    func fetchAllNotifications(withCategoryIDs categoryIDs: [UInt8]) -> [Notification]? {
        Logger.notification.trace("NotificationManager attempts to \(#function)")
        let fetchDescriptor = FetchDescriptor<Notification>(predicate: #Predicate { notification in categoryIDs.contains(notification.categoryID) })
        return try? context.fetch(fetchDescriptor)
    }
    
    func fetchAllNotifications(for hashedAddress: Data, includingBroadcast: Bool = false) -> [Notification]? {
        Logger.notification.debug("NotificationManager attempts to \(#function) for hashedAddress '\(printID(hashedAddress))'\(includingBroadcast ? " and broadcasts" : "")")
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
    
    func fetchAllNotificationHashIDs() -> [Data]? {
        Logger.notification.trace("NotificationManager attempts to \(#function)")
        guard let results = fetchAllNotifications() else {
            return nil
        }
        return results.map { $0.hashedID }
    }
    
    func fetchNotification(hashedID: Data) -> Notification? {
        Logger.notification.trace("NotificationManager attempts to \(#function)")
        let fetchDescriptor = FetchDescriptor<Notification>(predicate: #Predicate { notification in notification.hashedID == hashedID })
        return try? context.fetch(fetchDescriptor)[0]
    }
    
    // MARK: insertion methods
    
    func insertNotification(_ notification: Notification, andSave: Bool = false) {
        Logger.notification.debug("NotificationManager attempts to \(#function) #\(printID(notification.hashedID)) with message '\(notification.message ?? "")'")
        context.insert(notification)
        andSave ? saveContext() : ()
    }
    
    func saveContext() {
        do {
            try context.save()
            Logger.notification.trace("NotificationManager saved the context")
        } catch {
            Logger.notification.fault("NotificationManager failed to save the context: \(error)")
        }
    }
    
    // TODO: delete every notification automatically some time after receiving
    // TODO: regenerate address
}
