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

    var isTranscribing: Bool {
        return WatsonSTTManager.shared.state.isTranscribing
    }

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

        do {
            try WatsonSTTManager.shared.startTranscribing({ results in
                print("onResults:", results.bestTranscript)
                self.transcriptTextView.text = results.bestTranscript
            })
        } catch let error {
            print("Error Starting: ", error)
        }
        setupButtons()
    }

    @IBAction func didTapStopRecording(sender: AnyObject) {
        print(#function)

        do {
            try WatsonSTTManager.shared.stopTranscribing()
        } catch let error {
            print("Error Stopping: ", error)
        }
        setupButtons()
    }
}

