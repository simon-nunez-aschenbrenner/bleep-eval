//
//  MainView.swift
//  bleep-eval
//
//  Created by Simon Núñez Aschenbrenner on 03.05.24.
//

import Foundation
import OSLog
import SwiftUI

struct MainView: View {
    
    @Environment(BleepManager.self) var notificationManager: BleepManager
    @State private var showAutoView: Bool = true
    private let columns = [GridItem(.flexible()), GridItem(.flexible())]
    
    
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
                        if notificationManager.type != type {
                            notificationManager.type = type
                        }
                    }) {
                        Text(type.description.suffix(14))
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, minHeight: Dimensions.singleLineHeight)
                            .font(.custom(Font.BHTCaseMicro.Bold, size: Font.Size.Text))
                            .background(type == notificationManager.type ? Color("bleepPrimary") : Color("bleepSecondary"))
                            .foregroundColor(Color("bleepPrimaryOnPrimaryBackground"))
                            .cornerRadius(Dimensions.cornerRadius)
                        }
                    }
                }
                .padding(.horizontal)
            
            // MARK: Status
            
            HStack {
                Spacer()
                Text("I am \(notificationManager.address.description.dropLast(6))")
                    .font(.custom(Font.BHTCaseText.Regular, size: Font.Size.Text))
                    .foregroundColor(Color("bleepPrimary"))
                    .padding(.vertical, Dimensions.largePadding)
                Spacer()
            }
            
            if showAutoView {
                SimulationView(notificationManager)
            } else {
                ManualView(notificationManager)
            }
        }
        .dynamicTypeSize(DynamicTypeSize.large...DynamicTypeSize.large)
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
    MainView()
}
