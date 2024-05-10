//
//  ContentView.swift
//  bleep-eval
//
//  Created by Simon Núñez Aschenbrenner on 03.05.24.
//

import SwiftUI

struct ContentView: View {
    
    @StateObject var peripheralManagerDelegate = PeripheralManagerDelegate()
    @StateObject var centralManagerDelegate = CentralManagerDelegate()
    
    var body: some View {
        TabView {
            PeripheralView (peripheralManagerDelegate: peripheralManagerDelegate)
                .tabItem {
                    Label("Peripheral", systemImage: "tray.and.arrow.up.fill")
                }
                .onAppear(perform: peripheralManagerDelegate.startAdvertising)
                .onDisappear(perform: peripheralManagerDelegate.stopAdvertising)
            CentralView (peripheralDelegate: centralManagerDelegate.peripheralDelegate)
                .tabItem {
                    Label("Central", systemImage: "tray.and.arrow.down.fill")
                }
                .onAppear(perform: centralManagerDelegate.startScan)
                .onDisappear(perform: centralManagerDelegate.stopScan)
        }
    }
}

struct PeripheralView: View {
    
    @ObservedObject var peripheralManagerDelegate: PeripheralManagerDelegate
    @State private var messageDraft: String = ""

    func messageIsQueued() -> Bool {
        return peripheralManagerDelegate.testMessage != nil
    }
    
    var body: some View {
        VStack {
            Text("Peripheral")
                .font(.largeTitle)
                .fontWeight(/*@START_MENU_TOKEN@*/.bold/*@END_MENU_TOKEN@*/)
                .foregroundColor(.gray)
                .padding()
            Spacer()
            TextField("Enter message", text: $messageDraft)
                .padding()
                .overlay(
                    RoundedRectangle(cornerRadius: 10.0)
                        .strokeBorder(Color.black))
                .onSubmit {
                    peripheralManagerDelegate.testMessage = messageDraft
                    messageDraft = ""
                }
                .textInputAutocapitalization(.never)
                .disableAutocorrection(true)
                .padding()
            HStack {
                Text(messageIsQueued() ? "Value: " : "No value")
                    .fontWeight(/*@START_MENU_TOKEN@*/.bold/*@END_MENU_TOKEN@*/)
                    .padding(.horizontal)
                Spacer()
                Text(peripheralManagerDelegate.testMessage ?? "")
                Button(action: {
                    peripheralManagerDelegate.testMessage = nil
                }) {
                    Label(
                        title: { },
                        icon: { Image(systemName: "xmark.circle.fill").foregroundColor(Color.black) }
                    )
                }
                .opacity(messageIsQueued() ? 100 : 0)
                .padding(.horizontal)
                .disabled(!messageIsQueued())
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
    
    @ObservedObject var peripheralDelegate: PeripheralDelegate
    
    var body: some View {
        VStack {
            Text("Central")
                .font(.largeTitle)
                .fontWeight(/*@START_MENU_TOKEN@*/.bold/*@END_MENU_TOKEN@*/)
                .foregroundColor(.gray)
                .padding()
            Spacer()
//            Button(action: {
//                centralManagerDelegate.startScan()
//            }) {
//                Text("Start scan")
//                    .fontWeight(/*@START_MENU_TOKEN@*/.bold/*@END_MENU_TOKEN@*/)
//                    .padding()
//                    .background(Color.black)
//                    .foregroundColor(.white)
//                    .cornerRadius(10)
//            }
//            .padding()
            HStack {
                Text((peripheralDelegate.testMessage != nil) ? "Value: " : "No value")
                    .fontWeight(/*@START_MENU_TOKEN@*/.bold/*@END_MENU_TOKEN@*/)
                    .padding(.horizontal)
                Spacer()
                Text(peripheralDelegate.testMessage ?? "")
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
