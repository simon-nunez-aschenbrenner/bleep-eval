//
//  MainView.swift
//  bleep-eval
//
//  Created by Simon Núñez Aschenbrenner on 03.05.24.
//

import Foundation
import OSLog
import SwiftUI

struct MainView: View {
    
    @Environment(BleepManager.self) private var notificationManager: BleepManager
    @State private var showAutoView: Bool = true
    @State private var showNotifications: Bool = false
    private let columns = [GridItem(.flexible()), GridItem(.flexible())]
        
    var body: some View {
        
        ZStack {
            
            VStack(alignment: .leading) {
                
                // MARK: Logo
                
                ZStack {
                    LogoView()
                        .padding(.vertical, Dimensions.largePadding)
                    Toggle("", isOn: $showAutoView)
                        .padding(.trailing, Dimensions.largePadding)
                        .tint(Color("bleepPrimary"))
                }
                
                // MARK: Protocol
                
                LazyVGrid(columns: columns) {
                    ForEach(NotificationManagerType.allCases) { type in
                        Button(action: {
                            if notificationManager.type != type {
                                notificationManager.type = type
                            }
                        }) {
                            Text(type.description)
                                .lineLimit(1)
                                .frame(maxWidth: .infinity, minHeight: Dimensions.singleLineHeight)
                                .font(.custom(Font.BHTCaseMicro.Bold, size: Font.Size.Text))
                                .background(type == notificationManager.type ? Color("bleepPrimary") : Color("bleepSecondary"))
                                .foregroundColor(Color("bleepPrimaryOnPrimaryBackground"))
                                .cornerRadius(Dimensions.cornerRadius)
                        }
                        .disabled(notificationManager.simulator.isRunning)
                    }
                }
                .padding(.horizontal)
                
                // MARK: Status
                
                HStack {
                    Spacer()
                    Text("I am \(notificationManager.address.description.dropLast(6))")
                        .font(.custom(Font.BHTCaseText.Regular, size: Font.Size.Text))
                        .foregroundColor(Color("bleepPrimary"))
                        .padding(.vertical, Dimensions.largePadding)
                    Spacer()
                }
                
                if showAutoView {
                    SimulationView(notificationManager)
                        .opacity(showNotifications ? 0.5 : 1)
                        .blur(radius: showNotifications ? Dimensions.blurRadius : 0)
                        .animation(.easeInOut, value: showNotifications)
                } else {
                    ManualView(notificationManager)
                        .opacity(showNotifications ? 0.5 : 1)
                        .blur(radius: showNotifications ? Dimensions.blurRadius : 0)
                        .animation(.easeInOut, value: showNotifications)
                }
                
                Spacer(minLength: Dimensions.extraLargePadding + Dimensions.singleLineHeight + Dimensions.largePadding)
            }
            .edgesIgnoringSafeArea(.bottom)
            
            // MARK: Notifications
            
            VStack(alignment: .center) {
                Spacer()
                VStack {
                    Text("Received \(notificationManager.inbox.count)/\(notificationManager.storedHashedIDsCount) notifications")
                        .font(.custom(Font.BHTCaseMicro.Bold, size: Font.Size.Text))
                        .foregroundColor(Color("bleepPrimaryOnPrimaryBackground"))
                        .padding(.vertical, Dimensions.largePadding)
                    if showNotifications {
                        List(notificationManager.inbox.sorted(by: >)) { notification in
                            NotificationView(notification: notification, notificationManager: notificationManager)
                                .listRowBackground(Color("bleepPrimary"))
                                .listRowSeparator(.visible)
                                .listRowSeparatorTint(Color("bleepPrimaryOnPrimaryBackground"))
                        }
                        .listStyle(.plain)
                        .padding(.trailing, Dimensions.largePadding)
                    }
                }
                .frame(height: showNotifications ? UIScreen.main.bounds.height * 0.5 : Dimensions.singleLineHeight)
                .frame(maxWidth: .infinity)
                .background(notificationManager.inbox.count > 0 ? Color("bleepPrimary") : Color("bleepSecondary"))
                .cornerRadius(Dimensions.cornerRadius)
                .animation(.snappy, value: showNotifications)
                .onTapGesture {
                    if !showNotifications && notificationManager.inbox.count > 0 {
                        showNotifications = true
                    }
                }
            }
            .padding(.horizontal, showNotifications ? 0 : Dimensions.largePadding)
            .background(
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture { showNotifications = false }
                    .allowsHitTesting(showNotifications)
            )
            .padding(.bottom, showNotifications ? 0 : Dimensions.extraLargePadding)
            .edgesIgnoringSafeArea(.bottom)
        }
        .dynamicTypeSize(DynamicTypeSize.large...DynamicTypeSize.large)
    }
}

// MARK: NotificationView

struct NotificationView: View {
    
    let notification: Notification
    unowned var notificationManager: EvaluableNotificationManager
    @State private var showsMetadata = false
    private var displayText: String {
        if showsMetadata { return notification.description }
        else { return notification.message }
    }

    var body: some View {
        
        Button(action: {
            showsMetadata.toggle()
        }) {
            HStack {
                Text(displayText)
                    .font(.custom(Font.BHTCaseMicro.Regular, size: Font.Size.Text))
                    .foregroundColor(Color("bleepPrimaryOnPrimaryBackground"))
                    .transaction { $0.animation = nil }
                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: LogoView

struct LogoView: View {
    
    let spacing = 1.5
    let height = Font.Size.Logo + 10.0
    
    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: spacing) {
                ZStack(alignment: .trailing) {
                    Color("bleepPrimary")
                        .frame(maxWidth: .infinity, maxHeight: height, alignment: .leading)
                    Text("bleep")
                        .font(.custom(Font.BHTCaseMicro.Bold, size: Font.Size.Logo))
                        .foregroundColor(Color("bleepPrimaryOnPrimaryBackground"))
                        .padding(.trailing, spacing)
                }
                Text("eval")
                    .font(.custom(Font.BHTCaseText.Regular, size: Font.Size.Logo))
                    .foregroundColor(Color("bleepPrimary"))
            }
            .padding(.trailing, geometry.size.width/3)
        }
        .frame(maxHeight: height)
    }
}

#Preview {
    MainView()
        .environment(BleepManager())
}
