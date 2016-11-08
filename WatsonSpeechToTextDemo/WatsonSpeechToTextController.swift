//
//  WatsonSpeechToTextController.swift
//  WatsonSpeechToTextDemo
//
//  Created by Colden Prime on 11/2/16.
//  Copyright © 2016 IntrepidPursuits. All rights reserved.
//
//  Responsibilies:
//      - Turn on/off microphone
//      - Record audio to file
//      - Mananage audio session
//      - Play tones
//      - Start/stop transcription service
//      - Convert transcription results into SpeechToTextResult struct
//      - Handle interuptions

import Foundation
import AVFoundation
import Intrepid

class WatsonSpeechToTextController: SpeechToTextController {
    typealias InterimResultsCallback = SpeechTranscription -> Void
    typealias InteruptionCallback = ErrorType -> Void
    typealias CompletionCallback = Result<SpeechToTextResult> -> Void

    static let shared = WatsonSpeechToTextController()

    private static var username = Keys.WatsonUsername.value
    private static var password = Keys.WatsonPassword.value

    private let stt = SpeechToText(username: WatsonSpeechToTextController.username, password: WatsonSpeechToTextController.password)

    enum Error: ErrorType {
        case Busy
    }

    enum State {
        case Idle
        case Transcribing(session: SpeechToTextSession, audioFile: AVAudioFile, interimResultsCallback: InterimResultsCallback?, interuptionCallback: InteruptionCallback?)
        case FinishingTranscription(session: SpeechToTextSession, audioFile: AVAudioFile, completion: CompletionCallback)

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
            case .Transcribing(let session, _, _, _):
                return session
            default:
                return nil
            }
        }

        var audioFile: AVAudioFile? {
            switch self {
            case .Transcribing(_, let audioFile, _, _):
                return audioFile
            default:
                return nil
            }
        }
    }
    var state = State.Idle

    private static let audioSettings: [String : AnyObject] = [
        AVSampleRateKey: 16000,
        AVNumberOfChannelsKey: 1,
    ]

    // MARK: Constructors

    private func createAudioFile() throws -> AVAudioFile {
        return try AVAudioFile(
            forWriting: generateUniqueFileURL(),
            settings: WatsonSpeechToTextController.audioSettings,
            commonFormat: .PCMFormatInt16,
            interleaved: true
        )
    }

    private func createSpeechToTextSession(audioFile: AVAudioFile) -> SpeechToTextSession {
        let speechToTextSession = SpeechToTextSession(username: WatsonSpeechToTextController.username, password: WatsonSpeechToTextController.password)

        // define callbacks
        speechToTextSession.onConnect = handleOnConnectEvent
        speechToTextSession.onDisconnect = handleOnDisconnectEvent
        speechToTextSession.onPowerData = handleOnPowerDataEvent
        speechToTextSession.onError = handleOnErrorEvent
        speechToTextSession.onMicrophoneData = handleOnMicrophoneDataEvent
        speechToTextSession.onResults = handleOnResultsEvent

        return speechToTextSession
    }

    private func createRecognitionSettings(withKeywords keywords: [String]?) -> RecognitionSettings {
        var settings = RecognitionSettings(contentType: .L16(rate: 16000, channels: 1))
        settings.interimResults = true
        settings.continuous = true
        settings.keywords = keywords
        return settings
    }

    // MARK: SpeechToTextController

    func startTranscribingAudioStream(withKeywords keywords: [String]?,
                                                   interimResultsCallback: InterimResultsCallback?,
                                                   interuptionCallback: InteruptionCallback?) throws {
        guard state.isIdle else { throw Error.Busy }

        let audioFile = try createAudioFile()
        print(audioFile.url)

        let recognitionSettings = createRecognitionSettings(withKeywords: keywords)
        let speechToTextSession = createSpeechToTextSession(audioFile)

        speechToTextSession.connect()
        speechToTextSession.startRequest(recognitionSettings)
        speechToTextSession.startMicrophone(false)

        state = .Transcribing(session: speechToTextSession, audioFile: audioFile, interimResultsCallback: interimResultsCallback, interuptionCallback: interuptionCallback)
    }

    func stopTranscribingAudioStream(completion: CompletionCallback) throws {
        guard state.isTranscribing else { throw Error.Busy }
        guard let speechToTextSession = state.session else { throw Error.Busy }
        guard let audioFile = state.audioFile else { throw Error.Busy }

        state = .FinishingTranscription(session: speechToTextSession, audioFile: audioFile, completion: completion)

        speechToTextSession.stopMicrophone()
        speechToTextSession.stopRequest()
        speechToTextSession.disconnect()

        After(0.5) {
            if !speechToTextSession.results.results.isEmpty {
                let transcription = SpeechTranscription(watsonSpeechRecognitionResults: speechToTextSession.results)
                completion(.Success(SpeechToTextResult(transcription: transcription, recordingURL: audioFile.url)))
            } else {
                completion(.Failure(NSError(domain: "", code: 0, userInfo: nil)))
            }
            self.state = .Idle
        }
    }

    // MARK: Session Callbacks

    //    var onConnect: (Void -> Void)?
    private func handleOnConnectEvent() {
        print("connected")
    }

    private func handleOnMicrophoneDataEvent(data: NSData) {
        Qu.Main { [weak self] in
            guard let strongSelf = self else { return }
            guard let audioFile = strongSelf.state.audioFile else { return }
            let success = strongSelf.write(data, audioFile: audioFile)
            print("writeSucces:", success, data.length)
        }
    }

    private func handleOnPowerDataEvent(decibels: Float32) {
        print(decibels)
    }

    private func handleOnResultsEvent(results: SpeechRecognitionResults) {
        Qu.Main { [weak self] in
            guard let strongSelf = self else { return }

            switch strongSelf.state {
            case .Transcribing(_, _, let interimResultsCallback, _):
                if let interimResultsCallback = interimResultsCallback {
                    let transcription = SpeechTranscription(watsonSpeechRecognitionResults: results)
                    interimResultsCallback(transcription)
                }
            default:
                break
            }
        }
    }

    //    var onError: (NSError -> Void)?
    private func handleOnErrorEvent(error: NSError) {
        print(error)
    }

    //    var onDisconnect: (Void -> Void)?
    private func handleOnDisconnectEvent() {
        print("disconnected")
    }

    // MARK: Helpers

    private func generateUniqueFileURL() -> NSURL {
        let temporaryPathURL = NSURL(fileURLWithPath: NSFileManager.temporaryPath)
        return temporaryPathURL.URLByAppendingPathComponent("Voice_Recording_\(NSUUID().UUIDString).caf")!
    }

    private func write(data: NSData, audioFile: AVAudioFile) -> Bool {
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

private extension SpeechTranscription {
    init(watsonSpeechRecognitionResults results: SpeechRecognitionResults) {
        transcript = results.bestTranscript
        wordTimestamps = [] // TODO
    }
}
