//
//  ManualView.swift
//  bleep-eval
//
//  Created by Simon Núñez Aschenbrenner on 02.07.24.
//

import Foundation
import OSLog
import SwiftUI

struct ManualView: View {
    
    unowned var notificationManager: NotificationManager
    @State private var draft: String = ""
    @State private var destinationAddress: Address? = nil
    @FocusState private var textEditorFocused: Bool
    @State private var textEditorHeight: CGFloat = Dimensions.singleLineHeight
    private let columns = [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())]
    
    init(_ notificationManager: NotificationManager) {
        self.notificationManager = notificationManager
    }
    
    private func adjustTextEditorHeight() {
        let newHeight: CGFloat = draft.boundingRect(
            with: CGSize(width: UIScreen.main.bounds.width - Dimensions.textEditorWidthOffset, height: CGFloat.infinity),
            options: .usesLineFragmentOrigin,
            attributes: [.font: UIFont(name: Font.BHTCaseText.Regular, size: Font.Size.Text)!],
            context: nil
        ).height + 2 * Dimensions.mediumPadding
        withAnimation { textEditorHeight = newHeight }
    }
    
    private func sendMessage() {
        if !draft.isEmpty && destinationAddress != nil {
            Logger.view.info("View attempts to \(#function)")
            notificationManager.send(draft, to: destinationAddress!)
            draft.removeAll()
        }
    }
    
    private func getDraftCount() -> Int {
        return draft.data(using: .utf8)?.count ?? 0
    }
    
    var body: some View {

        // MARK: Destinations
        
        LazyVGrid(columns: columns) {
            ForEach(notificationManager.contacts) { address in
                Button(action: {
                    if destinationAddress == address {
                        destinationAddress = nil
                    } else {
                        destinationAddress = address
                    }
                }) {
                    Text(address.name ?? address.base58Encoded)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, minHeight: Dimensions.singleLineHeight)
                        .font(.custom(Font.BHTCaseMicro.Bold, size: Font.Size.Text))
                        .background(address == destinationAddress ? Color("bleepPrimary") : Color("bleepSecondary"))
                        .foregroundColor(Color("bleepPrimaryOnPrimaryBackground"))
                        .cornerRadius(Dimensions.cornerRadius)
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
                .padding(.leading, Dimensions.mediumPadding)
                .padding(.trailing, Dimensions.sendButtonSize + Dimensions.smallPadding)
                .padding(.bottom, Dimensions.lineWidth)
                .onChange(of: draft, initial: true) { adjustTextEditorHeight() }
                .font(.custom(Font.BHTCaseText.Regular, size: Font.Size.Text))
                .overlay(
                    Group { if draft.isEmpty {
                        Text("Select recipient and enter message")
                        .font(.custom(Font.BHTCaseText.Regular, size: Font.Size.Text))
                        .foregroundColor(Color("bleepSecondary"))
                        .padding(.leading, Dimensions.mediumPadding + Dimensions.smallPadding + Dimensions.lineWidth)
                        }
                    },
                    alignment: .leading
                )
                .disableAutocorrection(true)
                .textInputAutocapitalization(.never)
                .focused($textEditorFocused)
                .onTapGesture { textEditorFocused = true }
                Button(action: sendMessage) {
                    Image(systemName: "arrow.up.circle.fill")
                    .resizable()
                    .frame(width: Dimensions.sendButtonSize, height: Dimensions.sendButtonSize)
                    .foregroundColor(draft.isEmpty || destinationAddress == nil ? Color("bleepSecondary"): Color("bleepPrimary"))
                }
                .padding(Dimensions.smallPadding)
                .disabled(draft.isEmpty || destinationAddress == nil)
            }
            .overlay(
                RoundedRectangle(cornerRadius: Dimensions.cornerRadius)
                    .stroke(Color("bleepSecondary"), lineWidth: Dimensions.lineWidth)
            )
            .padding(.horizontal, Dimensions.largePadding)
            Button(action: {
                draft.isEmpty ? draft = Utils.generateText(with: notificationManager.maxMessageLength) : draft.removeAll()
                textEditorFocused = false
            }) {
                Text("\(getDraftCount())/\(notificationManager.maxMessageLength)")
                .font(.custom(Font.BHTCaseMicro.Regular, size: Font.Size.Text))
                .foregroundColor(Color("bleepSecondary"))
            }
            .padding(.trailing, Dimensions.largePadding)
        }

        // MARK: Notifications
        
        VStack(alignment: .center) {
            Text("Received \(notificationManager.inbox.count)/\(notificationManager.receivedHashedIDs.count) notifications")
                .font(.custom(Font.BHTCaseMicro.Bold, size: Font.Size.Text))
                .padding(.horizontal)
            List(notificationManager.inbox.sorted(by: >)) { notification in
                NotificationView(notification: notification)
            }
            .listStyle(.plain)
            Spacer()
        }
    }
}

struct NotificationView: View {
    
    let notification: Notification
    @State private var showsMetadata = false

    var body: some View {
        Button(action: {
            showsMetadata.toggle()
        }) {
            HStack {
                Text(displayText)
                    .font(.custom(Font.BHTCaseMicro.Regular, size: Font.Size.Text))
                    .foregroundColor(Color("bleepPrimary"))
                Spacer()
            }
        }
    }

    private var displayText: String {
        if showsMetadata {
            return notification.description
        } else {
            // TODO: Better way to calculate hops?
            return (notification.protocolValue > 1 ? "(\(Utils.initialNumberOfCopies/notification.sequenceNumberValue-1)) " : "") + notification.message
        }
    }
}
