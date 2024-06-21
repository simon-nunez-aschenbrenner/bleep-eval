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
    
    @Environment(\.notificationManager) var notificationManager: NotificationManager
    @FocusState private var isFocused: Bool
    @State var draft: String = "bleep"
    @State var destinationAddress: Address = Address.Broadcast
    let columns = [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())]
    
    var body: some View {
        VStack(alignment: .leading) {
            LogoView()
                .padding(.vertical)
            
            // MARK: Source
            
            Text("I am \(addressBook.first(where: { $0.rawValue == notificationManager.address.rawValue })?.description ?? "unknown")")
                .frame(maxWidth: .infinity)
                .font(.custom(Font.BHTCaseMicro.Regular, size: Font.Size.Text))
                .foregroundColor(Color("bleepPrimary"))
                .padding([.leading, .bottom])

            // MARK: Destinations
            
            LazyVGrid(columns: columns) {
                ForEach(addressBook) { address in
                    Button(action: {
                        destinationAddress = address
                    }) {
                        Text(address.name ?? address.base58Encoded)
                            .lineLimit(1)
                            .frame(maxWidth: .infinity)
                            .font(.custom(Font.BHTCaseMicro.Bold, size: Font.Size.Text))
                            .padding()
                            .background(address.rawValue != destinationAddress.rawValue || address.rawValue == notificationManager.address.rawValue ? Color("bleepSecondary") : Color("bleepPrimary"))
                            .foregroundColor(Color("bleepPrimaryOnPrimaryBackground"))
                            .cornerRadius(.infinity)
                    }
                    .disabled(address.rawValue == notificationManager.address.rawValue)
                }
            }
            .padding(.horizontal)
            
            // MARK: Message
            
            HStack(alignment: .bottom) {
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
                    .focused($isFocused)
                    .onSubmit {
                        if !draft.isEmpty {
                            let notification = notificationManager.create(destinationAddress: destinationAddress, message: draft)
                            notificationManager.insert(notification)
                            notificationManager.save()
                            draft.removeAll()
                        }
                        notificationManager.decide()
                        isFocused = false
                    }
                
                Button(action: {
                    draft = generateText(with: maxMessageLength)
                }) {
                    Text("\(draft.count)/\(maxMessageLength)")
                        .font(.custom(Font.BHTCaseMicro.Regular, size: Font.Size.Text))
                        .foregroundColor(Color("bleepPrimary"))
                }
            }
            .padding([.leading, .trailing])
            
            // MARK: State
            
//            HStack {
//                Button(action: {
//                    if !draft.isEmpty {
//                        let notification = notificationManager.create(destinationAddress: destinationAddress, message: draft)
//                        notificationManager.insert(notification)
//                        draft.removeAll()
//                    }
//                    notificationManager.save()
//                    notificationManager.publish()
//                }) {
//                    Text("Publish")
//                        .frame(maxWidth: .infinity)
//                        .font(.custom(Font.BHTCaseMicro.Bold, size: Font.Size.Text))
//                        .padding()
//                        .background(notificationManager.isPublishing ? Color("bleepPrimary") : Color("bleepSecondary"))
//                        .foregroundColor(Color("bleepPrimaryOnPrimaryBackground"))
//                        .cornerRadius(.infinity)
//                }
//                Button(action: {
//                    notificationManager.isIdling ? notificationManager.subscribe(): notificationManager.idle()
//                }) {
//                    Text(notificationManager.isIdling ? "Subscribe" : "Idle")
//                        .frame(maxWidth: .infinity)
//                        .font(.custom(Font.BHTCaseMicro.Bold, size: Font.Size.Text))
//                        .padding()
//                        .background(notificationManager.isSubscribing ? Color("bleepPrimary") : Color("bleepSecondary"))
//                        .foregroundColor(Color("bleepPrimaryOnPrimaryBackground"))
//                        .cornerRadius(.infinity)
//                }
//            }
//            .padding([.leading, .top, .trailing])
            
            // MARK: Notifications
            
            VStack(alignment: .leading) {
                Text("Notifications:")
                    .font(.custom(Font.BHTCaseMicro.Bold, size: Font.Size.Text))
                    .padding([.top, .leading, .trailing])
                List(notificationManager.view) { notification in
                    NotificationView(notification: notification)
                }
                Spacer()
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
        .environment(BinarySprayAndWait(connectionManagerType: BluetoothManager.self, numberOfCopies: 3))
}
