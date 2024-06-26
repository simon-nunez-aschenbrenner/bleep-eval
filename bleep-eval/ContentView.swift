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
    @FocusState private var isFocused: Bool
    @State private var draft: String = ""
    @State private var destinationAddress: Address? = nil
    
    private let columns = [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())]
    // Padding properties
    private let largePadding: CGFloat = Font.Size.Text
    private let mediumPadding: CGFloat = Font.Size.Text * 0.5
    private let smallPadding: CGFloat = Font.Size.Text * 0.25
    // Rounded Rectangle properties
    private let sendButtonSize: CGFloat = Font.Size.Text * 2
    private let cornerRadius: CGFloat = (Font.Size.Text * 2.5) * 0.5
    private let lineWidth: CGFloat = 1
    private let singleLineHeight: CGFloat = Font.Size.Text * 2.5
    @State private var textEditorHeight: CGFloat = Font.Size.Text * 2.5 // sendButtonSize + small vertical padding = Font.Size.Text + small and medium vertical padding
    
    private func adjustTextEditorHeight() {
        let newHeight = draft.boundingRect(
            with: CGSize(width: UIScreen.main.bounds.width - (2*largePadding+mediumPadding+3*smallPadding+2*lineWidth+sendButtonSize), height: CGFloat.infinity),
            options: .usesLineFragmentOrigin,
            attributes: [.font: UIFont(name: Font.BHTCaseText.Regular, size: Font.Size.Text)!],
            context: nil
        ).height + 2*mediumPadding
        withAnimation { textEditorHeight = newHeight }
    }
    
    private func sendMessage() {
        if !draft.isEmpty && destinationAddress != nil {
            let notification = notificationManager.create(destinationAddress: destinationAddress!, message: draft)
            notificationManager.insert(notification)
            notificationManager.save()
            draft.removeAll()
        }
        notificationManager.decide()
    }
    
    var body: some View {
        VStack(alignment: .leading) {
            LogoView()
            .padding(.vertical, largePadding)
            
            // MARK: Status
            
            HStack {
                Text("I am \(addressBook.first(where: { $0 == notificationManager.address })?.description ?? "unknown")")
                    .font(.custom(Font.BHTCaseText.Regular, size: Font.Size.Text))
                    .foregroundColor(Color("bleepPrimary"))
                Button(action: { notificationManager.reset() }) {
                    if notificationManager.isSubscribing {
                        Image(systemName: "tray.and.arrow.down.fill")
                    } else if notificationManager.isPublishing {
                        Image(systemName: "tray.and.arrow.up.fill")
                    } else {
                        Image(systemName: "tray.fill")
                    }
                }
                .foregroundColor(Color("bleepPrimary"))
            }
            .frame(maxWidth: .infinity)
            .padding(.bottom, largePadding)

            // MARK: Destinations
            
            LazyVGrid(columns: columns) {
                ForEach(addressBook) { address in
                    Button(action: {
                        if destinationAddress == address {
                            destinationAddress = nil
                        } else {
                            destinationAddress = address
                        }
                    }) {
                        Text(address.name ?? address.base58Encoded)
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, minHeight: singleLineHeight)
                            .font(.custom(Font.BHTCaseMicro.Bold, size: Font.Size.Text))
                            .background(address == destinationAddress ? Color("bleepPrimary") : Color("bleepSecondary"))
                            .foregroundColor(Color("bleepPrimaryOnPrimaryBackground"))
                            .cornerRadius(cornerRadius)
                    }
                    .disabled(address == notificationManager.address)
                }
            }
            .padding(.horizontal)
            
            // MARK: Message
            
            VStack(alignment: .trailing) {
                ZStack(alignment: .bottomTrailing) {
                    TextEditor(text: $draft)
                    .background(Color.clear)
                    .frame(height: textEditorHeight)
                    .padding(.leading, mediumPadding)
                    .padding(.trailing, sendButtonSize+smallPadding)
                    .padding(.bottom, lineWidth)
                    .onChange(of: draft, initial: true) { adjustTextEditorHeight() }
                    .font(.custom(Font.BHTCaseText.Regular, size: Font.Size.Text))
                    .overlay(
                        Group { if draft.isEmpty {
                            Text("Select recipient and enter message")
                            .font(.custom(Font.BHTCaseText.Regular, size: Font.Size.Text))
                            .foregroundColor(Color.gray)
                            .padding(.leading, mediumPadding+smallPadding+lineWidth)
                            .allowsHitTesting(false)
                            }
                        },
                        alignment: .leading
                    )
                    Button(action: sendMessage) {
                        Image(systemName: draft.isEmpty || destinationAddress == nil ? "questionmark.circle.fill" : "arrow.up.circle.fill")
                        .resizable()
                        .frame(width: sendButtonSize, height: sendButtonSize)
                        .foregroundColor(Color("bleepPrimary"))
                    }
                    .padding(smallPadding)
                }
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .stroke(Color("bleepSecondary"), lineWidth: lineWidth)
                )
                .padding(.horizontal, largePadding)
                Button(action: { draft.isEmpty ? draft = generateText(with: maxMessageLength) : draft.removeAll() }) {
                    Text("\(draft.count)/\(maxMessageLength)")
                    .font(.custom(Font.BHTCaseMicro.Regular, size: Font.Size.Text))
                    .foregroundColor(Color("bleepSecondary"))
                }
                .padding(.trailing, largePadding)
            }

            // MARK: Notifications
            
            VStack(alignment: .center) {
                Text("Received \(notificationManager.inbox.count) notifications")
                    .font(.custom(Font.BHTCaseMicro.Bold, size: Font.Size.Text))
                    .underline()
                    .padding(.horizontal)
                List(notificationManager.inbox) { notification in
                    NotificationView(notification: notification)
                }
                Spacer()
            }
        }
        .dynamicTypeSize(DynamicTypeSize.large...DynamicTypeSize.large)
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
//                        .ignoresSafeArea()
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
        .environment(try! BinarySprayAndWait(connectionManagerType: BluetoothManager.self, numberOfCopies: 15))
}
