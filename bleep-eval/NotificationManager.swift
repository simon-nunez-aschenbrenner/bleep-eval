//
//  NotificationManager.swift
//  bleep-eval
//
//  Created by Simon Núñez Aschenbrenner on 10.06.24.
//

import Foundation
import SwiftData
import OSLog

@Observable
class NotificationManager: NSObject {
    
    let version: Int!
    var maxSupportedControlByteValue: Int { return (self.version * 64) - 1 }
    
    private var container: ModelContainer!
    private var context: ModelContext!
    
    private(set) var address: Address!
    private var bluetoothManager: BluetoothManager!
    
    var notificationView: [Notification] = []
    
    var isPublishing: Bool { return bluetoothManager.modeIsPeripheral }
    var isSubscribing: Bool { return bluetoothManager.modeIsCentral }
    var isIdling: Bool { return bluetoothManager.modeIsUndefined }
    var state: String { return bluetoothManager.mode.description }
    
    // MARK: initializing methods
    
    init(version: Int) {
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
            save()
            self.address = address
        } else {
            self.address = fetchResult![0]
            Logger.notification.trace("NotificationManager found its address in storage")
        }
        Logger.notification.debug("NotificationManager address: \(self.address!.base58Encoded) (\(printID(self.address!.hashed)))")
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
    
    func updateView() {
        Logger.notification.trace("NotificationManager attempts to \(#function)")
        let countBefore = notificationView.count
        save()
        notificationView = fetchAll(for: self.address.hashed, includingBroadcast: true) ?? []
        Logger.notification.debug("NotificationManager added \(self.notificationView.count - countBefore) notification(s) to the notificationView")
    }
    
    func updateView(with notification: Notification) {
        Logger.notification.debug("NotificationManager attempts to \(#function) #\(printID(notification.hashedID))")
        let countBefore = notificationView.count
        save()
        notificationView.insert(notification, at: 0)
        Logger.notification.debug("NotificationManager added \(self.notificationView.count - countBefore) notification to the notificationView")
    }
    
    // MARK: counting methods
    
    func fetchCount() -> Int {
        Logger.notification.trace("NotificationManager attempts to \(#function)")
        let result = try? context.fetchCount(FetchDescriptor<Notification>())
        return result ?? 0
    }
    
    func fetchCount(with destinationControlValues: [UInt8]) -> Int {
        Logger.notification.debug("NotificationManager attempts to \(#function) \(destinationControlValues)")
        let descriptor = FetchDescriptor<Notification>(predicate: #Predicate { notification in destinationControlValues.contains(notification.destinationControlValue) })
        let result = try? context.fetchCount(descriptor)
        return result ?? 0
    }
    
    // MARK: fetching methods
    
    func fetchAll() -> [Notification]? {
        Logger.notification.trace("NotificationManager attempts to \(#function)")
        return try? context.fetch(FetchDescriptor<Notification>())
    }
    
    func fetchAll(with destinationControlValues: [UInt8]) -> [Notification]? {
        Logger.notification.debug("NotificationManager attempts to \(#function) \(destinationControlValues)")
        let descriptor = FetchDescriptor<Notification>(predicate: #Predicate { notification in destinationControlValues.contains(notification.destinationControlValue) })
        return try? context.fetch(descriptor)
    }
    
    func fetchAll(for hashedAddress: Data, includingBroadcast: Bool = false) -> [Notification]? {
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
    
    func fetchAllHashedIDs() -> [Data]? {
        Logger.notification.trace("NotificationManager attempts to \(#function)")
        guard let results = fetchAll() else {
            return nil
        }
        return results.map { $0.hashedID }
    }
    
    func fetch(with hashedID: Data) -> Notification? {
        Logger.notification.trace("NotificationManager attempts to \(#function)")
        let fetchDescriptor = FetchDescriptor<Notification>(predicate: #Predicate { notification in notification.hashedID == hashedID })
        return try? context.fetch(fetchDescriptor)[0]
    }
    
    // MARK: insertion methods
    
    func insert(_ notification: Notification, andSave: Bool = false) {
        Logger.notification.debug("NotificationManager attempts to \(#function) notification #\(printID(notification.hashedID)) with message '\(notification.message)'")
        context.insert(notification)
        andSave ? save() : ()
    }
    
    func save() {
        do {
            try context.save()
            Logger.notification.trace("NotificationManager saved the context")
        } catch {
            Logger.notification.fault("NotificationManager failed to save the context: \(error)")
        }
    }
    
    // TODO: deletion methods
}

// MARK: Spray and Wait extension

extension NotificationManager {
    
}
