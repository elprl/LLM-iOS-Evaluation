//
//  Item.swift
//  TaskManager
//
//  Created by Paul Leo on 16/08/2026.
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
