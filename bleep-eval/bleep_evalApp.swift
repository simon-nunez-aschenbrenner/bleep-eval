//
//  bleep_evalApp.swift
//  bleep-eval
//
//  Created by Simon Núñez Aschenbrenner on 03.05.24.
//

import SwiftUI

@main
struct bleep_evalApp: App {
    
    @StateObject var peripheralManager = PeripheralManager.shared
    
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
