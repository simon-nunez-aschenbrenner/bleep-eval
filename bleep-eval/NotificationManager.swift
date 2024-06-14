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
    var hashedSourceAddress: Data? // TODO: set only once
    let hashedDestinationAddress: Data!
    var message: String? // TODO: encrypt, set only once
    
    init(categoryID: UInt8!, sourceAddress: Address!, destinationAddress: Address!, message: String!) {
        self.categoryID = categoryID
        let id = String(sourceAddress.rawValue).appendingFormat("%064u", UInt64.random(in: UInt64.min...UInt64.max)) // TODO: replace with UInt128 in the future?
        self.hashedID = Data(SHA256.hash(data: id.data(using: .utf8)!))
        self.hashedSourceAddress = sourceAddress.hashed
        self.hashedDestinationAddress = destinationAddress.hashed
        self.message = message
        Logger.notification.trace("Initialized Notification")
    }
    
    init(categoryID: UInt8!, hashedID: Data!, hashedDestinationAddress: Data!) {
        self.categoryID = categoryID
        self.hashedID = hashedID
        self.hashedDestinationAddress = hashedDestinationAddress
    }
}

@Observable
class NotificationManager: NSObject {
    
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
    
    // TODO: delete
    var state: String {
        if isPublishing {
            return "Peripheral / Publishing"
        } else if isSubscribing {
            return "Central / Subscribing"
        } else if isIdling {
            return "Undefined / Idling"
        } else {
            return "??????????"
        }
    }
    
    override init() {
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
            Logger.notification.info("Creating new address")
            let address = Address()
            context.insert(address)
            saveContext()
            self.address = address
        } else {
            self.address = fetchResult![0]
            Logger.notification.debug("Address found in storage")
        }
        Logger.notification.info("This notificationManager's base58Encoded address: '\(printID(self.address!.base58Encoded))' (hashed: '\(printID(self.address!.hashed))')")
        Logger.notification.debug("Address.rawValue is '\(self.address!.rawValue)'") // TODO: delete
    }
    
    func updateNotificationsDisplay() {
        saveContext()
        notificationsDisplay = fetchAllNotifications(for: self.address.data, includingBroadcast: true) ?? []
    }
    
    // MARK: state changing methods
    
    func publish() {
        Logger.notification.trace("Attempting to \(#function) notifications")
        bluetoothManager.setMode(to: .peripheral)
    }
    
    func subscribe() {
        Logger.notification.trace("Attempting to \(#function) to notifications")
        bluetoothManager.setMode(to: .central)
    }
    
    func idle() {
        Logger.notification.debug("Attempting to \(#function)")
        bluetoothManager.setMode(to: .undefined)
    }
    
    // MARK: counting methods
    
    func fetchNotificationCount() -> Int {
        Logger.notification.trace("In \(#function)")
        let result = try? context.fetchCount(FetchDescriptor<Notification>())
        return result ?? 0
    }
    
    // MARK: fetching methods
    
    func fetchAllNotifications() -> [Notification]? {
        Logger.notification.trace("In \(#function)")
        return try? context.fetch(FetchDescriptor<Notification>())
    }
    
    func fetchAllNotifications(with categoryIDs: [UInt8]) -> [Notification]? {
        Logger.notification.trace("In \(#function)")
        let fetchDescriptor = FetchDescriptor<Notification>(predicate: #Predicate { notification in categoryIDs.contains(notification.categoryID) })
        return try? context.fetch(fetchDescriptor)
    }
    
    func fetchAllNotifications(for hashedAddress: Data, includingBroadcast: Bool = false) -> [Notification]? {
        Logger.notification.trace("In \(#function)")
        let hashedBroadcastAddress = Data(Address.Broadcast.hashed)
        let predicate = #Predicate<Notification> {
            $0.hashedDestinationAddress == hashedAddress || includingBroadcast ? $0.hashedDestinationAddress == hashedBroadcastAddress : false
        }
        let descriptor = FetchDescriptor<Notification>(predicate: predicate)
        return try? context.fetch(descriptor)
    }
    
    func fetchAllNotificationHashIDs() -> [Data]? {
        Logger.notification.trace("In \(#function)")
        guard let results = fetchAllNotifications() else {
            return nil
        }
        return results.map { $0.hashedID }
    }
    
    func fetchNotification(hashedID: Data) -> Notification? {
        Logger.notification.trace("In \(#function)")
        let fetchDescriptor = FetchDescriptor<Notification>(predicate: #Predicate { notification in notification.hashedID == hashedID })
        return try? context.fetch(fetchDescriptor)[0]
    }
    
    // MARK: insertion methods
    
    func insertNotification(_ notification: Notification, andSave: Bool = false) {
        Logger.notification.debug("\(#function) #\(printID(notification.hashedID)) with message '\(notification.message ?? "")'")
        context.insert(notification)
        andSave ? saveContext() : ()
    }
    
    func saveContext() {
        do {
            try context.save()
            Logger.notification.trace("NotificationManager saved context")
        } catch {
            Logger.notification.fault("NotificationManager failed to save context: \(error)")
        }
    }
    
    // TODO: delete every notification automatically some time after receiving
}
