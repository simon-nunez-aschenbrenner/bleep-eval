//
//  ConnectionManagerProtocol.swift
//  bleep-eval
//
//  Created by Simon Núñez Aschenbrenner on 19.06.24.
//

import Foundation

enum DeviceMode: Int, CustomStringConvertible {
    case consumer = -1
    case undefined = 0
    case provider = 1
    
    var isConsumer: Bool { return !(self.rawValue > -1) }
    var isUndefined: Bool { return self.rawValue == 0 }
    var isProvider: Bool { return !(self.rawValue < 1) }
    
    var description: String {
        switch self {
        case .consumer: return "Consumer"
        case .undefined: return "Undefined"
        case .provider:  return "Provider"
        }
    }
}

protocol ConnectionManager {
    
    var notificationManager: NotificationManager! { get }
    var mode: DeviceMode! { get }

    init(notificationManager: NotificationManager)
    
    func setMode(to mode: DeviceMode)
    func send(notification data: Data) -> Bool
}
