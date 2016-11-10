//
//  ViewController.swift
//  WatsonSpeechToTextDemo
//
//  Created by Colden Prime on 11/1/16.
//  Copyright © 2016 IntrepidPursuits. All rights reserved.
//

import UIKit

class ViewController: UIViewController {
    @IBOutlet weak var startRecordingButton: UIButton!
    @IBOutlet weak var stopRecordingButton: UIButton!
    @IBOutlet weak var transcriptTextView: UITextView!

    let speechToTextController: SpeechToTextController = WatsonSpeechToTextController.shared

    var isTranscribing: Bool {
        switch WatsonSpeechToTextController.shared.state {
        case .Idle:
            return false
        default:
            return true
        }
    }

    var keywords = [
        "Colden",
        "Kerry",
        "Alan",
        "Tommy"
    ]

    override func viewWillAppear(animated: Bool) {
        super.viewWillAppear(animated)
        if !AudioManager.sharedInstance.hasRequestedRecordPermission() {
            AudioManager.sharedInstance.requestRecordingPermission(withCompletion: { _ in })
        }
        setupButtons()
    }

    func setupButtons() {
        startRecordingButton.enabled = !isTranscribing
        stopRecordingButton.enabled = isTranscribing
    }

    // MARK: Actions

    @IBAction func didTapStartRecording(sender: AnyObject) {
        print(#function)

        let interimResultsCallback: SpeechTranscription -> Void = { transcription in
            print("onResults:", transcription)
            self.transcriptTextView.text = transcription.transcript
        }
        let interruptionCallback: ErrorType -> Void = { error in
            print("interruption: ", error)
            self.setupButtons()
        }

        do {
            try speechToTextController.startTranscribingAudioStream(
                withKeywords: keywords,
                interimResultsCallback: interimResultsCallback,
                interruptionCallback: interruptionCallback
            )
        } catch let error {
            print("Error Starting: ", error)
        }
        setupButtons()
    }

    @IBAction func didTapStopRecording(sender: AnyObject) {
        print(#function)

        do {
            try speechToTextController.stopTranscribingAudioStream { result in
                if let result = result.value {
                    self.transcriptTextView.text = result.transcription.transcript
                    print(result.recordingURL)
                } else {
                    print("Failure: ", result.error)
                }
                self.setupButtons()
            }
        } catch let error {
            print("Error Stopping: ", error)
        }
        setupButtons()
    }
}

