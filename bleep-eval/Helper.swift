//
//  Helper.swift
//  bleep-eval
//
//  Created by Simon Núñez Aschenbrenner on 13.06.24.
//

import Foundation

let suffixLength = 5

func printID(_ data: Data?) -> String {
    return printID(data?.map { String($0) }.joined() ?? "")
}

func printID(_ int: UInt64) -> String {
    return printID(String(int))
}

func printID(_ string: String?) -> String {
    return String(string?.suffix(suffixLength) ?? "")
}

func printData(_ data: Data?) -> String {
    // return data.map { String($0) }.joined()
    return data?.base64EncodedString() ?? ""
}
