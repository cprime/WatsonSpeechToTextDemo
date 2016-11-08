//
//  NSFileManagerExtension.swift
//  bose-scribe
//
//  Created by Colden Prime on 9/28/16.
//  Copyright © 2016 Intrepid Pursuits LLC. All rights reserved.
//

import Foundation

extension NSFileManager {
    static var documentPath: String {
        get {
            return NSSearchPathForDirectoriesInDomains(.DocumentDirectory,
                                                       .UserDomainMask, true)[0]
        }
    }

    static var temporaryPath: String {
        get {
            return NSTemporaryDirectory()
        }
    }
}
