//
//  ServiceKeyLoader.swift
//  WatsonSpeechToTextDemo
//
//  Created by Colden Prime on 11/4/16.
//  Copyright © 2016 IntrepidPursuits. All rights reserved.
//

import Foundation

class ServiceKeyLoader {
    static let shared = ServiceKeyLoader()

    private let keys: NSDictionary

    init(filename: String = "keys") {
        guard let url = NSBundle.mainBundle().URLForResource(filename, withExtension: "plist") else { fatalError("No file found: \(filename).plist") }
        guard let keys = NSDictionary(contentsOfURL: url) else { fatalError("\(filename).plist is not a valid plist file") }
        self.keys = keys
    }

    func stringValueForKey(key: String) -> String {
        guard let value = self.keys[key] else { fatalError("There is no value for the key: \(key)") }
        guard let stringValue = value as? String else { fatalError("The value for \(key) is not a String") }
        return stringValue
    }
}

enum Keys: String {
    case WatsonUsername = "net.bluemix.stt.username"
    case WatsonPassword = "net.bluemix.stt.password"

    var value: String {
        return ServiceKeyLoader.shared.stringValueForKey(rawValue)
    }
}
