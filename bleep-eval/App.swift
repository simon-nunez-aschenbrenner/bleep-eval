//
//  App.swift
//  bleep-eval
//
//  Created by Simon Núñez Aschenbrenner on 03.05.24.
//

import SwiftData
import SwiftUI
import OSLog

extension Logger {
    private static var subsystem = Bundle.main.bundleIdentifier!
    static let app = Logger(subsystem: subsystem, category: "app")
    static let notification = Logger(subsystem: subsystem, category: "notification")
    static let bluetooth = Logger(subsystem: subsystem, category: "bluetooth")
    static let peripheral = Logger(subsystem: subsystem, category: "peripheral")
    static let central = Logger(subsystem: subsystem, category: "central")
}

@main
struct bleepEvalApp: App {
    
    @State var notificationManager: NotificationManager
    
    init() {
        self.notificationManager = NotificationManager()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(notificationManager)
        }
    }
}
