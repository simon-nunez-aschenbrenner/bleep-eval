//
//  App.swift
//  bleep-eval
//
//  Created by Simon Núñez Aschenbrenner on 03.05.24.
//

import SwiftUI
import OSLog

extension Logger {
    private static var subsystem = Bundle.main.bundleIdentifier!
    static let view = Logger(subsystem: subsystem, category: "view")
    static let bluetooth = Logger(subsystem: subsystem, category: "bluetooth")
}

@main
struct bleepEvalApp: App {
    
    @State var bluetoothManager = BluetoothManager()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(bluetoothManager)
        }
    }
}
