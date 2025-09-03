//
//  Item.swift
//  Navigation App
//
//  Created by Yoshiki Osuka on 2025/09/04.
//

import Foundation
import SwiftData

@Model
final class Item {
    var timestamp: Date
    
    init(timestamp: Date) {
        self.timestamp = timestamp
    }
}
