//
//  SpeechToTextController.swift
//  WatsonSpeechToTextDemo
//
//  Created by Colden Prime on 11/4/16.
//  Copyright © 2016 IntrepidPursuits. All rights reserved.
//

import Foundation
import Intrepid

func ==(lhs: SpeechWordTimestamp, rhs: SpeechWordTimestamp) -> Bool {
    return (lhs.word == rhs.word && lhs.startOffset == rhs.startOffset && lhs.endOffset == rhs.endOffset)
}

func ==(lhs: SpeechTranscription, rhs: SpeechTranscription) -> Bool {
    return (lhs.transcript == rhs.transcript && lhs.wordTimestamps == rhs.wordTimestamps)
}

func ==(lhs: SpeechToTextResult, rhs: SpeechToTextResult) -> Bool {
    return (lhs.transcription == rhs.transcription && lhs.recordingURL == rhs.recordingURL)
}

struct SpeechWordTimestamp: Equatable {
    var word: String
    var startOffset: NSTimeInterval
    var endOffset: NSTimeInterval
}

struct SpeechTranscription: Equatable {
    var transcript: String
    var wordTimestamps: [SpeechWordTimestamp]

    static var emptyTranscription: SpeechTranscription {
        return SpeechTranscription(transcript: "", wordTimestamps: [])
    }
}

struct SpeechToTextResult: Equatable {
    var transcription: SpeechTranscription
    var recordingURL: NSURL
}

protocol SpeechToTextController {
    func startTranscribingAudioStream(withKeywords keywords: [String],
                                                   interimResultsCallback: (SpeechTranscription -> Void)?,
                                                   interruptionCallback: (ErrorType -> Void)?) throws
    func stopTranscribingAudioStream(completion: (Result<SpeechToTextResult> -> Void)) throws
}
