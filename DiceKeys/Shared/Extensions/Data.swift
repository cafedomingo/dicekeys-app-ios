//
//  Data.swift
//  DiceKeys
//
//  Created by Stuart Schechter on 2021/02/08.
//

import Foundation

extension Data {
    // a hex string encoding of the data (no prefix such as "0x".  Add it if you want it.)
    var asHexString: String {
        self.reduce("") { $0 + String(format: "%02x", $1) }
    }
}
