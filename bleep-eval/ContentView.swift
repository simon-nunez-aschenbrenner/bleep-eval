//
//  ContentView.swift
//  bleep-eval
//
//  Created by Simon Núñez Aschenbrenner on 03.05.24.
//

import SwiftUI
import SwiftData
import OSLog

struct Font {

    struct BHTCaseMicro {
        static let Regular = "BHTCaseMicro-Regular"
        static let Italic = "BHTCaseMicro-Italic"
        static let Bold = "BHTCaseMicro-Bold"
        static let BoldItalic = "BHTCaseMicro-BoldItalic"
    }
    
    struct BHTCaseText {
        static let Regular = "BHTCaseText-Regular"
        static let Italic = "BHTCaseText-Italic"
        static let Bold = "BHTCaseText-Bold"
        static let BoldItalic = "BHTCaseText-BoldItalic"
    }
    
    struct Size {
        static let Logo = 32.0
        static let Title = 32.0
        static let Text = 16.0
    }
}

// MARK: ContentView

struct ContentView: View {
    
    @Environment(NotificationManager.self) var notificationManager
    @State var draft: String = "bleep"
    @State var destinationAddressString: String = "9234973771377527816"
    let exampleDraftWith459Characters = "A quick brown fox jumps over the lazy dog. Every amazing wizard begs for quick but sleepy zebras. My huge sphinx of quartz vows to blow lazy kites apart. Just quickly vexing zebras from California, Dwight jumps over a lazy fox. The five boxing wizards jump quickly, vexing. Big sphinx of quartz, judge my vow! Amazingly few discotheques provide jukeboxes. A quick brown fox jumps over the lazy dog. Pack my box with five dozen liquor jugs. Zebras vex Mr. Fox."
    
    var body: some View {
        VStack(alignment: .leading) {
            LogoView()
                .padding(.vertical)
            Spacer()
            
            HStack(alignment: .bottom) {
                TextField("Enter address", text: $destinationAddressString)
                    .font(.custom(Font.BHTCaseMicro.Regular, size: Font.Size.Text))
                    .textInputAutocapitalization(.never)
                    .disableAutocorrection(true)
                    .padding()
                    .cornerRadius(.infinity)
                    .overlay(
                        RoundedRectangle(cornerRadius: .infinity)
                            .stroke(Color("bleepPrimary"), lineWidth: 1)
                    )
                Button(action: {
                    draft = exampleDraftWith459Characters
                }) {
                    Text("\(draft.count)/459")
                        .font(.custom(Font.BHTCaseMicro.Regular, size: Font.Size.Text))
                        .foregroundColor(Color("bleepPrimary"))
                }
            }
            .padding([.leading, .trailing])
            
            HStack {
                TextField("Enter message", text: $draft)
                    .font(.custom(Font.BHTCaseMicro.Regular, size: Font.Size.Text))
                    .textInputAutocapitalization(.never)
                    .disableAutocorrection(true)
                    .padding()
                    .cornerRadius(.infinity)
                    .overlay(
                        RoundedRectangle(cornerRadius: .infinity)
                            .stroke(Color("bleepPrimary"), lineWidth: 1)
                    )
            }
            .padding([.leading, .trailing])
            
            Button(action: {
                if !draft.isEmpty {
                    let destinationAddress = Address(UInt64(destinationAddressString) ?? 0)
                    let notification = Notification(categoryID: 1, sourceAddress: notificationManager.address, destinationAddress: destinationAddress, message: draft)
                    notificationManager.insertNotification(notification)
                } else {
                    notificationManager.idle()
                }
                draft = ""
            }) {
                Text(!draft.isEmpty ? "Save" : "Stop")
                    .font(.custom(Font.BHTCaseMicro.Bold, size: Font.Size.Text))
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(notificationManager.isIdling && draft.isEmpty ? Color("bleepSecondary") : Color("bleepPrimary"))
                    .foregroundColor(Color("bleepPrimaryOnPrimaryBackground"))
                    .cornerRadius(.infinity)
            }
            .padding(.horizontal)
            .disabled(notificationManager.isIdling && draft.isEmpty)
            
            Text("Current state: \(notificationManager.state)")
                .frame(maxWidth: .infinity)
                .font(.custom(Font.BHTCaseMicro.Regular, size: Font.Size.Text))
                .foregroundColor(Color("bleepPrimary"))
                .padding(.top)
            
            HStack {
                Button(action: {
                    notificationManager.saveContext()
                    notificationManager.publish()
                }) {
                    Text("Publish")
                        .frame(maxWidth: .infinity)
                        .font(.custom(Font.BHTCaseMicro.Bold, size: Font.Size.Text))
                        .padding()
                        .background(Color("bleepPrimary"))
                        .foregroundColor(Color("bleepPrimaryOnPrimaryBackground"))
                        .cornerRadius(.infinity)
                }
                Button(action: {
                    notificationManager.subscribe()
                }) {
                    Text("Subscribe")
                        .frame(maxWidth: .infinity)
                        .font(.custom(Font.BHTCaseMicro.Bold, size: Font.Size.Text))
                        .padding()
                        .background(Color("bleepPrimary"))
                        .foregroundColor(Color("bleepPrimaryOnPrimaryBackground"))
                        .cornerRadius(.infinity)
                }
            }
            .padding(.horizontal)
            
            VStack {
                Text("Notifications:")
                    .font(.custom(Font.BHTCaseMicro.Bold, size: Font.Size.Text))
                    .padding(.horizontal)
                ForEach(notificationManager.notificationsDisplay) { notification in
                    Text(notification.message ?? "")
                        .font(.custom(Font.BHTCaseMicro.Regular, size: Font.Size.Text))
                        .padding(.horizontal)
                }
            }
            Spacer()
        }
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
                        .ignoresSafeArea()
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
    ContentView()
        .environment(NotificationManager())
}
