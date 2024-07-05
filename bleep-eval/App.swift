//
//  App.swift
//  bleep-eval
//
//  Created by Simon Núñez Aschenbrenner on 03.05.24.
//

import Foundation
import SwiftData
import SwiftUI

@main
struct bleepEvalApp: App {
    
    @State private var notificationManager = BleepManager()

    var body: some Scene {
        WindowGroup {
            MainView()
                .environment(notificationManager)
        }
    }
}
