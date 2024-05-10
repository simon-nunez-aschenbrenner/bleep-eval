//
//  ContentView.swift
//  bleep-eval
//
//  Created by Simon Núñez Aschenbrenner on 03.05.24.
//

import SwiftUI
import Logging

private let logger = Logger(label: "com.simon.bleep-eval.logger.view")

struct ContentView: View {
    
    var bluetoothManager = BluetoothManager()
    
    var body: some View {
        TabView {
            PeripheralView (bluetoothManager: bluetoothManager)
                .tabItem {
                    Label("Peripheral", systemImage: "tray.and.arrow.up.fill")
                }
            CentralView (bluetoothManager: bluetoothManager)
                .tabItem {
                    Label("Central", systemImage: "tray.and.arrow.down.fill")
                }
        }
    }
}

struct PeripheralView: View {
    
    var bluetoothManager: BluetoothManager!
    @State private var messageDraft: String = ""

    func valueIsSet() -> Bool {
        return bluetoothManager.peripheralManagerDelegate.testMessage != nil
    }
    
    var body: some View {
        VStack {
            Text("Peripheral")
                .font(.largeTitle)
                .fontWeight(/*@START_MENU_TOKEN@*/.bold/*@END_MENU_TOKEN@*/)
                .foregroundColor(.gray)
                .padding()
            Spacer()
            TextField("Enter message to publish", text: $messageDraft)
                .padding()
                .overlay(
                    RoundedRectangle(cornerRadius: 10.0)
                        .strokeBorder(Color.black))
                .onSubmit {
                    bluetoothManager.publish(serviceUUID: nil, characteristicUUID: nil, message: messageDraft)
                    messageDraft = ""
                }
                .textInputAutocapitalization(.never)
                .disableAutocorrection(true)
                .padding()
            HStack {
                Text(valueIsSet() ? "Value: " : "No value")
                    .fontWeight(/*@START_MENU_TOKEN@*/.bold/*@END_MENU_TOKEN@*/)
                    .padding(.horizontal)
                Spacer()
                Text(bluetoothManager.outgoingTestMessage ?? "")
                Button(action: {
                    bluetoothManager.outgoingTestMessage = nil
                }) {
                    Label(
                        title: { },
                        icon: { Image(systemName: "xmark.circle.fill").foregroundColor(Color.black) }
                    )
                }
                .opacity(valueIsSet() ? 100 : 0)
                .padding(.horizontal)
                .disabled(!valueIsSet())
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

struct CentralView: View {
    
    var bluetoothManager: BluetoothManager!
    
    var body: some View {
        VStack {
            Text("Central")
                .font(.largeTitle)
                .fontWeight(/*@START_MENU_TOKEN@*/.bold/*@END_MENU_TOKEN@*/)
                .foregroundColor(.gray)
                .padding()
            Spacer()
            Button(action: {
                bluetoothManager.subscribe(serviceUUID: nil, characteristicUUID: nil)
            }) {
                Text("Subscribe")
                    .fontWeight(/*@START_MENU_TOKEN@*/.bold/*@END_MENU_TOKEN@*/)
                    .padding()
                    .background(Color.black)
                    .foregroundColor(.white)
                    .cornerRadius(10)
            }
            .padding()
            HStack {
                Text((bluetoothManager.incomingTestMessage != nil) ? "Value: " : "No value")
                    .fontWeight(/*@START_MENU_TOKEN@*/.bold/*@END_MENU_TOKEN@*/)
                    .padding(.horizontal)
                Spacer()
                Text(bluetoothManager.incomingTestMessage ?? "")
            }
            Spacer()
        }
    }
    
}

struct LogoView: View {
    
    var body: some View {
        ZStack {
            HStack {
                Rectangle()
                    .frame(height: 40)
                Rectangle()
                    .frame(height: 40)
                    .opacity(0)
            }
            HStack {
                Text("bleep")
                    .foregroundColor(.white)
                    .font(.largeTitle)
                    .fontWeight(/*@START_MENU_TOKEN@*/.bold/*@END_MENU_TOKEN@*/)
                Text("bleep")
                    .foregroundColor(.white)
                    .font(.largeTitle)
                    .fontWeight(/*@START_MENU_TOKEN@*/.bold/*@END_MENU_TOKEN@*/)
                    .opacity(0)
            }
        }
        .padding(.vertical, 40)
    }
}

#Preview {
    ContentView()
}
