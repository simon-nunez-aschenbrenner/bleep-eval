//
//  ContentView.swift
//  bleep-eval
//
//  Created by Simon Núñez Aschenbrenner on 03.05.24.
//

import SwiftUI
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
    
    @Environment(BluetoothManager.self) var bluetoothManager
        
    var body: some View {
        VStack {
            LogoView()
                .padding(.vertical)
            TabView {
                CentralView (bluetoothManager: bluetoothManager, notifications: bluetoothManager.centralManagerDelegate.notifications)
                    .tabItem {
                        Label("Central", systemImage: "tray.and.arrow.down.fill")
                    }
                PeripheralView (bluetoothManager: bluetoothManager, notifications: bluetoothManager.peripheralManagerDelegate.notifications)
                    .tabItem {
                        Label("Peripheral", systemImage: "tray.and.arrow.up.fill")
                    }
            }
            .accentColor(Color("bleepPrimary"))
        }
    }
}

// MARK: CentralView

struct CentralView: View {
    
    var bluetoothManager: BluetoothManager
    var notifications: [UInt16: Notification]
    var shallBeDisabled: Bool {
        if !bluetoothManager.modeIsCentral { return false }
        else { return bluetoothManager.centralManagerDelegate.peripheral == nil }
    }
    
    var body: some View {
        VStack(alignment: .leading) {
            Spacer()
            Text("Central")
                .font(.custom(Font.BHTCaseMicro.Bold, size: Font.Size.Title))
                .foregroundColor(Color("bleepSecondary"))
                .padding([.top, .leading])
            HStack {
                Button(action: {
                    bluetoothManager.modeIsCentral ? bluetoothManager.idle() : bluetoothManager.subscribe()
                }) {
                    Text(bluetoothManager.modeIsCentral ? "Unsubscribe" : "Subscribe")
                        .font(.custom(Font.BHTCaseMicro.Bold, size: Font.Size.Text))
                        .padding()
                        .background(shallBeDisabled ? Color("bleepSecondary") : Color("bleepPrimary"))
                        .foregroundColor(Color("bleepPrimaryOnPrimaryBackground"))
                        .cornerRadius(.infinity)
                }
                .disabled(shallBeDisabled)
            }
            .padding([.bottom, .leading, .trailing])
            HStack {
                Text(bluetoothManager.modeIsCentral && !notifications.isEmpty ? "Notification: " : "No notification")
                    .font(.custom(Font.BHTCaseMicro.Bold, size: Font.Size.Text))
                    .padding(.horizontal)
                Spacer()
                Text(notifications.first?.value.message ?? "") // TODO: change
                    .font(.custom(Font.BHTCaseMicro.Regular, size: Font.Size.Text))
                    .padding(.horizontal)
                    .opacity(bluetoothManager.modeIsCentral ? 1 : 0)
            }
            Spacer()
        }
    }
}

// MARK: PeripheralView

struct PeripheralView: View {
    
    var bluetoothManager: BluetoothManager
    var notifications: [UInt16: Notification]
    @State var draft: String = "bleep"
    
    let exampleDraftWith505Characters = "The quick brown fox jumps over the lazy dog. This sentence contains every letter in the English alphabet at least once, making it a popular example of a pangram. Pangrams are useful for testing fonts, keyboards, and other typographical elements. The fox, quick and agile, effortlessly leaps over the dog, who is resting peacefully. As the sun sets, the animals continue their dance, each movement a testament to nature's harmony. In this simple scene, one finds a reminder of beauty and balance in nature."
    
    var body: some View {
        VStack(alignment: .leading) {
            Spacer()
            HStack(alignment: .bottom) {
                Text("Peripheral")
                    .font(.custom(Font.BHTCaseMicro.Bold, size: Font.Size.Title))
                    .foregroundColor(Color("bleepSecondary"))
                    .padding([.top, .leading])
                Spacer()
                Button(action: {
                    draft = exampleDraftWith505Characters
                }) {
                    Text("\(draft.count)/505")
                        .font(.custom(Font.BHTCaseMicro.Regular, size: Font.Size.Text))
                        .padding()
                }
            }
            HStack {
                TextField("Enter value to publish", text: $draft)
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
                    draft != "" ? bluetoothManager.publish(draft) : bluetoothManager.idle()
                    draft = ""
                }) {
                    Text(draft != "" ? "Publish" : "Stop")
                        .font(.custom(Font.BHTCaseMicro.Bold, size: Font.Size.Text))
                        .padding()
                        .background(bluetoothManager.modeIsUndefined && draft == "" ? Color("bleepSecondary") : Color("bleepPrimary"))
                        .foregroundColor(Color("bleepPrimaryOnPrimaryBackground"))
                        .cornerRadius(.infinity)
                }
                .disabled(bluetoothManager.modeIsUndefined && draft == "")
            }
            .padding([.bottom, .leading, .trailing])
            HStack {
                Text(bluetoothManager.modeIsPeripheral && !notifications.isEmpty ? "Notification: " : "No notification")
                    .font(.custom(Font.BHTCaseMicro.Bold, size: Font.Size.Text))
                    .padding(.horizontal)
                Spacer()
                Text(notifications.first?.value.message ?? "") // TODO: change
                    .font(.custom(Font.BHTCaseMicro.Regular, size: Font.Size.Text))
                    .padding(.horizontal)
                    .opacity(bluetoothManager.modeIsPeripheral ? 1 : 0)
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
        .environment(BluetoothManager())
}
