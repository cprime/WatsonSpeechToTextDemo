//
//  WatsonSTTManager.swift
//  WatsonSpeechToTextDemo
//
//  Created by Colden Prime on 11/2/16.
//  Copyright © 2016 IntrepidPursuits. All rights reserved.
//

import Foundation
import AVFoundation
import Intrepid

class WatsonSTTManager {
    static let shared = WatsonSTTManager()

    static private(set) var username = Keys.WatsonUsername.value
    static private(set) var password = Keys.WatsonPassword.value

    let stt = SpeechToText(username: WatsonSTTManager.username, password: WatsonSTTManager.password)

    enum Error: ErrorType {
        case Busy
    }

    enum State {
        case Idle
        case Transcribing(session: SpeechToTextSession, audioFile: AVAudioFile)

        var isIdle: Bool {
            switch self {
            case .Idle:
                return true
            default:
                return false
            }
        }

        var isTranscribing: Bool {
            switch self {
            case .Transcribing:
                return true
            default:
                return false
            }
        }

        var session: SpeechToTextSession? {
            switch self {
            case .Transcribing(let session, _):
                return session
            default:
                return nil
            }
        }

        var audioFile: AVAudioFile? {
            switch self {
            case .Transcribing(_, let audioFile):
                return audioFile
            default:
                return nil
            }
        }
    }
    var state = State.Idle

    static let recordingFileURL: NSURL = NSURL(fileURLWithPath: "\(NSFileManager.documentPath)/Voice_Recording.caf")
    static let audioSettings: [String : AnyObject] = [
        AVSampleRateKey: 16000,
        AVNumberOfChannelsKey: 1,
    ]

    func startTranscribing(onResults: (SpeechRecognitionResults -> Void)?) throws {
        guard state.isIdle else { throw Error.Busy }


        let audioFile = try AVAudioFile(
            forWriting: WatsonSTTManager.recordingFileURL,
            settings: WatsonSTTManager.audioSettings,
            commonFormat: .PCMFormatInt16,
            interleaved: true
        )
        let speechToTextSession = SpeechToTextSession(username: WatsonSTTManager.username, password: WatsonSTTManager.password)

        // define callbacks
        speechToTextSession.onConnect = { print("connected") }
        speechToTextSession.onDisconnect = { print("disconnected") }
        speechToTextSession.onError = { error in print(error) }
        speechToTextSession.onPowerData = { decibels in print(decibels) }
        speechToTextSession.onMicrophoneData = { data in
            Qu.Main {
                let success = self.write(data, audioFile: audioFile)
                print("writeSucces:", success, data.length)
            }
        }
        speechToTextSession.onResults = { results in
            onResults?(results)
        }

        // define recognition request settings
        var settings = RecognitionSettings(contentType: .L16(rate: 16000, channels: 1))
        settings.interimResults = true
        settings.continuous = true

        // start streaming microphone audio for transcription
        speechToTextSession.connect()
        speechToTextSession.startRequest(settings)
        speechToTextSession.startMicrophone(false)

        state = .Transcribing(session: speechToTextSession, audioFile: audioFile)
    }

    func stopTranscribing() throws {
        guard state.isTranscribing else { throw Error.Busy }
        guard let speechToTextSession = state.session else { throw Error.Busy }
        guard let audioFile = state.audioFile else { throw Error.Busy }

        speechToTextSession.stopMicrophone()
        speechToTextSession.stopRequest()
        speechToTextSession.disconnect()

        let fileManager = NSFileManager.defaultManager()
        let finalFileURL = generateUniqueFileURL()
        try fileManager.moveItemAtURL(audioFile.url, toURL: finalFileURL)
        print(finalFileURL)

        state = .Idle
    }

    // MARK: Helpers

    private func generateUniqueFileURL() -> NSURL {
        return NSURL(fileURLWithPath: "\(NSFileManager.documentPath)/Voice_Recording_\(NSUUID().UUIDString).caf")
    }

    func write(data: NSData, audioFile: AVAudioFile) -> Bool {
        let audioFormat = audioFile.fileFormat
        let PCMBuffer = AVAudioPCMBuffer(PCMFormat: audioFormat, frameCapacity: UInt32(data.length) / audioFormat.streamDescription.memory.mBytesPerFrame)
        PCMBuffer.frameLength = PCMBuffer.frameCapacity
        let channels = UnsafeBufferPointer(start: PCMBuffer.int16ChannelData, count: Int(PCMBuffer.format.channelCount))
        data.getBytes(UnsafeMutablePointer<Void>(channels[0]) , length: data.length)

        do {
            try audioFile.writeFromBuffer(PCMBuffer)
            return true
        } catch let error {
            print("error: ", error)
            return false
        }
    }
}
