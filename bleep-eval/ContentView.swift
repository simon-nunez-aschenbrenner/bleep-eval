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
    
    @Environment(BinarySprayAndWait.self) var notificationManager: BinarySprayAndWait
    @FocusState var isFocused: Bool
    @State var draft: String = "bleep"
    @State var hasSetDestinationAddress: Bool = false
    @State var destinationAddress: Address? = nil
    let columns = [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())]
    
    var body: some View {
        VStack(alignment: .leading) {
            LogoView()
                .padding(.vertical)
            
            // MARK: Status
            
            HStack {
                Text("I am \(addressBook.first(where: { $0 == notificationManager.address })?.description ?? "unknown")")
                    .font(.custom(Font.BHTCaseMicro.Regular, size: Font.Size.Text))
                    .foregroundColor(Color("bleepPrimary"))
                if notificationManager.isSubscribing {
                    Image(systemName: "tray.and.arrow.down.fill")
                    Text(String(notificationManager.receivedQueue.count))
                } else if notificationManager.isPublishing {
                    Image(systemName: "tray.and.arrow.up.fill")
                    Text("\(notificationManager.sendQueue.count)")
                } else {
                    Image(systemName: "tray.fill")
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.bottom)

            // MARK: Destinations
            
            LazyVGrid(columns: columns) {
                ForEach(addressBook) { address in
                    Button(action: {
                        if !hasSetDestinationAddress {
                            destinationAddress = address
                            hasSetDestinationAddress = true
                        } else {
                            destinationAddress = nil
                            hasSetDestinationAddress = false
                        }
                    }) {
                        Text(address.name ?? address.base58Encoded)
                            .lineLimit(1)
                            .frame(maxWidth: .infinity)
                            .font(.custom(Font.BHTCaseMicro.Bold, size: Font.Size.Text))
                            .padding()
                            .background(address == destinationAddress ? Color("bleepPrimary") : Color("bleepSecondary"))
                            .foregroundColor(Color("bleepPrimaryOnPrimaryBackground"))
                            .cornerRadius(.infinity)
                    }
                    .disabled(address == notificationManager.address)
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
                        if !draft.isEmpty && destinationAddress != nil {
                            let notification = notificationManager.create(destinationAddress: destinationAddress!, message: draft)
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
            
            // MARK: Notifications
            
            VStack(alignment: .leading) {
                Text("Notifications:")
                    .font(.custom(Font.BHTCaseMicro.Bold, size: Font.Size.Text))
                    .padding([.top, .leading, .trailing])
                List(notificationManager.receivedQueue) { notification in
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
        .environment(BinarySprayAndWait(connectionManagerType: BluetoothManager.self, numberOfCopies: 15))
}
