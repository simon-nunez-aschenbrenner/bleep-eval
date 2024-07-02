//
//  Utils.swift
//  bleep-eval
//
//  Created by Simon Núñez Aschenbrenner on 13.06.24.
//

import CoreBluetooth
import Foundation
import OSLog

enum BleepError: Error {
    
    case invalidControlByteValue, invalidAddress, missingDestination
}

extension Logger {
    
    private static var subsystem = Bundle.main.bundleIdentifier!
    static let view = Logger(subsystem: subsystem, category: "view")
    static let evaluation = Logger(subsystem: subsystem, category: "evaluation")
    static let notification = Logger(subsystem: subsystem, category: "notification")
    static let bluetooth = Logger(subsystem: subsystem, category: "bluetooth")
    static let peripheral = Logger(subsystem: subsystem, category: "peripheral")
    static let central = Logger(subsystem: subsystem, category: "central")
}

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
    static let shadowRadius: CGFloat = 15.0
    static let textEditorWidthOffset: CGFloat = 2 * lineWidth + 2 * largePadding + mediumPadding + 3 * smallPadding + sendButtonSize
}

struct Utils {
    
    static let addressBook: [Address] = [
        Address("XVQ6uh5nTLN", name: "Simon")!,
        Address("3NHph2xbJS4", name: "A")!,
        Address("36BP1FRmt8N", name: "B")!,
        Address("Mm79DuurhxB", name: "D")!
    ]

    static let suffixLength: Int = 5
    static let initialNumberOfCopies: UInt8 = 15
    static let initialCountdownTime = 10
    
    static func generateText(with length: Int, testPattern: Bool = true) -> String {
        var end = " // This test message contains \(length) ASCII characters"
        if testPattern {
            end += ". The last visible digit indicates the number of characters missing: 9876543210"
        }
        var result = ""
        if end.count > length {
            result = String(end.suffix(length))
        } else {
            for _ in 0..<length - end.count {
                result.append(Character(Unicode.Scalar(UInt8.random(in: 21...126))))
            }
            result.append(end)
        }
        assert(result.count == length)
        return result
    }
    
    static func printID(_ data: Data?) -> String {
        return printID(data?.map { String($0) }.joined() ?? "")
    }
    
    static func printID(_ int: UInt64) -> String {
        return printID(String(int))
    }
    
    static func printID(_ string: String?) -> String {
        return String(string?.suffix(suffixLength) ?? "")
    }
    
    static func printTimestamp(_ date: Date) -> String {
        return String(date.description.dropLast(6))
    }
}
