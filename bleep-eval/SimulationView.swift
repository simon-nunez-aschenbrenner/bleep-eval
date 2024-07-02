//
//  SimulationView.swift
//  bleep-eval
//
//  Created by Simon Núñez Aschenbrenner on 02.07.24.
//

import Combine
import Foundation
import OSLog
import SwiftUI

struct SimulationView: View {
    
    unowned var notificationManager: NotificationManager
    @State private var simulator: Simulator?
    @State private var runID: Int = 0
    @State private var rssiThresholdFactor: Int = -8
    @State private var isSending: Bool = false
    @State private var frequency: Int = 4
    @State private var varianceFactor: Int = 2
    @State private var numberOfCopies: Int = 15
    @State private var destinations: Set<Address>
    
    @State private var countdownTimer: AnyCancellable?
    @State private var remainingCountdownTime: Int = Utils.initialCountdownTime
    @State private var countdownTimerIsActive: Bool = false
    @State private var buttonWidth: CGFloat = .infinity
        
    private let columns = [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())]
    
    init(_ notificationManager: NotificationManager) {
        self.notificationManager = notificationManager
        self.destinations = Set(notificationManager.contacts)
    }
    
    private func startCountdown() {
        Logger.view.trace("View attempts to \(#function)")
        countdownTimerIsActive = true
        countdownTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect().sink { _ in
            if self.remainingCountdownTime > 0 {
                self.remainingCountdownTime -= 1
            } else {
                simulator?.start()
                resetCountdown()
            }
        }
    }
        
    private func resetCountdown() {
        Logger.view.trace("View attempts to \(#function)")
        countdownTimerIsActive = false
        countdownTimer?.cancel()
        remainingCountdownTime = Utils.initialCountdownTime
    }
    
    private func adjustButtonWidth() {
        let initialWidth: CGFloat = UIScreen.main.bounds.width
        let newWidth: CGFloat = initialWidth - CGFloat(Utils.initialCountdownTime - remainingCountdownTime + 1) * initialWidth / (CGFloat(Utils.initialCountdownTime) * 1.4)
        withAnimation { buttonWidth = newWidth }
    }
    
    var body: some View {
        
        // MARK: Destinations
        
        LazyVGrid(columns: columns) {
            ForEach(notificationManager.contacts) { address in
                Button(action: {
                    if destinations.contains(address) && destinations.count > 1 {
                        destinations.remove(address)
                    } else {
                        destinations.insert(address)
                    }
                }) {
                    Text(address.name ?? address.base58Encoded)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, minHeight: Dimensions.singleLineHeight)
                        .font(.custom(Font.BHTCaseMicro.Bold, size: Font.Size.Text))
                        .background(destinations.contains(address) ? Color("bleepPrimary") : Color("bleepSecondary"))
                        .foregroundColor(Color("bleepPrimaryOnPrimaryBackground"))
                        .cornerRadius(Dimensions.cornerRadius)
                }
                .disabled(simulator?.isRunning ?? false)
            }
        }
        .padding(.horizontal)
        
        // MARK: Simulation
        
        List {
            
            Stepper("Simulation #\(runID)", value: $runID, in: 0...Int.max)
                .font(.custom(Font.BHTCaseMicro.Bold, size: Font.Size.Text))
                .foregroundColor(Color("bleepPrimary"))
                .listRowSeparator(.hidden)
                .disabled(simulator?.isRunning ?? false)
            
            Stepper("RSSI threshold: \(rssiThresholdFactor * 8) dBM", value: $rssiThresholdFactor, in: -16...0)
                .font(.custom(Font.BHTCaseMicro.Regular, size: Font.Size.Text))
                .foregroundColor(Color("bleepPrimary"))
                .listRowSeparator(.hidden)
                .disabled(simulator?.isRunning ?? false)
                .onChange(of: rssiThresholdFactor, initial: true) { notificationManager.rssiThreshold = Int8(rssiThresholdFactor * 8) }
            
            HStack {
                Text(isSending ? "Receive and" : "Receive only")
                    .font(.custom(Font.BHTCaseMicro.Regular, size: Font.Size.Text))
                    .foregroundColor(Color("bleepPrimary"))
                Toggle("", isOn: $isSending)
                    .padding(.trailing, Dimensions.largePadding)
                    .tint(Color("bleepPrimary"))
                    .disabled(simulator?.isRunning ?? false)
            }
            .listRowSeparator(.hidden)
            
            if isSending {
                Stepper(frequency > 1 ? "send every \(frequency) seconds" : "send every second", value: $frequency, in: 1...60)
                    .font(.custom(Font.BHTCaseMicro.Regular, size: Font.Size.Text))
                    .foregroundColor(isSending ? Color("bleepPrimary") : Color("bleepSecondary"))
                    .disabled(!isSending)
                    .listRowSeparator(.hidden)
                    .disabled(simulator?.isRunning ?? false)
                
                Stepper("with ±\(varianceFactor * 25)% variance", value: $varianceFactor, in: 0...4)
                    .font(.custom(Font.BHTCaseMicro.Regular, size: Font.Size.Text))
                    .foregroundColor(isSending ? Color("bleepPrimary") : Color("bleepSecondary"))
                    .disabled(!isSending || simulator?.isRunning ?? false)
                    .listRowSeparator(.hidden)
                
                if notificationManager.type == .binarySprayAndWait {
                    Stepper(numberOfCopies > 1 ? "and \(numberOfCopies) copies each" : "and 1 copy each", value: $numberOfCopies, in: 1...15)
                        .font(.custom(Font.BHTCaseMicro.Regular, size: Font.Size.Text))
                        .foregroundColor(isSending ? Color("bleepPrimary") : Color("bleepSecondary"))
                        .disabled(simulator?.isRunning ?? false)
                        .listRowSeparator(.hidden)
                        .onChange(of: numberOfCopies, initial: true) { try! notificationManager.setNumberOfCopies(to: UInt8(numberOfCopies)) }
                }
            }
            
            HStack {
                Spacer(minLength: /*@START_MENU_TOKEN@*/0/*@END_MENU_TOKEN@*/)
                Button(action: {
                    if countdownTimerIsActive {
                        Logger.view.trace("View attempts to cancel the simulation")
                        resetCountdown()
                    } else if !(simulator?.isRunning ?? false) {
                        Logger.view.trace("View attempts to start a new simulation")
                        simulator = try! Simulator(notificationManager: notificationManager, runID: UInt(runID), isSending: isSending, frequency: UInt(frequency), varianceFactor: UInt8(varianceFactor), destinations: destinations)
                        startCountdown()
                    } else {
                        Logger.view.trace("View attempts to stop the simulation")
                        simulator!.stop()
                    }
                }) {
                    Text(countdownTimerIsActive ? String(remainingCountdownTime) : (simulator?.isRunning ?? false ? "Stop" : "Start"))
                        .lineLimit(1)
                        .frame(maxWidth: buttonWidth, minHeight: Dimensions.singleLineHeight)
                        .font(.custom(Font.BHTCaseMicro.Bold, size: Font.Size.Text))
                        .background(simulator?.isRunning ?? false ? Color("bleepPrimary") : Color("bleepSecondary"))
                        .foregroundColor(Color("bleepPrimaryOnPrimaryBackground"))
                        .cornerRadius(Dimensions.cornerRadius)
                        .onChange(of: remainingCountdownTime, initial: true) { adjustButtonWidth() }
                }
                Spacer(minLength: /*@START_MENU_TOKEN@*/0/*@END_MENU_TOKEN@*/)
            }
            .listRowSeparator(.hidden)
            
            HStack {
                Spacer()
                Text("Received \(notificationManager.inbox.count)/\(notificationManager.receivedHashedIDs.count) notifications")
                    .font(.custom(Font.BHTCaseMicro.Regular, size: Font.Size.Text))
                Spacer()
            }
            .listRowSeparator(.hidden)
            
            if let logFileURL = simulator?.logFileURL {
                ShareLink(item: logFileURL, preview: SharePreview(logFileURL.lastPathComponent, image: Image(systemName: "doc.text"))) {
                    Text("Share log file")
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, minHeight: Dimensions.singleLineHeight)
                        .font(.custom(Font.BHTCaseMicro.Bold, size: Font.Size.Text))
                        .foregroundColor(Color("bleepPrimaryOnPrimaryBackground"))
                        .background(Color("bleepPrimary"))
                        .foregroundColor(Color("bleepPrimaryOnPrimaryBackground"))
                        .cornerRadius(Dimensions.cornerRadius)
                }
                .listRowSeparator(.hidden)
            }
        }
        .listStyle(.plain)
        .scrollDisabled(true)
    }
}
