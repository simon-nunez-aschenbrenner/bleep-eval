//
//  ContentView.swift
//  bleep-eval
//
//  Created by Simon Núñez Aschenbrenner on 03.05.24.
//

import Combine
import Foundation
import OSLog
import SwiftUI
import SwiftData

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

struct Dimensions {
    static let lineWidth: CGFloat = 1.0
    static let largePadding: CGFloat = Font.Size.Text
    static let mediumPadding: CGFloat = Font.Size.Text * 0.5
    static let smallPadding: CGFloat = Font.Size.Text * 0.25
    static let sendButtonSize: CGFloat = Font.Size.Text * 2
    static let singleLineHeight: CGFloat = Font.Size.Text * 2.5 // sendButtonSize + small vertical padding = Font.Size.Text + small and medium vertical padding
    static let cornerRadius: CGFloat = Font.Size.Text * 1.25 // singleLineHeight/2
    static let textEditorWidthOffset: CGFloat = 2 * lineWidth + 2 * largePadding + mediumPadding + 3 * smallPadding + sendButtonSize
}

enum NotificationManagerType: String, CaseIterable, Identifiable {
    case direct = "Direct"
    case epidemic = "Epidemic"
    case binarySprayAndWait = "Spray and Wait"
    var id: Self { self }
}

// MARK: ContentView

struct ContentView: View {
    
    @State private var notificationManager: NotificationManager?
    @State private var showAutoView: Bool = true
    @State private var notificationManagerType: NotificationManagerType = .binarySprayAndWait
    
    private let columns = [GridItem(.flexible()), GridItem(.flexible())]
    
    init() {
        self.setNotificationManagerType(to: self.notificationManagerType)
    }
    
    func setNotificationManagerType(to type: NotificationManagerType) {
        Logger.view.debug("View attempts to \(#function) \(type.rawValue)")
        notificationManagerType = type
        notificationManager = nil
        switch type {
        case .direct:
            notificationManager = Direct(connectionManagerType: BluetoothManager.self)
        case .epidemic:
            notificationManager = Epidemic(connectionManagerType: BluetoothManager.self)
        case .binarySprayAndWait:
            notificationManager = try! BinarySprayAndWait(connectionManagerType: BluetoothManager.self, numberOfCopies: Utils.initialNumberOfCopies)
        }
    }
    
    var body: some View {
        
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
                        if notificationManagerType != type {
                            setNotificationManagerType(to: type)
                        }
                    }) {
                        Text(type.rawValue)
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, minHeight: Dimensions.singleLineHeight)
                            .font(.custom(Font.BHTCaseMicro.Bold, size: Font.Size.Text))
                            .background(type == notificationManagerType ? Color("bleepPrimary") : Color("bleepSecondary"))
                            .foregroundColor(Color("bleepPrimaryOnPrimaryBackground"))
                            .cornerRadius(Dimensions.cornerRadius)
                        }
                    }
                }
                .padding(.horizontal)
            
            // MARK: Status
            
            HStack {
                Spacer()
                Text("Address: \(notificationManager?.address.description.dropLast(6) ?? "unknown")")
                    .font(.custom(Font.BHTCaseText.Regular, size: Font.Size.Text))
                    .foregroundColor(Color("bleepPrimary"))
                    .padding(.vertical, Dimensions.largePadding)
                Spacer()
            }
            
            if notificationManager != nil {
                if showAutoView {
                    AutoView(notificationManager!)
                } else {
                    ManualView(notificationManager!)
                }
            }
        }
        .dynamicTypeSize(DynamicTypeSize.large...DynamicTypeSize.large)
    }
}

// MARK: AutoView

struct AutoView: View {
    
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
        let initialWidth: CGFloat = UIScreen.main.bounds.width - 2 * Dimensions.largePadding
        let newWidth: CGFloat = initialWidth - CGFloat(Utils.initialCountdownTime - remainingCountdownTime + 1) * initialWidth / (CGFloat(Utils.initialCountdownTime) * 1.25)
        withAnimation { buttonWidth = newWidth }
    }
    
    var body: some View {
        
        // MARK: Destinations
        
        LazyVGrid(columns: columns) {
            ForEach(notificationManager.contacts) { address in
                Button(action: {
                    if destinations.contains(address) {
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
            
            HStack {
                Text(isSending ? "Send and receive" : "Receive only")
                    .font(.custom(Font.BHTCaseMicro.Regular, size: Font.Size.Text))
                    .foregroundColor(Color("bleepPrimary"))
                Toggle("", isOn: $isSending)
                    .padding(.trailing, Dimensions.largePadding)
                    .tint(Color("bleepPrimary"))
                    .disabled(simulator?.isRunning ?? false)
            }
            .listRowSeparator(.hidden)
            
            Stepper(frequency > 1 ? "Send every \(frequency) seconds" : "Send every second", value: $frequency, in: 1...60)
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
            
            if notificationManager is BinarySprayAndWait {
                Stepper(numberOfCopies > 1 ? "and \(numberOfCopies) copies" : "and 1 copy", value: $numberOfCopies, in: 1...15)
                    .font(.custom(Font.BHTCaseMicro.Regular, size: Font.Size.Text))
                    .foregroundColor(isSending ? Color("bleepPrimary") : Color("bleepSecondary"))
                    .disabled(!isSending || simulator?.isRunning ?? false)
                    .listRowSeparator(.hidden)
            }
            
            HStack {
                Spacer()
                Button(action: {
                    if countdownTimerIsActive {
                        Logger.view.trace("View attempts to cancel the simulation")
                        resetCountdown()
                    } else if !(simulator?.isRunning ?? false) {
                        Logger.view.trace("View attempts to start a new simulation")
                        simulator = Simulator(notificationManager: notificationManager, runID: UInt(runID), rssiThresholdFactor: Int8(rssiThresholdFactor), isSending: isSending, frequency: UInt(frequency), varianceFactor: UInt8(varianceFactor), numberOfCopies: UInt8(numberOfCopies), destinations: destinations)
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
                Spacer()
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

// MARK: ManualView

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
            let notification = notificationManager.create(destinationAddress: destinationAddress!, message: draft)
            notificationManager.insert(notification)
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
                        .foregroundColor(Color.gray)
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
            return notification.protocolValue > 1 ? "(\(15/notification.sequenceNumberValue)) " : "" + notification.message
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
//        .environment(try! BinarySprayAndWait(connectionManagerType: BluetoothManager.self, numberOfCopies: Utils.initialNumberOfCopies))
}
