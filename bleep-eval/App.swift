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
    static let bluetooth = Logger(subsystem: subsystem, category: "bluetooth")
}

@main
struct bleepEvalApp: App {
    
    @State var bluetoothManager = BluetoothManager()
    
    init() {
        let tabBarAppearance = UITabBarAppearance()
        tabBarAppearance.stackedLayoutAppearance.normal.titleTextAttributes = [.font: UIFont(name: Font.BHTCaseMicro.Regular, size: 10)!]
        tabBarAppearance.inlineLayoutAppearance.normal.titleTextAttributes = [.font: UIFont(name: Font.BHTCaseMicro.Regular, size: 10)!]
        tabBarAppearance.compactInlineLayoutAppearance.normal.titleTextAttributes = [.font: UIFont(name: Font.BHTCaseMicro.Regular, size: 10)!]
        UITabBar.appearance().standardAppearance = tabBarAppearance
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(bluetoothManager)
        }
    }
}
