//
//  NotificationManagerProtocol.swift
//  bleep-eval
//
//  Created by Simon Núñez Aschenbrenner on 19.06.24.
//

import Foundation
import SwiftData

protocol NotificationManager: AnyObject {
        
    var container: ModelContainer! { get }
    var context: ModelContext! { get }
    var view: [Notification] { get }
    
    var address: Address! { get }
    var connectionManager: ConnectionManager! { get }
    
    var isPublishing: Bool { get }
    var isSubscribing: Bool { get }
    var isIdling: Bool { get }
    var state: String { get }
        
    init(connectionManagerType: ConnectionManager.Type)
        
    func publish()
    func subscribe()
    func idle()
        
    func updateView()
    func updateView(with notification: Notification)
        
    func fetchCount() -> Int
    func fetchCount(with destinationControlValues: [UInt8]) -> Int
        
    func fetchAll() -> [Notification]?
    func fetchAll(with destinationControlValues: [UInt8]) -> [Notification]?
    func fetchAll(for hashedAddress: Data, includingBroadcast: Bool) -> [Notification]?
    
    func fetchAllHashedIDs() -> [Data]?
    
    func fetch(with hashedID: Data) -> Notification?
        
    func insert(_ notification: Notification, andSave: Bool)
    func save()
}
