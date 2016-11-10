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
//      - Convert transcription results into SpeechToTextResult struct
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
        case Transcribing(session: SpeechToTextSession, keywords: [String], audioFile: AVAudioFile, interimResultsCallback: InterimResultsCallback?, interruptionCallback: InterruptionCallback?)
        case FinishingTranscription(session: SpeechToTextSession, keywords: [String], audioFile: AVAudioFile, completion: CompletionCallback)
        case FailingTranscription(session: SpeechToTextSession, error: ErrorType, interruptionCallback: InterruptionCallback?)
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
        settings.keywordsThreshold = 0.1
        settings.timestamps = true
        settings.wordAlternativesThreshold = 0.1
        return settings
    }

    // MARK: SpeechToTextController

    func startTranscribingAudioStream(withKeywords keywords: [String],
                                                   interimResultsCallback: InterimResultsCallback?,
                                                   interruptionCallback: InterruptionCallback?) throws {
        switch state {
        case .Idle:
            let audioFile = try createAudioFile()
            let recognitionSettings = createRecognitionSettings(withKeywords: keywords)
            let speechToTextSession = createSpeechToTextSession(audioFile)

            state = .Transcribing(session: speechToTextSession, keywords: keywords, audioFile: audioFile, interimResultsCallback: interimResultsCallback, interruptionCallback: interruptionCallback)

            speechToTextSession.connect()
            speechToTextSession.startRequest(recognitionSettings)
            speechToTextSession.startMicrophone(false)
        default:
            throw Error.Busy
        }
    }

    func stopTranscribingAudioStream(completion: CompletionCallback) throws {
        switch state {
        case .Transcribing(let speechToTextSession, let keywords, let audioFile, _, _):
            state = .FinishingTranscription(session: speechToTextSession, keywords: keywords, audioFile: audioFile, completion: completion)

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
        case .Transcribing(_, _, _, _, _):
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
            case .Transcribing(_, _, let audioFile, _, _):
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
            case .Transcribing(_, let keywords, _, let interimResultsCallback, _):
                if let interimResultsCallback = interimResultsCallback {
                    let transcription = SpeechTranscription(watsonSpeechRecognitionResults: results, keywords: keywords)
                    interimResultsCallback(transcription)
                }
            default:
                break
            }
        }
    }

    private func handleOnErrorEvent(error: NSError) {
        switch state {
        case .Transcribing(_, _, _, _, _):
            failTranscription(withError: error)
        default:
            break
        }
    }

    private func handleOnDisconnectEvent() {
        switch state {
        case .FailingTranscription(_, _, _):
            finishFailingTranscription()
        case .FinishingTranscription(let session, let keywords, let audioFile, let completion):
            clearCallbacks(withSession: session)
            state = .Idle
            let watsonResults = session.results
            let transcription = watsonResults.results.isEmpty
                ? SpeechTranscription.emptyTranscription
                : SpeechTranscription(watsonSpeechRecognitionResults: watsonResults, keywords: keywords)
            let speechToTextResult = SpeechToTextResult(transcription: transcription, recordingURL: audioFile.url)
            completion(.Success(speechToTextResult))
        default:
            break
        }
    }

    // MARK: Helpers

    private func failTranscription(withError error: ErrorType) {
        switch state {
        case .Transcribing(let session, _, _, _, let interruptionCallback):
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

extension SpeechTranscription {
    init(watsonSpeechRecognitionResults results: SpeechRecognitionResults, keywords: [String]) {
        var combinedTimestamps = [SpeechWordTimestamp]()

        for result in results.results {
            if let alternative = result.alternatives.first where alternative.timestamps?.count > 0 {
                var wordTimestamps = [SpeechWordTimestamp]()

                let sortedTimestamps = alternative.timestamps?.sort({ $0.startTime < $1.startTime }) ?? []
                wordTimestamps = sortedTimestamps.map({
                    SpeechWordTimestamp(
                        word: $0.word,
                        startOffset: NSTimeInterval($0.startTime),
                        endOffset: NSTimeInterval($0.endTime)
                    )
                })

                // Replace words with appropriate alternative key words
                let wordAlternatives = result.wordAlternatives ?? []
                wordTimestamps = wordTimestamps.map({ timestamp in
                    guard let potentialReplacements = wordAlternatives.filter({ $0.startTime == timestamp.startOffset && $0.endTime == timestamp.endOffset }).first,
                        let bestReplacement = potentialReplacements.alternatives.filter({ keywords.contains($0.word) }).sort({ $0.confidence > $1.confidence }).first else {
                            return timestamp
                    }
                    return SpeechWordTimestamp(word: bestReplacement.word, startOffset: timestamp.startOffset, endOffset: timestamp.endOffset)
                })

                combinedTimestamps.appendContentsOf(wordTimestamps)
            }
        }

        self.transcript = combinedTimestamps.map({ $0.word }).joinWithSeparator(" ")
        self.wordTimestamps = combinedTimestamps
    }
}
