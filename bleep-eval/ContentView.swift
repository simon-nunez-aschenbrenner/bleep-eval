//
//  ContentView.swift
//  bleep-eval
//
//  Created by Simon Núñez Aschenbrenner on 03.05.24.
//

import SwiftUI
import OSLog

// MARK: ContentView

struct ContentView: View {
        
    var body: some View {
        TabView {
            PeripheralView ()
                .tabItem {
                    Label("Peripheral", systemImage: "tray.and.arrow.up.fill")
                }
            CentralView ()
                .tabItem {
                    Label("Central", systemImage: "tray.and.arrow.down.fill")
                }
        }
    }
}

// MARK: PeripheralView

struct PeripheralView: View {
    
    @Environment(BluetoothManager.self) var bluetoothManager
    // @ObservedObject var peripheralManagerDelegate = bluetoothManager.peripheralManagerDelegate
    @State private var draft: String = ""
    
    var body: some View {
        VStack {
            Text("Peripheral")
                .font(.largeTitle)
                .fontWeight(/*@START_MENU_TOKEN@*/.bold/*@END_MENU_TOKEN@*/)
                .foregroundColor(.gray)
                .padding()
            Spacer()
            TextField("Enter message to publish", text: $draft)
                .padding()
                .overlay(
                    RoundedRectangle(cornerRadius: 10.0)
                        .strokeBorder(Color.black))
                .onSubmit {
                    Logger.view.trace("In PeripheralView TextField onSubmit")
                    bluetoothManager.publish(value: draft, serviceUUID: nil, characteristicUUID: nil)
                    draft = ""
                }
                .textInputAutocapitalization(.never)
                .disableAutocorrection(true)
                .padding()
            HStack {
                Text(bluetoothManager.peripheralManagerDelegate.value == nil ? "No value" : "Value: ")
                    .fontWeight(/*@START_MENU_TOKEN@*/.bold/*@END_MENU_TOKEN@*/)
                    .padding(.horizontal)
                Spacer()
                Text(bluetoothManager.peripheralManagerDelegate.value ?? "")
                Button(action: {
                    Logger.view.trace("In PeripheralView Button action")
                    bluetoothManager.peripheralManagerDelegate.value = nil
                    bluetoothManager.stop()
                }) {
                    Label(
                        title: { },
                        icon: { Image(systemName: "xmark.circle.fill").foregroundColor(Color.black) }
                    )
                }
                .opacity(bluetoothManager.peripheralManagerDelegate.value == nil ? 0 : 100)
                .padding(.horizontal)
                .disabled(bluetoothManager.peripheralManagerDelegate.value == nil)
            }
//            Button(action: {
//                peripheralManagerDelegate.startAdvertising()
//            }) {
//                Text("Start advertising")
//                    .fontWeight(/*@START_MENU_TOKEN@*/.bold/*@END_MENU_TOKEN@*/)
//                    .padding()
//                    .background(sendQueueFilled ? Color.black : Color.gray)
//                    .foregroundColor(.white)
//                    .cornerRadius(10)
//            }
//            .padding()
//            .disabled(!sendQueueFilled)
            Spacer()
        }
    }
}

// MARK: CentralView

struct CentralView: View {
    
    @Environment(BluetoothManager.self) var bluetoothManager
    // @ObservedObject var centralManagerDelegate: CentralManagerDelegate = BluetoothManager.shared.centralManagerDelegate
    
    var body: some View {
        VStack {
            Text("Central")
                .font(.largeTitle)
                .fontWeight(/*@START_MENU_TOKEN@*/.bold/*@END_MENU_TOKEN@*/)
                .foregroundColor(.gray)
                .padding()
            Spacer()
            Button(action: {
                Logger.view.trace("In CentralView Button action")
                bluetoothManager.mode.rawValue > -1 ? bluetoothManager.subscribe(serviceUUID: nil, characteristicUUID: nil) : bluetoothManager.stop()
            }) {
                Text(bluetoothManager.mode.rawValue > -1 ? "Subscribe" : "Unsubscribe")
                    .fontWeight(/*@START_MENU_TOKEN@*/.bold/*@END_MENU_TOKEN@*/)
                    .padding()
                    .background(Color.black)
                    .foregroundColor(.white)
                    .cornerRadius(10)
            }
            .padding()
            HStack {
                Text((bluetoothManager.centralManagerDelegate.value == nil) ? "No value" : "Value: ")
                    .fontWeight(/*@START_MENU_TOKEN@*/.bold/*@END_MENU_TOKEN@*/)
                    .padding(.horizontal)
                Spacer()
                Text(bluetoothManager.centralManagerDelegate.value ?? "")
            }
            Spacer()
        }
    }
}

//struct LogoView: View {
//    
//    var body: some View {
//        ZStack {
//            HStack {
//                Rectangle()
//                    .frame(height: 40)
//                Rectangle()
//                    .frame(height: 40)
//                    .opacity(0)
//            }
//            HStack {
//                Text("bleep")
//                    .foregroundColor(.white)
//                    .font(.largeTitle)
//                    .fontWeight(/*@START_MENU_TOKEN@*/.bold/*@END_MENU_TOKEN@*/)
//                Text("bleep")
//                    .foregroundColor(.white)
//                    .font(.largeTitle)
//                    .fontWeight(/*@START_MENU_TOKEN@*/.bold/*@END_MENU_TOKEN@*/)
//                    .opacity(0)
//            }
//        }
//        .padding(.vertical, 40)
//    }
//}

#Preview {
    ContentView()
}
