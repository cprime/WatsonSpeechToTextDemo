//
//  VoiceRecorder.swift
//  bose-scribe
//
//  Created by Colden Prime on 8/12/16.
//  Copyright © 2016 Intrepid Pursuits LLC. All rights reserved.
//

import AVFoundation
import Foundation
import Intrepid

protocol AudioManagerType {
    func recordPermission() -> AVAudioSessionRecordPermission
    func hasRequestedRecordPermission() -> Bool
    func hasRecordPermission() -> Bool
    func requestRecordingPermission(withCompletion completion: (Bool) -> Void)

    func startRecording(tapBlock: AVAudioNodeTapBlock?, interruptedCallback: ((ErrorType?) -> Void)?) throws
    func stopRecording() throws -> NSURL
    func startPlayingAudio(fileURL: NSURL, completion: ((ErrorType?) -> Void)?) throws
    func stopPlayingAudio()
    func toggleSessionActive(active: Bool) throws
}

// MARK: AudioManager.State Equatable

func ==(lhs: AudioManager.State, rhs: AudioManager.State) -> Bool {
    switch (lhs, rhs) {
    case (.Idle, .Idle), (.Recording(_), .Recording(_)), (.Playing(_), .Playing(_)):
        return true
    default:
        return false
    }
}

class AudioManager: NSObject, AudioManagerType, AVAudioSessionDelegate, AVAudioPlayerDelegate {
    static let audioBus = 0

    typealias InterruptedCallback = (ErrorType?) -> Void
    typealias PlaybackCompletion = (ErrorType?) -> Void

    enum AudioError: ErrorType {
        case Unauthorized
        case Busy
        case RecordingFailed
        case RecordingInterrupted
        case PlaybackFailed
        case PlaybackInterrupted
    }

    enum State: Equatable {
        case Idle
        case PreparingToRecord(interruptedCallback: InterruptedCallback?)
        case Recording(audioFile: AVAudioFile, interruptedCallback: InterruptedCallback?)
        case Playing(playbackCompletion: PlaybackCompletion?)

        var isIdle: Bool {
            get {
                switch self {
                case Idle:
                    return true
                default:
                    return false
                }
            }
        }

        var isPreparingToRecord: Bool {
            get {
                switch self {
                case .PreparingToRecord:
                    return true
                default:
                    return false
                }
            }
        }

        var isRecording: Bool {
            get {
                switch self {
                case .Recording(_):
                    return true
                default:
                    return false
                }
            }
        }

        var isPlaying: Bool {
            get {
                switch self {
                case .Playing(_):
                    return true
                default:
                    return false
                }
            }
        }

        var interruptedCallback: InterruptedCallback? {
            switch self {
            case .PreparingToRecord(let interruptedCallback):
                return interruptedCallback
            case .Recording(_, let interruptedCallback):
                return interruptedCallback
            default:
                return nil
            }
        }

        var playbackCompletion: PlaybackCompletion? {
            get {
                switch self {
                case .Playing(let completion):
                    return completion
                default:
                    return nil
                }
            }
        }
    }

    private(set) var state = State.Idle {
        didSet {
            guard oldValue != state else { return }
            _ = try? toggleSessionActive(state == .Idle ? false : true)
        }
    }

    static let sharedInstance = AudioManager()

    private var recordingFileURL: NSURL = NSURL(fileURLWithPath: "\(NSFileManager.documentPath)/Voice_Recording.caf")

    private var audioEngine = AVAudioEngine()
    private var audioPlayer: AVAudioPlayer?
    private var tonePlayers = [AVAudioPlayer]()

    private override init() {
        super.init()
        registerForNotifications()
    }

    deinit {
        unregisterForNotifications()
    }

    private func generateUniqueFileURL() -> NSURL {
        return NSURL(fileURLWithPath: "\(NSFileManager.documentPath)/Voice_Recording_\(NSUUID().UUIDString).caf")
    }

    func setupSession() {
        do {
            UIApplication.sharedApplication().beginReceivingRemoteControlEvents()
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(AVAudioSessionCategoryPlayAndRecord,
                                    withOptions: [.AllowBluetooth, .DefaultToSpeaker])
            let bluetoothHFP = session.availableInputs?.filter({ $0.portType == AVAudioSessionPortBluetoothHFP }).first
            try session.setPreferredInput(bluetoothHFP)
        } catch let e {
            print(e)
        }
    }

    func toggleSessionActive(active: Bool) throws {
        do {
            try AVAudioSession.sharedInstance().setActive(active, withOptions: .NotifyOthersOnDeactivation)
        } catch let e {
            print(e)
            throw e
        }
    }

    // MARK: - Authorization

    func recordPermission() -> AVAudioSessionRecordPermission {
        return AVAudioSession.sharedInstance().recordPermission()
    }

    func hasRequestedRecordPermission() -> Bool {
        return self.recordPermission() != .Undetermined
    }

    func hasRecordPermission() -> Bool {
        return self.recordPermission() == .Granted
    }

    func requestRecordingPermission(withCompletion completion: (Bool) -> Void) {
        AVAudioSession.sharedInstance().requestRecordPermission { recordPermissionGranted in
            Qu.Main {
                completion(recordPermissionGranted)
            }
        }
    }

    // MARK: - Controls

    func startRecording(tapBlock: AVAudioNodeTapBlock?, interruptedCallback: InterruptedCallback?) throws {
        guard AudioManager.sharedInstance.hasRecordPermission() else { throw AudioError.Unauthorized}
        guard state.isIdle else { throw AudioError.Busy }

        state = .PreparingToRecord(interruptedCallback: interruptedCallback)

        do {
            guard let inputNode = audioEngine.inputNode else { throw AudioError.RecordingFailed }
            let audioFile = try AVAudioFile(forWriting: recordingFileURL, settings: inputNode.inputFormatForBus(AudioManager.audioBus).settings)

            let recordingFormat = inputNode.inputFormatForBus(AudioManager.audioBus)
            inputNode.installTapOnBus(AudioManager.audioBus, bufferSize: 1024, format: recordingFormat) { (buffer: AVAudioPCMBuffer, when: AVAudioTime) in
                _ = try? audioFile.writeFromBuffer(buffer)
                tapBlock?(buffer, when)
            }

            try audioEngine.start()

            state = .Recording(audioFile: audioFile, interruptedCallback: interruptedCallback)
        } catch let e {
            print(e)
            finishRecording()
            throw AudioError.RecordingFailed
        }
    }

    func stopRecording() throws -> NSURL {
        guard AudioManager.sharedInstance.hasRecordPermission() else { throw AudioError.Unauthorized }

        var tempFile: AVAudioFile?
        switch state {
        case .Recording(let file, _):
            tempFile = file
        default:
            break
        }
        guard let audioFile = tempFile else { throw AudioError.Busy }

        do {
            finishRecording()

            let fileManager = NSFileManager.defaultManager()
            let finalFileURL = generateUniqueFileURL()
            try fileManager.moveItemAtURL(audioFile.url, toURL: finalFileURL)

            return finalFileURL
        } catch let e {
            print(e)
            throw AudioError.RecordingFailed
        }
    }

    func startPlayingAudio(fileURL: NSURL, completion: PlaybackCompletion?) throws {
        guard state.isIdle else { throw AudioError.Busy }

        state = .Playing(playbackCompletion: completion)
        do {
            audioPlayer = try AVAudioPlayer(contentsOfURL: fileURL)
            audioPlayer?.delegate = self
            audioPlayer?.play()
        } catch {
            state = .Idle
            throw AudioError.PlaybackFailed
        }
    }

    func stopPlayingAudio() {
        guard state.isPlaying else { return }
        audioPlayer?.stop()
        state = .Idle
    }

    // MARK: - Cleanup

    private func finishRecording() {
        audioEngine.stop()
        audioEngine.inputNode?.removeTapOnBus(AudioManager.audioBus)
        audioEngine.reset()
        After(1.0) {
            // either recorder.stop() or playing the StopRecording tone seems to need a second to finish
            self.state = .Idle
        }
    }

    // MARK: - Notifications

    private func registerForNotifications() {
        NSNotificationCenter.defaultCenter().addObserver(self,
                                                         selector: #selector(AudioManager.handleAudioSessionInterruptionNotification),
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
        case .Idle:
            break
        case .PreparingToRecord(_), .Recording(_):
            let interruptedCallback = state.interruptedCallback
            finishRecording()
            Qu.Main {
                interruptedCallback?(AudioError.RecordingInterrupted)
            }
        case .Playing(let playbackCompletion):
            audioPlayer?.stop()
            audioPlayer = nil
            state = .Idle
            Qu.Main {
                playbackCompletion?(AudioError.PlaybackInterrupted)
            }
        }
    }

    // MARK: - AVAudioPlayerDelegate

    @objc func audioPlayerDidFinishPlaying(player: AVAudioPlayer, successfully flag: Bool) {
        if player == audioPlayer {
            guard state.isPlaying else { return }

            let completion = state.playbackCompletion
            state = .Idle
            audioPlayer = nil
            completion?(nil)
        } else if let i = tonePlayers.indexOf(player) {
            tonePlayers.removeAtIndex(i)
        }
    }

}
