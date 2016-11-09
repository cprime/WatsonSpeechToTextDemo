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
//      - Start/stop transcription service
//      - TODO: Mananage audio session
//      - TODO: Play tones
//      - TODO: Convert transcription results into SpeechToTextResult struct
//      - TODO: Handle session interruptions
//      - Handle errors

import Foundation
import AVFoundation
import Intrepid

class WatsonSpeechToTextController: SpeechToTextController {
    typealias InterimResultsCallback = SpeechTranscription -> Void
    typealias InterruptionCallback = ErrorType -> Void
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
        case Transcribing(session: SpeechToTextSession, audioFile: AVAudioFile, interimResultsCallback: InterimResultsCallback?, interruptionCallback: InterruptionCallback?, hasConnected: Bool)
        case FailingTranscription(session: SpeechToTextSession, error: ErrorType, interruptionCallback: InterruptionCallback?)
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
            case .Transcribing(let session, _, _, _, _):
                return session
            default:
                return nil
            }
        }

        var audioFile: AVAudioFile? {
            switch self {
            case .Transcribing(_, let audioFile, _, _, _):
                return audioFile
            default:
                return nil
            }
        }
    }
    var state = State.Idle {
        didSet(oldValue) {
            print(oldValue, " -> ", state)
        }
    }

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
        setCallbacks(withSession: speechToTextSession)
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
                                                   interruptionCallback: InterruptionCallback?) throws {
        guard state.isIdle else { throw Error.Busy }

        let audioFile = try createAudioFile()
        print(audioFile.url)

        let recognitionSettings = createRecognitionSettings(withKeywords: keywords)
        let speechToTextSession = createSpeechToTextSession(audioFile)

        speechToTextSession.connect()
        speechToTextSession.startRequest(recognitionSettings)
        speechToTextSession.startMicrophone(false)

        state = .Transcribing(session: speechToTextSession, audioFile: audioFile, interimResultsCallback: interimResultsCallback, interruptionCallback: interruptionCallback, hasConnected: false)
    }

    func stopTranscribingAudioStream(completion: CompletionCallback) throws {
        guard state.isTranscribing else { throw Error.Busy }
        guard let speechToTextSession = state.session else { throw Error.Busy }
        guard let audioFile = state.audioFile else { throw Error.Busy }

        state = .FinishingTranscription(session: speechToTextSession, audioFile: audioFile, completion: completion)

        speechToTextSession.stopMicrophone()
        speechToTextSession.stopRequest()
        speechToTextSession.disconnect()
    }

    // MARK: Session Callbacks

    private func setCallbacks(withSession session: SpeechToTextSession) {
        session.onConnect = handleOnConnectEvent
        session.onDisconnect = handleOnDisconnectEvent
        session.onError = handleOnErrorEvent
        session.onMicrophoneData = handleOnMicrophoneDataEvent
        session.onResults = handleOnResultsEvent
    }

    private func clearCallbacks(withSession session: SpeechToTextSession) {
        session.onConnect = nil
        session.onDisconnect = nil
        session.onError = nil
        session.onMicrophoneData = nil
        session.onResults = nil
    }

    private func handleOnConnectEvent() {
        print("connected")
        switch state {
        case .Transcribing(let session, let audioFile, let interimResultsCallback, let interruptionCallback, _):
            state = .Transcribing(
                session: session,
                audioFile: audioFile,
                interimResultsCallback: interimResultsCallback,
                interruptionCallback: interruptionCallback,
                hasConnected: true
            )
        default:
            break
        }
    }

    private func handleOnMicrophoneDataEvent(data: NSData) {
        Qu.Main { [weak self] in
            guard let strongSelf = self else { return }
            guard let audioFile = strongSelf.state.audioFile else { return }
            let success = strongSelf.write(data, audioFile: audioFile)
            print("writeSucces:", success, data.length)
        }
    }

    private func handleOnResultsEvent(results: SpeechRecognitionResults) {
        Qu.Main { [weak self] in
            guard let strongSelf = self else { return }

            switch strongSelf.state {
            case .Transcribing(_, _, let interimResultsCallback, _, _):
                if let interimResultsCallback = interimResultsCallback {
                    let transcription = SpeechTranscription(watsonSpeechRecognitionResults: results)
                    interimResultsCallback(transcription)
                }
            default:
                break
            }
        }
    }

    private func handleOnErrorEvent(error: NSError) {
        switch state {
        case .Transcribing(let session, _, _, let interruptionCallback, let hasConnected):
            state = .FailingTranscription(session: session, error: error, interruptionCallback: interruptionCallback)

            session.stopMicrophone()
            session.stopRequest()
            if hasConnected {
                session.disconnect()
            } else {
                failTranscription()
            }
        default:
            break
        }
    }

    private func handleOnDisconnectEvent() {
        switch state {
        case .FailingTranscription(_, _, _):
            failTranscription()
        case .FinishingTranscription(let session, let audioFile, let completion):
            clearCallbacks(withSession: session)
            if !session.results.results.isEmpty {
                let transcription = SpeechTranscription(watsonSpeechRecognitionResults: session.results)
                completion(.Success(SpeechToTextResult(transcription: transcription, recordingURL: audioFile.url)))
            } else {
                completion(.Failure(NSError(domain: "", code: 0, userInfo: nil)))
            }
            state = .Idle
        default:
            break
        }
    }

    // MARK: Helpers

    private func failTranscription() {
        switch state {
        case .FailingTranscription(let session, let error, let interruptionCallback):
            clearCallbacks(withSession: session)
            interruptionCallback?(error)
            state = .Idle
        default:
            break
        }
    }

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
