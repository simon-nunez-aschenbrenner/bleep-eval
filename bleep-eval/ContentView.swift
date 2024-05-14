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
    
    @Environment(BluetoothManager.self) var bluetoothManager
        
    var body: some View {
        TabView {
            PeripheralView (bluetoothManager: bluetoothManager, value: bluetoothManager.peripheralManagerDelegate.value)
                .tabItem {
                    Label("Peripheral", systemImage: "tray.and.arrow.up.fill")
                }
            CentralView (bluetoothManager: bluetoothManager, value: bluetoothManager.centralManagerDelegate.value)
                .tabItem {
                    Label("Central", systemImage: "tray.and.arrow.down.fill")
                }
        }
    }
}

// MARK: PeripheralView

struct PeripheralView: View {
    
    var bluetoothManager: BluetoothManager
    var value: String
    @State var draft: String = "bleep"
    
    var body: some View {
        VStack {
            Text("Peripheral")
                .font(.largeTitle)
                .fontWeight(/*@START_MENU_TOKEN@*/.bold/*@END_MENU_TOKEN@*/)
                .foregroundColor(.gray)
                .padding()
            Spacer()
            HStack {
                TextField("Enter value to publish", text: $draft)
                    .textInputAutocapitalization(.never)
                    .disableAutocorrection(true)
                    .padding()
                    .cornerRadius(10)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color.black, lineWidth: 1)
                    )
                Button(action: {
                    Logger.view.debug("In PeripheralView Button action")
                    draft != "" ? bluetoothManager.publish(draft, nil, nil) : bluetoothManager.stopPublishing()
                    draft = ""
                }) {
                    Text(draft != "" ? "Publish" : "Stop")
                        .fontWeight(/*@START_MENU_TOKEN@*/.bold/*@END_MENU_TOKEN@*/)
                        .padding()
                        .background(Color.black)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                }
            }
            .padding()
            HStack {
                Text(value == "" ? "No value published" : "Published value: ")
                    .fontWeight(.bold)
                    .padding(.horizontal)
                Spacer()
                Text(value)
                    .padding(.horizontal)
//                Button(action: {
//                    Logger.view.trace("In PeripheralView Button action")
//                    publishedValue = ""
//                    bluetoothManager.stop()
//                }) {
//                    Label(
//                        title: { },
//                        icon: { Image(systemName: "xmark.circle.fill").foregroundColor(Color.black) }
//                    )
//                }
//                .opacity(publishedValue == "" ? 0 : 100)
//                .padding(.horizontal)
//                .disabled(publishedValue == "")
            }
            Spacer()
        }
    }
}

// MARK: CentralView

struct CentralView: View {
    
    var bluetoothManager: BluetoothManager
    var value: String
    
    var body: some View {
        VStack {
            Text("Central")
                .font(.largeTitle)
                .fontWeight(/*@START_MENU_TOKEN@*/.bold/*@END_MENU_TOKEN@*/)
                .foregroundColor(.gray)
                .padding()
            Spacer()
            Button(action: {
                Logger.view.debug("In CentralView Button action")
                bluetoothManager.mode.rawValue > -1 ? bluetoothManager.subscribe(nil, nil) : bluetoothManager.unsubscribe(nil, nil)
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
                Text(value == "" ? "No subscribed value" : "Subscribed value: ")
                    .fontWeight(.bold)
                    .padding(.horizontal)
                Spacer()
                Text(value)
                    .padding(.horizontal)
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
        .environment(BluetoothManager())
}
