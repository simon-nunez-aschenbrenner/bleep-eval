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
    @StateObject var peripheralDelegate = PeripheralDelegate()
    
    @State private var messageDraft: String = ""
    
    @State private var queuedMessage: String = ""
    @State private var sendQueueFilled: Bool = false
    
    func addToQueue(_ message: String ) {
        queuedMessage = message
        sendQueueFilled = true
    }
    
    func clearQueue() {
        sendQueueFilled = false
        queuedMessage = ""
    }
    
    var body: some View {
        VStack {
            
            ZStack {
                HStack {
                    Rectangle()
                        .frame(width: 180, height: 20, alignment: .leading)
                    Spacer()
                }
                HStack {
                    Text("bleep")
                        .foregroundColor(.white)
                        .fontWeight(/*@START_MENU_TOKEN@*/.bold/*@END_MENU_TOKEN@*/)
                    Text("evaluation")
                }
            }
            .padding(.vertical)
            
            Text("Peripheral")
                .font(.largeTitle)
                .fontWeight(/*@START_MENU_TOKEN@*/.bold/*@END_MENU_TOKEN@*/)
                .foregroundColor(.gray)
            
            TextField("Enter message", text: $messageDraft)
                .padding()
                .overlay(
                    RoundedRectangle(cornerRadius: 10.0)
                        .strokeBorder(Color.black))
                .onSubmit {
                    addToQueue(messageDraft)
                    messageDraft = ""
                }
                .textInputAutocapitalization(.never)
                .disableAutocorrection(true)
                .padding()
            
            HStack {
                Text(sendQueueFilled ? "Send queue: " : "Send queue empty")
                    .fontWeight(/*@START_MENU_TOKEN@*/.bold/*@END_MENU_TOKEN@*/)
                    .padding(.horizontal)
                Spacer()
                Text(queuedMessage)
                    .opacity(sendQueueFilled ? 100 : 0)
                Button(action: {
                    queuedMessage = ""
                    sendQueueFilled = false
                }) {
                    Label(
                        title: { },
                        icon: { Image(systemName: "xmark.circle.fill").foregroundColor(Color.black) }
                    )
                }
                .opacity(sendQueueFilled ? 100 : 0)
                .padding(.horizontal)
                .disabled(!sendQueueFilled)
            }
            
            Button(action: {
                peripheralManagerDelegate.startAdvertising()
            }) {
                Text("Start advertising")
                    .fontWeight(/*@START_MENU_TOKEN@*/.bold/*@END_MENU_TOKEN@*/)
                    .padding()
                    .background(sendQueueFilled ? Color.black : Color.gray)
                    .foregroundColor(.white)
                    .cornerRadius(10)
            }
            .padding()
            .disabled(!sendQueueFilled)
            
            Divider()
                .frame(height: 2)
                .overlay(.black)
                .padding(.vertical)
            
            Text("Central")
                .font(.largeTitle)
                .fontWeight(/*@START_MENU_TOKEN@*/.bold/*@END_MENU_TOKEN@*/)
                .foregroundColor(.gray)
            
            Button(action: {
                centralManagerDelegate.startScan()
            }) {
                Text("Start scan")
                    .fontWeight(/*@START_MENU_TOKEN@*/.bold/*@END_MENU_TOKEN@*/)
                    .padding()
                    .background(Color.black)
                    .foregroundColor(.white)
                    .cornerRadius(10)
            }
            .padding()
            
            HStack {
                Text((peripheralDelegate.testMessage != nil) ? "Read queue: " : "Read queue empty")
                    .fontWeight(/*@START_MENU_TOKEN@*/.bold/*@END_MENU_TOKEN@*/)
                    .padding(.horizontal)
                Spacer()
                Text(peripheralDelegate.testMessage ?? "")
            }
        }
        Spacer()
        
    }
}

#Preview {
    ContentView()
}
