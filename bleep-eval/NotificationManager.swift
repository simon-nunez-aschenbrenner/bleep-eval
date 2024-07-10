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

enum NotificationManagerType: UInt8, CaseIterable, Identifiable, CustomStringConvertible {
    case direct = 0
    case epidemic = 1
    case replicating = 2
    case forwarding = 3
    var id: Self { self }
    var description: String {
        switch self {
        case .direct: return "Direct"
        case .epidemic: return "Epidemic"
        case .replicating: return "Replicating"
        case .forwarding: return "Forwarding"
        }
    }
}

protocol EvaluableNotificationManager: NotificationManager {
    var type: NotificationManagerType! { get set }
    var lastRSSIValue: Int8? { get set }
    var rssiThreshold: Int8 { get set }
    var notificationTimeToLive: TimeInterval { get set }
    var initialRediscoveryInterval: TimeInterval { get set }
    var countHops: Bool { get }
    var storedHashedIDsCount: Int { get }
    var simulator: Simulator! { get }
    func setInitialNumberOfCopies(to value: UInt8) throws
    func reset()
}

protocol NotificationManager: NotificationProvider, NotificationConsumer {
    var address: Address! { get }
    var contacts: [Address] { get }
    var inbox: [Notification] { get }
    var maxMessageLength: Int! { get }
    func send(_ message: String, to destinationAddress: Address)
}

protocol NotificationProvider: AnyObject {
    var blocked: Bool { get set }
    func transmit()
    func receiveResponse(_ data: Data, from id: String) -> Bool
}

protocol NotificationConsumer: AnyObject {
    var blocked: Bool { get set }
    func receiveNotification(_ data: Data, from id: String)
}

// MARK: BleepManager

@Observable
class BleepManager: EvaluableNotificationManager {
    
    private struct Default {
        static let rssiThreshold: Int8 = -128
        static let notificationTimeToLive: TimeInterval = 300
        static let initialNumberOfCopies: UInt8 = 16
        static let initialRediscoveryInterval: TimeInterval = 10
    }
    
    let minNotificationLength: Int = 105
    let responseLength: Int = 33
    let countHops: Bool = Utils.countHops
    
    var type: NotificationManagerType! {
        didSet { Logger.notification.info("NotificationManager type set to '\(self.type.description)'") }
    }
    var blocked: Bool = false {
        didSet { Logger.notification.debug("NotificationManager \(self.blocked ? "blocked" : "is not blocked")") }
    }
    var lastRSSIValue: Int8?
    var rssiThreshold: Int8 = Default.rssiThreshold {
        didSet { Logger.notification.debug("NotificationManager rssiThreshold set to \(self.rssiThreshold) dBM") }
    }
    var notificationTimeToLive: TimeInterval = Default.notificationTimeToLive {
        didSet { Logger.notification.debug("NotificationManager notificationTimeToLive set to \(String(format: "%.0f", self.notificationTimeToLive)) seconds") }
    }
    var initialRediscoveryInterval: TimeInterval = Default.initialRediscoveryInterval {
        didSet { Logger.notification.debug("NotificationManager initialRediscoveryInterval set to \(String(format: "%.0f", self.initialRediscoveryInterval)) seconds") }
    }
    var storedHashedIDsCount: Int { return storedHashedIDs.count }

    private(set) var simulator: Simulator!
    private(set) var address: Address!
    private(set) var contacts: [Address] = []
    private(set) var inbox: [Notification] = []
    private(set) var maxMessageLength: Int!
    
    private var container: ModelContainer!
    private var context: ModelContext!
    private var connectionManager: ConnectionManager!
    private var storedHashedIDs: Set<Data> = []
    private var transmitQueue: [Notification: Bool] = [:]
    private var initialNumberOfCopies: UInt8 = Default.initialNumberOfCopies {
        didSet { Logger.notification.debug("NotificationManager initialNumberOfCopies set to \(self.initialNumberOfCopies)") }
    }
    private var rediscoveryInterval: TimeInterval = Default.initialRediscoveryInterval {
        didSet { Logger.notification.debug("NotificationManager rediscoveryInterval set to \(String(format: "%.0f", self.rediscoveryInterval)) seconds") }
    }
    private var hasResetRediscoveryIntervalSinceLastHello: Bool = false {
        didSet { Logger.notification.debug("NotificationManager \(self.hasResetRediscoveryIntervalSinceLastHello ? "hasResetRediscoveryIntervalSinceLastHello" : "has not resetRediscoveryIntervalSinceLastHello")") }
    }
    private var isRediscoveryIntervalResetDelayed: Bool = false {
        didSet { Logger.notification.debug("NotificationManager \(self.isRediscoveryIntervalResetDelayed ? "rediscoveryIntervalReset is delayed" : "rediscoveryIntervalReset is not delayed")") }
    }
    private var hasTransmittedHello: Bool = false {
        didSet { Logger.notification.debug("NotificationManager \(self.hasTransmittedHello ? "hasTransmittedHello" : "has not transmittedHello")") }
    }
    private var hasTransmittedUtilityProbes: Bool = false {
        didSet { Logger.notification.debug("NotificationManager \(self.hasTransmittedUtilityProbes ? "hasTransmittedUtilityProbes" : "has not transmittedUtilityProbes")") }
    }
    
    // MARK: initialize
        
    init(type: NotificationManagerType, connectionManagerType: ConnectionManager.Type) {
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
        self.init(type: .replicating, connectionManagerType: BluetoothManager.self)
    }

    func reset() {
        Logger.notification.trace("NotificationManager attempts to \(#function)")
        resetContext(notifications: true)
        transmitQueue.removeAll()
        storedHashedIDs.removeAll()
        inbox.removeAll()
        rssiThreshold = Default.rssiThreshold
        notificationTimeToLive = Default.notificationTimeToLive
        initialNumberOfCopies = Default.initialNumberOfCopies
        initialRediscoveryInterval = Default.initialRediscoveryInterval
        rediscoveryInterval = Default.initialRediscoveryInterval
        hasResetRediscoveryIntervalSinceLastHello = false
        isRediscoveryIntervalResetDelayed = false
        hasTransmittedHello = false
        hasTransmittedUtilityProbes = false
        connectionManager.reset()
        blocked = false
        Logger.notification.info("NotificationManager is reset to defaults")
    }
    
    private func resetContext(notifications: Bool = false, address: Bool = false) {
        Logger.notification.debug("NotificationManager attempts to \(#function): notifications=\(notifications), address=\(address)")
        if notifications { try! context.delete(model: Notification.self) }
        if address { try! context.delete(model: Address.self) }
    }
    
    private func initAddress() {
        Logger.notification.trace("NotificationManager attempts to \(#function)")
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
}

// MARK: NotificationProvider

extension BleepManager: NotificationProvider {
    
    // MARK: send
    
    func send(_ message: String, to destinationAddress: Address) {
        Logger.notification.debug("NotificationManager attempts to \(#function) message '\(message)' to \(destinationAddress.description)")
        var controlByte: ControlByte!
        switch type! {
        case .direct:
            controlByte = try! ControlByte(protocolValue: type.rawValue, destinationControlValue: 2, sequenceNumberValue: 0)
        case .epidemic:
            controlByte = try! ControlByte(protocolValue: type.rawValue, destinationControlValue: 1, sequenceNumberValue: 0)
        case .replicating:
            controlByte = try! ControlByte(protocolValue: type.rawValue, destinationControlValue: 1, sequenceNumberValue: initialNumberOfCopies-1)
        case .forwarding:
            controlByte = try! ControlByte(protocolValue: type.rawValue, destinationControlValue: 3, sequenceNumberValue: 0)
        }
        let notification = Notification(controlByte: controlByte, sourceAddress: address, destinationAddress: destinationAddress, message: message)
        if simulator.evaluationLogger == nil { Logger.notification.warning("NotificationManager did not log for evaluation because the evaluationLogger property of the simulator is nil") }
        else { simulator.evaluationLogger!.log(notification, at: address) }
        insert(notification)
        if !blocked { connectionManager.advertise() }
    }
    
    // MARK: transmit
    
    // Get's called after a consumer subscribed to this provider and each time a transmission fails
    func transmit() {
        Logger.notification.trace("NotificationManager may attempt to \(#function)")
        if transmitQueue.isEmpty { populateTransmitQueue() } // Prepare a current transmitQueue only at the first call, meaning for each new subscription, not every time a transmission fails
        Logger.notification.debug("NotificationManager attempts to \(#function) with \(self.transmitQueue.values.filter { !$0 }.count)/\(self.transmitQueue.count) notifications in the transmitQueue")
        if type == .forwarding && !hasTransmittedUtilityProbes {
            if !hasTransmittedHello { transmitHello() }
            transmitUtilityProbes()
            // TODO: utilityCollectionTimeout
        }
        transmitNotifications()
        transmitGoodbye()
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
    
    private func transmitHello() {
        Logger.notification.trace("NotificationManager attempts to \(#function)")
        let controlByte = try! ControlByte(protocolValue: type.rawValue, destinationControlValue: 1, sequenceNumberValue: hasResetRediscoveryIntervalSinceLastHello ? 1 : 0)
        let hello = Notification(controlByte: controlByte, sourceAddress: address, destinationAddress: address, message: "HELLO")
        if transmitSimple(hello) {
            hasTransmittedHello = true
            hasResetRediscoveryIntervalSinceLastHello = false
            Logger.notification.info("NotificationManager transmitted HELLO")
        }
        try! hello.controlByte.setDestinationControl(to: 0)
    }
    
    private func transmitGoodbye() {
        Logger.notification.trace("NotificationManager attempts to \(#function)")
        let controlByte = try! ControlByte(protocolValue: type.rawValue, destinationControlValue: 0, sequenceNumberValue: 0)
        let goodbye = Notification(controlByte: controlByte, sourceAddress: address, destinationAddress: address, message: "GOODBYE")
        guard transmitSimple(goodbye) else { return }
        Logger.notification.info("NotificationManager transmitted GOODBYE")
        hasTransmittedHello = false
    }
    
    private func transmitUtilityProbes() {
        Logger.notification.trace("NotificationManager attempts to \(#function)")
        for element in transmitQueue {
            let notification = element.key
            guard !element.value else {
                Logger.notification.trace("NotificationManager skips transmitting notification #\(Utils.printID(notification.hashedID)) as utility probe because it was already transmitted")
                continue
            }
            guard notification.controlByte.destinationControlValue == 3 else {
                Logger.notification.trace("NotificationManager skips transmitting notification #\(Utils.printID(notification.hashedID)) because it is not marked as utility probe")
                continue
            }
            guard notification.lastRediscoveryTimestamp == nil || notification.lastRediscoveryTimestamp! < Date(timeIntervalSinceNow: -rediscoveryInterval) else {
                Logger.notification.debug("NotificationManager skips transmitting notification #\(Utils.printID(notification.hashedID)) as utility probe because its rediscoveryInterval has not yet elapsed")
                continue
            }
            Logger.notification.trace("NotificationManager attempts to transmit notification #\(Utils.printID(notification.hashedID)) as utility probe")
            try! notification.controlByte.setSequenceNumber(to: computeUtility(for: notification.hashedDestinationAddress))
            guard transmitSimple(notification) else { return }
            transmitQueue[notification] = true
        }
        for notification in transmitQueue.keys {
            transmitQueue[notification] = false
        }
        hasTransmittedUtilityProbes = true
        Logger.notification.trace("NotificationManager skipped or finished the \(#function) loop and set all notifications in the transmitQueue to false")
    }
    
    private func transmitNotifications() {
        Logger.notification.trace("NotificationManager attempts to \(#function)")
        for element in transmitQueue {
            let notification = element.key
            guard !element.value else {
                Logger.notification.trace("NotificationManager skips transmitting notification #\(Utils.printID(notification.hashedID)) because it was already transmitted")
                continue
            }
            guard notification.controlByte.destinationControlValue < 3 else {
                Logger.notification.trace("NotificationManager skips transmitting notification #\(Utils.printID(notification.hashedID)) because it is marked as utility probe")
                continue
            }
            Logger.notification.trace("NotificationManager attempts to transmit notification #\(Utils.printID(notification.hashedID))")
            switch type! {
            case .direct, .epidemic:
                guard transmitSimple(notification) else { return }
            case .replicating:
                guard transmitReplicating(notification) else { return }
            case .forwarding:
                guard transmitForwarding(notification) else { return }
            }
            transmitQueue[notification] = true
        }
        transmitQueue.removeAll()
        hasTransmittedUtilityProbes = false
        Logger.notification.trace("NotificationManager skipped or finished the \(#function) loop and removed all notifications from the transmitQueue")
    }
    
    // Handles HELLOs, GOODBYEs, direct and epidemic notifications, as well as utility probes
    private func transmitSimple(_ notification: Notification) -> Bool {
        Logger.notification.debug("NotificationManager attempts to \(#function) \(notification.description) with message: '\(notification.message)'")
        let data = encodeNotification(notification)
        if connectionManager.publish(data) {
            Logger.notification.info("NotificationManager transmitted notification data of \(data.count-self.minNotificationLength)+\(self.minNotificationLength)=\(data.count) bytes")
            return true
        } else {
            Logger.notification.warning("NotificationManager did not transmit notification data of \(data.count-self.minNotificationLength)+\(self.minNotificationLength)=\(data.count) bytes")
            return false
        }
    }
    
    // MARK: transmit replicating
    
    private func transmitReplicating(_ notification: Notification) -> Bool {
        Logger.notification.debug("NotificationManager attempts to \(#function) notification \(notification.description)")
        var newControlByte = notification.controlByte
        do { try newControlByte.setSequenceNumber(to: notification.controlByte.sequenceNumberValue / 2) }
        catch BleepError.invalidControlByteValue { try! newControlByte.setDestinationControl(to: 2) }
        catch { Logger.notification.error("NotificationManager encountered an unexpected error while trying to modify the controlByte") } // TODO: throw
        Logger.notification.debug("NotificationManager will \(#function) notification #\(Utils.printID(notification.hashedID)) with a newControlByte: \(newControlByte.description)")
        let data = encodeNotification(notification, with: newControlByte)
        if connectionManager.publish(data) {
            Logger.notification.info("NotificationManager transmitted notification data of \(data.count-self.minNotificationLength)+\(self.minNotificationLength)=\(data.count) bytes")
            return true
        } else {
            Logger.notification.warning("NotificationManager did not transmit notification data of \(data.count-self.minNotificationLength)+\(self.minNotificationLength)=\(data.count) bytes")
            return false
        }
    }
    
    // MARK: transmit forwarding
    
    private func transmitForwarding(_ notification: Notification) -> Bool {
        Logger.notification.debug("NotificationManager attempts to \(#function) notification \(notification.description)")
        notification.collectedUtilites[computeUtility(for: notification.hashedDestinationAddress)] = nil
        Logger.notification.debug("NotificationManager attempts to determine the utilityThreshold for notification #\(Utils.printID(notification.hashedID)) based on the following collectedUtilites: \(notification.collectedUtilites)")
        let utilityThreshold = notification.collectedUtilites.sorted(by: { $0.key > $1.key } )[0]
        guard utilityThreshold.value != nil else {
            try! notification.controlByte.setDestinationControl(to: 3)
            return true
        }
        try! notification.controlByte.setDestinationControl(to: 2)
        try! notification.controlByte.setSequenceNumber(to: utilityThreshold.key)
        let data = encodeNotification(notification)
        if connectionManager.publish(data, to: utilityThreshold.value!) {
            Logger.notification.info("NotificationManager transmitted notification data of \(data.count-self.minNotificationLength)+\(self.minNotificationLength)=\(data.count) bytes to '\(Utils.printID(utilityThreshold.value!))'")
            return true
        } else {
            Logger.notification.warning("NotificationManager did not transmit notification data of \(data.count-self.minNotificationLength)+\(self.minNotificationLength)=\(data.count) bytes to '\(Utils.printID(utilityThreshold.value!))'")
            if notification.hasBeenRetriedToTransmitDirectly {
                Logger.notification.warning("NotificationManager failed the second time to transmit notification #\(Utils.printID(notification.hashedID)) directly and will reset it, so it can be sent as autility probe again")
                notification.collectedUtilites.removeAll()
                notification.hasBeenRespondedTo = false
                notification.hasBeenRetriedToTransmitDirectly = false
                try! notification.controlByte.setDestinationControl(to: 3)
                return true
            }
            notification.hasBeenRetriedToTransmitDirectly = true
            return false
        }
    }
    
    private func encodeNotification(_ notification: Notification, with newControlByte: ControlByte? = nil) -> Data {
        var data = Data()
        data.append(newControlByte?.value ?? notification.controlByte.value)
        data.append(notification.hashedID)
        data.append(notification.hashedDestinationAddress)
        data.append(notification.hashedSourceAddress)
        data.append(notification.sentTimestampData)
        assert(data.count == minNotificationLength)
        if let messageData = notification.message.data(using: .utf8) { data.append(messageData) }
        return data
    }
    
    // MARK: receive response
    
    func receiveResponse(_ data: Data, from id: String) -> Bool {
        Logger.notification.debug("NotificationManager attempts to \(#function) of \(data.count) bytes")
        guard data.count == responseLength else {
            Logger.notification.error("NotificationManager will ignore the response data as it's not \(self.responseLength) bytes long")
            return false
        }
        let response = Response(controlByte: ControlByte(UInt8(data[0])), hashedID: data.subdata(in: 1..<data.count))
        if simulator.evaluationLogger == nil { Logger.notification.warning("NotificationManager did not log for evaluation because the evaluationLogger property of the simulator is nil") }
        else { simulator.evaluationLogger!.log(response, at: address) }
        
        guard type.rawValue > 1 else {
            Logger.notification.error("NotificationManager does not support \(#function)")
            return false
        }
        Logger.notification.debug("NotificationManager attempts to \(#function) \(response.description)")
        
        guard response.controlByte.destinationControlValue > 0 else {
            Logger.notification.error("NotificationManager does not support \(#function) with destinationControlValue 0")
            return false
        }
        guard let notification = fetch(with: data) else {
            Logger.notification.error("NotificationManager did not find a matching notification in storage")
            return false
        }
        guard notification.controlByte.destinationControlValue > 0 else {
            Logger.notification.error("NotificationManager will ignore the response because it matches a notification with destinationControlValue 0")
            return false
        }
        guard response.controlByte.destinationControlValue != 2 else { // Accepted by destination
            Logger.notification.info("NotificationManager delivered notification #\(Utils.printID(notification.hashedID)) to its destination")
            if type == .replicating { try? notification.controlByte.setSequenceNumber(to: notification.controlByte.sequenceNumberValue / 2) }
            try! notification.controlByte.setDestinationControl(to: 0)
            notification.hasBeenRespondedTo = true
            return true
        }
        if type == .replicating {
            guard response.controlByte.destinationControlValue != 3 else {
                Logger.notification.error("NotificationManager does not support \(#function) with destinationControlValue 3")
                return false
            } // controlByte.destinationControlValue == 1
            guard !notification.hasBeenRespondedTo else {
                Logger.notification.warning("NotificationManager will ignore the response because it matches a notification that already hasBeenRespondedTo")
                return true
            }
            do { try notification.controlByte.setSequenceNumber(to: notification.controlByte.sequenceNumberValue / 2) }
            catch BleepError.invalidControlByteValue { try! notification.controlByte.setDestinationControl(to: 2) }
            catch { Logger.notification.error("NotificationManager encountered an unexpected error while trying to modify the controlByte") } // TODO: throw
            notification.hasBeenRespondedTo = true
            return true
            
        } else { // type == .forwarding
            guard response.controlByte.destinationControlValue != 1 else {
                Logger.notification.error("NotificationManager does not support \(#function) with destinationControlValue 1")
                return false
            } // controlByte.destinationControlValue == 3
            let utilityResponse = response.controlByte.sequenceNumberValue
            notification.collectedUtilites[utilityResponse] = id
            Logger.notification.info("NotificationManager has received utility response \(utilityResponse) from '\(Utils.printID(id))' and added it to the collectedUtilites array for notification #\(Utils.printID(notification.hashedID)): \(notification.collectedUtilites)")
            if !notification.hasBeenRespondedTo {
                notification.lastRediscoveryTimestamp = Date.now
                rediscoveryInterval *= 2
                notification.hasBeenRespondedTo = true
            }
            return true
        }
    }
}

// MARK: NotificationConsumer

extension BleepManager: NotificationConsumer {
    
    // MARK: receive notification
    
    func receiveNotification(_ data: Data, from id: String) {
        Logger.notification.debug("NotificationManager attempts to \(#function) of \(data.count-self.minNotificationLength)+\(self.minNotificationLength)=\(data.count) bytes from '\(Utils.printID(id))'")
        
        guard data.count >= minNotificationLength else {
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
        
        let notification = Notification(controlByte: controlByte, hashedID: hashedID, hashedDestinationAddress: hashedDestinationAddress, hashedSourceAddress: hashedSourceAddress, sentTimestampData: sentTimestampData, message: message)
        
        if simulator.evaluationLogger == nil { Logger.notification.warning("NotificationManager did not log for evaluation because the evaluationLogger property of the simulator is nil") }
        else { simulator.evaluationLogger!.log(notification, at: address) }
        
        guard notification.controlByte.destinationControlValue > 0 else {
            Logger.notification.info("NotificationManager received GOODBYE")
            connectionManager.disconnect(id)
            return
        }
        guard notification.controlByte.protocolValue == type.rawValue else {
            Logger.notification.error("NotificationManager will ignore notification #\(Utils.printID(notification.hashedID)), as its protocolValue \(notification.controlByte.protocolValue) doesn't match the type.rawValue \(self.type.rawValue)")
            return
        }
        guard !storedHashedIDs.contains(notification.hashedID) else {
            Logger.notification.info("NotificationManager will ignore notification #\(Utils.printID(notification.hashedID)) as it is already stored")
            return
        }
        guard accept(notification, from: id) else {
            Logger.notification.info("NotificationManager will ignore notification #\(Utils.printID(hashedID)) as accept(notification) returned false")
            return
        }
        Logger.notification.info("NotificationManager accepted notification \(notification.description) with message: '\(notification.message)'")
        
        if countHops, let hopCount = Int(notification.message) {
            notification.message = String(hopCount + 1)
            Logger.notification.info("NotificationManager incremented hop count for notification #\(Utils.printID(hashedID)) from \(hopCount) to \(notification.message)")
        }
        if notification.hashedDestinationAddress == address.hashed {
            Logger.notification.info("NotificationManager is the destination of notification #\(Utils.printID(notification.hashedID))")
            try! notification.controlByte.setDestinationControl(to: 0)
            inbox.append(notification)
        }
        insert(notification)
        if !blocked || type == .forwarding { connectionManager.advertise() }
    }
    
    private func accept(_ notification: Notification, from id: String) -> Bool {
        Logger.notification.debug("NotificationManager attempts to \(#function) #\(Utils.printID(notification.hashedID)) from '\(Utils.printID(id))'")
        
        switch type! {
        case .direct:
            return notification.controlByte.destinationControlValue == 2 && notification.hashedDestinationAddress == address.hashed
            
        case .epidemic:
            return notification.controlByte.destinationControlValue == 1
            
        case .replicating:
            if notification.hashedDestinationAddress == address.hashed {
                let response = Response(controlByte: try! ControlByte(protocolValue: type.rawValue, destinationControlValue: 2, sequenceNumberValue: 0), hashedID: notification.hashedID)
                respond(response, to: id)
                return true
            } else if notification.controlByte.destinationControlValue == 1 {
                let response = Response(controlByte: try! ControlByte(protocolValue: type.rawValue, destinationControlValue: 1, sequenceNumberValue: 0), hashedID: notification.hashedID)
                respond(response, to: id)
                return true
            } else { return false }
            
        case .forwarding:
            if notification.controlByte.destinationControlValue == 1 {
                handleHello(notification)
                return false
            } else if notification.hashedDestinationAddress == address.hashed {
                let response = Response(controlByte: try! ControlByte(protocolValue: type.rawValue, destinationControlValue: 2, sequenceNumberValue: 0), hashedID: notification.hashedID)
                respond(response, to: id)
                return true
            } else {
                let utility = computeUtility(for: notification.hashedDestinationAddress)
                guard notification.controlByte.sequenceNumberValue <= utility else {
                    Logger.notification.trace("NotificationManager utility < notification utility threshold")
                    return false
                }
                Logger.notification.trace("NotificationManager utility >= notification utility threshold")
                if notification.controlByte.destinationControlValue == 2 {
                    let response = Response(controlByte: try! ControlByte(protocolValue: type.rawValue, destinationControlValue: 2, sequenceNumberValue: 0), hashedID: notification.hashedID)
                    respond(response, to: id)
                    return true
                } else { // notification.controlByte.destinationControlValue == 3
                    Logger.notification.trace("NotificationManager received utility probe and will attempt to send utility response")
                    let response = Response(controlByte: try! ControlByte(protocolValue: type.rawValue, destinationControlValue: 3, sequenceNumberValue: utility), hashedID: notification.hashedID)
                    respond(response, to: id)
                    return false
                }
            }
        }
    }
    
    private func handleHello(_ notification: Notification) {
        Logger.notification.debug("NotificationManager attempts to \(#function) \(notification.description)")
        guard notification.controlByte.sequenceNumberValue > 0 || fetchAll(from: notification.hashedSourceAddress) == nil else { return }
        Logger.notification.trace("NotificationManager received a HELLO notification from an unknown source or by a source indicating its RDI has been reset since the last HELLO message")
        if !isRediscoveryIntervalResetDelayed {
            rediscoveryInterval = initialRediscoveryInterval
            hasResetRediscoveryIntervalSinceLastHello = true
        }
        isRediscoveryIntervalResetDelayed.toggle()
    }
    
    // MARK: respond
    
    private func respond(_ response: Response, to id: String) {
        Logger.notification.trace("NotificationManager attempts to \(#function)")
        var data = Data()
        data.append(response.controlByte.value)
        data.append(response.hashedID)
        assert(data.count == responseLength)
        if connectionManager.write(data, to: id) {
            Logger.notification.info("NotificationManager did \(#function) \(response.description) to '\(Utils.printID(id))'")
        } else {
            Logger.notification.error("NotificationManager did not \(#function) \(response.description) to '\(Utils.printID(id))'")
        }
    }
}

// MARK: Utility computation

extension BleepManager {
    
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
}

// MARK: Persistence

extension BleepManager {
    
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
        } catch {
            Logger.notification.error("NotificationManager failed to save the context: \(error)")
        }
    }
    
    private func fetchAllTransmittables() -> [Notification]? {
        Logger.notification.trace("NotificationManager attempts to \(#function)")
        updateAllTransmittables()
        return try? context.fetch(FetchDescriptor<Notification>(predicate: #Predicate<Notification> { return $0.controlByte.destinationControlValue > 0 }))
    }
    
    private func fetchAllTransmittablesCount() -> Int {
        Logger.notification.trace("NotificationManager attempts to \(#function)")
        updateAllTransmittables()
        let result: Int? = try? context.fetchCount(FetchDescriptor<Notification>(predicate: #Predicate<Notification> { return $0.controlByte.destinationControlValue > 0 }))
        return result ?? 0
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
        return try? context.fetch(FetchDescriptor<Notification>(predicate: predicate)).first
    }
    
    private func updateAllTransmittables() {
        let threshold = Date(timeIntervalSinceNow: -notificationTimeToLive)
        Logger.notification.debug("NotificationManager attempts to \(#function) with the notificationTimeToLive date threshold \(threshold)")
        let predicate = #Predicate<Notification> { $0.receivedTimestamp ?? $0.sentTimestamp < threshold }
        guard let notifications = try? context.fetch(FetchDescriptor<Notification>(predicate: predicate)) else {
            Logger.notification.debug("NotificationManager has no notifications to update")
            return
        }
        for notification in notifications { try! notification.controlByte.setDestinationControl(to: 0) }
    }
}
