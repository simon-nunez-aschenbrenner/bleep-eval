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
    @State var destinationAddressString: String = Address.Broadcast.base58Encoded
    
    var body: some View {
        VStack(alignment: .leading) {
            LogoView()
                .padding(.vertical)
            Spacer()
            
            Text("Source address: \(notificationManager.address.base58Encoded) (\(printID(notificationManager.address.hashed)))")
                .frame(maxWidth: .infinity)
                .font(.custom(Font.BHTCaseMicro.Regular, size: Font.Size.Text))
                .foregroundColor(Color("bleepPrimary"))
                .padding(.top)
            
            HStack(alignment: .bottom) {
                TextField("Enter destination address", text: $destinationAddressString)
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
                    draft = generateText(with: maxMessageLength)
                }) {
                    Text("\(draft.count)/\(maxMessageLength)")
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
                Button(action: {
                    if !draft.isEmpty {
                        let destinationAddress = Address(Address.decode(destinationAddressString) ?? 0)
                        let controlByte = try! ControlByte(protocolValue: 0, destinationControlValue: 1, sequenceNumberValue: 0)
                        let notification = Notification(controlByte: controlByte, sourceAddress: notificationManager.address, destinationAddress: destinationAddress, message: draft)
                        notificationManager.insert(notification)
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
                .disabled(notificationManager.isIdling && draft.isEmpty)
            }
            .padding([.leading, .trailing])
            
            Text("Current state: \(notificationManager.state)")
                .frame(maxWidth: .infinity)
                .font(.custom(Font.BHTCaseMicro.Regular, size: Font.Size.Text))
                .foregroundColor(Color("bleepPrimary"))
                .padding(.top)
            
            HStack {
                Button(action: {
                    notificationManager.save()
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
            
            VStack(alignment: .leading) {
                Text("Notifications:")
                    .font(.custom(Font.BHTCaseMicro.Bold, size: Font.Size.Text))
                    .padding()
                List(notificationManager.notificationView) { notification in
                    NotificationView(notification: notification)
                }
            }
            Spacer()
        }
    }
}

// MARK: NotificationView

struct NotificationView: View {
    let notification: Notification
    @State private var showsMetadata = false

    var body: some View {
        Button(action: {
            showsMetadata.toggle()
        }) {
            Text(displayText)
                .font(.custom(Font.BHTCaseMicro.Regular, size: Font.Size.Text))
                .foregroundColor(Color("bleepPrimary"))
        }
    }

    private var displayText: String {
        if showsMetadata {
            return notification.description
        } else {
            return notification.message
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
        .environment(NotificationManager(version: version))
}
