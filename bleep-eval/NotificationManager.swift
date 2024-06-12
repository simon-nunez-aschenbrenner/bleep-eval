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
        let id = String(sourceAddress.rawValue).appendingFormat("%064u", UInt64.random(in: UInt64.min...UInt64.max))
        Logger.notification.debug("Notification ID before hashing: '\(id)'") // TODO: delete
        self.hashedID = Data(SHA256.hash(data: id.data(using: .utf8)!))
        self.hashedSourceAddress = sourceAddress.hashed
        self.hashedDestinationAddress = destinationAddress.hashed
        self.message = message
    }
    
    init(categoryID: UInt8!, hashedID: Data!, hashedDestinationAddress: Data!) {
        self.categoryID = categoryID
        self.hashedID = hashedID
        self.hashedDestinationAddress = hashedDestinationAddress
    }
}

// TODO: change !
class NotificationManager {

    static let shared = NotificationManager()
    
    var container: ModelContainer? = nil
    var context: ModelContext? = nil
    
    init() {
        do {
            self.container = try ModelContainer(for: Notification.self)
            self.context = ModelContext(self.container!)
            try self.context!.delete(model: Notification.self) // TODO: delete
        } catch {
            Logger.notification.fault("Failed to initialise modelContainer: \(error)")
        }
    }
    
    func fetchAllNotifications() -> [Notification]? { // TODO: needed?
        let fetchDescriptor = FetchDescriptor<Notification>()
        do {
            return try context!.fetch(fetchDescriptor)
        } catch {
            Logger.notification.error("Failed to fetch all notifications: \(error)")
            return nil
        }
    }
    
//    func fetchAllNotifications(with categoryID: UInt8) -> [Notification]? { // TODO: multiple categoryIDs?
//        let fetchDescriptor = FetchDescriptor<Notification>(predicate: #Predicate { notification in
//            notification.categoryID == categoryID
//        })
//        do {
//            return try context.fetch(fetchDescriptor)
//        } catch {
//            Logger.notification.error("Failed to fetch all notifications with category \(categoryID): \(error)")
//            return nil
//        }
//    }
    
    func fetchAllNotifications(for hashedAddress: Data, includingBroadcast: Bool = false) -> [Notification]? {
        let hashedBroadcastAddress = Data(Address.Broadcast.hashed)
        let predicate = #Predicate<Notification> {
            $0.hashedDestinationAddress == hashedAddress || includingBroadcast ? $0.hashedDestinationAddress == hashedBroadcastAddress : false
        }
        let descriptor = FetchDescriptor<Notification>(predicate: predicate)
        do {
            return try context!.fetch(descriptor)
        } catch {
            Logger.notification.error("Failed to fetch all my notifications: \(error)")
            return nil
        }
    }
    
    func fetchAllNotificationHashIDs() -> [Data]? {
        let fetchDescriptor = FetchDescriptor<Notification>()
        do {
            let results = try context!.fetch(fetchDescriptor)
            return results.map { $0.hashedID }
        } catch {
            Logger.notification.error("Failed to fetch all notifications: \(error)")
            return nil
        }
    }
    
//    func fetchNotification(hashedID: Data) -> Notification? {
//        let fetchDescriptor = FetchDescriptor<Notification>(predicate: #Predicate { notification in
//            notification.hashedID == hashedID
//        })
//        do {
//            return try context.fetch(fetchDescriptor)[0]
//        } catch {
//            Logger.notification.error("Failed to fetch notification '\(hashedID)' (hashed): \(error)")
//            return nil
//        }
//    }
    
    // TODO: delete every notification automatically some time after receiving
}
