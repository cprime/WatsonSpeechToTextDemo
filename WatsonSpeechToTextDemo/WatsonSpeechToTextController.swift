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
//      - Handle session interruptions
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
        case SessionInterruption
    }

    enum State {
        case Idle
        case Transcribing(session: SpeechToTextSession, audioFile: AVAudioFile, interimResultsCallback: InterimResultsCallback?, interruptionCallback: InterruptionCallback?)
        case FailingTranscription(session: SpeechToTextSession, error: ErrorType, interruptionCallback: InterruptionCallback?)
        case FinishingTranscription(session: SpeechToTextSession, audioFile: AVAudioFile, completion: CompletionCallback)
    }
    var state = State.Idle

    private static let audioSettings: [String : AnyObject] = [
        AVSampleRateKey: 16000,
        AVNumberOfChannelsKey: 1,
    ]

    // MARK: Lifecycle

    init() {
        registerForNotifications()
    }

    deinit {
        unregisterForNotifications()
    }

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
        switch state {
        case .Idle:
            let audioFile = try createAudioFile()
            let recognitionSettings = createRecognitionSettings(withKeywords: keywords)
            let speechToTextSession = createSpeechToTextSession(audioFile)

            state = .Transcribing(session: speechToTextSession, audioFile: audioFile, interimResultsCallback: interimResultsCallback, interruptionCallback: interruptionCallback)

            speechToTextSession.connect()
            speechToTextSession.startRequest(recognitionSettings)
            speechToTextSession.startMicrophone(false)
        default:
            throw Error.Busy
        }
    }

    func stopTranscribingAudioStream(completion: CompletionCallback) throws {
        switch state {
        case .Transcribing(let speechToTextSession, let audioFile, _, _):
            state = .FinishingTranscription(session: speechToTextSession, audioFile: audioFile, completion: completion)

            speechToTextSession.stopMicrophone()
            speechToTextSession.stopRequest()
            speechToTextSession.disconnect()
        default:
            throw Error.Busy
        }
    }

    // MARK: - Notifications

    private func registerForNotifications() {
        NSNotificationCenter.defaultCenter().addObserver(self,
                                                         selector: #selector(WatsonSpeechToTextController.handleAudioSessionInterruptionNotification),
                                                         name: AVAudioSessionInterruptionNotification,
                                                         object: AVAudioSession.sharedInstance())
    }

    private func unregisterForNotifications() {
        NSNotificationCenter.defaultCenter().removeObserver(self,
                                                            name: AVAudioSessionInterruptionNotification,
                                                            object: AVAudioSession.sharedInstance())
    }

    @objc private func handleAudioSessionInterruptionNotification(notification: NSNotification) {
        guard notification.name == AVAudioSessionInterruptionNotification else { return }
        guard let value = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
            let interruptionType = AVAudioSessionInterruptionType(rawValue: value) where interruptionType == .Began else { return }

        switch state {
        case .Transcribing(_, _, _, _):
            failTranscription(withError: Error.SessionInterruption)
        default:
            break
        }
    }

    // MARK: Session Callbacks

    private func setCallbacks(withSession session: SpeechToTextSession) {
        session.onDisconnect = handleOnDisconnectEvent
        session.onError = handleOnErrorEvent
        session.onMicrophoneData = handleOnMicrophoneDataEvent
        session.onResults = handleOnResultsEvent
    }

    private func clearCallbacks(withSession session: SpeechToTextSession) {
        session.onDisconnect = nil
        session.onError = nil
        session.onMicrophoneData = nil
        session.onResults = nil
    }

    private func handleOnMicrophoneDataEvent(data: NSData) {
        Qu.Main { [weak self] in
            guard let strongSelf = self else { return }

            switch strongSelf.state {
            case .Transcribing(_, let audioFile, _, _):
                do {
                    try strongSelf.write(data, audioFile: audioFile)
                } catch let error {
                    strongSelf.failTranscription(withError: error)
                }
            default:
                break
            }
        }
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

    private func handleOnErrorEvent(error: NSError) {
        switch state {
        case .Transcribing(_, _, _, _):
            failTranscription(withError: error)
        default:
            break
        }
    }

    private func handleOnDisconnectEvent() {
        switch state {
        case .FailingTranscription(_, _, _):
            finishFailingTranscription()
        case .FinishingTranscription(let session, let audioFile, let completion):
            clearCallbacks(withSession: session)
            state = .Idle
            let transcription = session.results.results.isEmpty ? SpeechTranscription.emptyTranscription : SpeechTranscription(watsonSpeechRecognitionResults: session.results)
            let speechToTextResult = SpeechToTextResult(transcription: transcription, recordingURL: audioFile.url)
            completion(.Success(speechToTextResult))
        default:
            break
        }
    }

    // MARK: Helpers

    private func failTranscription(withError error: ErrorType) {
        switch state {
        case .Transcribing(let session, _, _, let interruptionCallback):
            state = .FailingTranscription(session: session, error: error, interruptionCallback: interruptionCallback)

            session.stopMicrophone()
            session.stopRequest()
            session.disconnect()

            finishFailingTranscription()
        default:
            fatalError("Should only fail a transcription that is active")
        }
    }

    private func finishFailingTranscription() {
        switch state {
        case .FailingTranscription(let session, let error, let interruptionCallback):
            clearCallbacks(withSession: session)
            state = .Idle
            interruptionCallback?(error)
        default:
            fatalError("Should only finish a transcription as failing if it is already failing")
        }
    }

    private func generateUniqueFileURL() -> NSURL {
        let temporaryPathURL = NSURL(fileURLWithPath: NSFileManager.temporaryPath)
        return temporaryPathURL.URLByAppendingPathComponent("Voice_Recording_\(NSUUID().UUIDString).caf")!
    }

    private func write(data: NSData, audioFile: AVAudioFile) throws {
        let audioFormat = audioFile.fileFormat
        let PCMBuffer = AVAudioPCMBuffer(PCMFormat: audioFormat, frameCapacity: UInt32(data.length) / audioFormat.streamDescription.memory.mBytesPerFrame)
        PCMBuffer.frameLength = PCMBuffer.frameCapacity
        let channels = UnsafeBufferPointer(start: PCMBuffer.int16ChannelData, count: Int(PCMBuffer.format.channelCount))
        data.getBytes(UnsafeMutablePointer<Void>(channels[0]) , length: data.length)

        try audioFile.writeFromBuffer(PCMBuffer)
    }
}

private extension SpeechTranscription {
    init(watsonSpeechRecognitionResults results: SpeechRecognitionResults) {
        transcript = results.bestTranscript
        wordTimestamps = [] // TODO
    }
}
