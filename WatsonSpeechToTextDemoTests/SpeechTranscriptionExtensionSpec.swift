//
//  SpeechTranscriptionExtensionSpec.swift
//  WatsonSpeechToTextDemo
//
//  Created by Colden Prime on 11/9/16.
//  Copyright © 2016 IntrepidPursuits. All rights reserved.
//

@testable import WatsonSpeechToTextDemo
import Nimble
import Quick
import Intrepid

extension SpeechRecognitionResult {
    init(final: Bool = true, alternatives: [SpeechRecognitionAlternative] = [], keywordResults: [String: [KeywordResult]]? = nil, wordAlternatives: [WordAlternativeResults]? = nil) {
        self.final = final
        self.alternatives = alternatives
        self.keywordResults = keywordResults
        self.wordAlternatives = wordAlternatives
    }
}

extension SpeechRecognitionAlternative {
    init(transcript: String, confidence: Double?, timestamps: [WordTimestamp]?, wordConfidence: [WordConfidence]?) {
        self.transcript = transcript
        self.confidence = confidence
        self.timestamps = timestamps
        self.wordConfidence = wordConfidence
    }

    static func createAlternative(withTranscript transcript: String, startOffset: Double = 0) -> SpeechRecognitionAlternative {
        let words = transcript.componentsSeparatedByString(" ")
        let timestamps = words.enumerate().map({ index, word in
            WordTimestamp(
                word: word,
                startTime: startOffset + Double(index),
                endTime: startOffset + Double(index + 1)
            )
        })
        let wordConfidence = words.map({ word in
            WordConfidence(word: word, confidence: 1)
        })
        return SpeechRecognitionAlternative(
            transcript: words.joinWithSeparator(" "),
            confidence: 1,
            timestamps: timestamps,
            wordConfidence: wordConfidence
        )
    }
}

extension WordTimestamp {
    init(word: String, startTime: Double, endTime: Double) {
        self.word = word
        self.startTime = startTime
        self.endTime = endTime
    }
}

extension WordConfidence {
    init(word: String, confidence: Double) {
        self.word = word
        self.confidence = confidence
    }
}

extension WordAlternativeResults {
    init(startTime: Double, endTime: Double, alternatives: [WordAlternativeResult]) {
        self.startTime = startTime
        self.endTime = endTime
        self.alternatives = alternatives
    }
}

extension WordAlternativeResult {
    init(confidence: Double, word: String) {
        self.confidence = confidence
        self.word = word
    }
}

class SpeechTranscriptionExtensionSpec: QuickSpec {
    override func spec() {
        describe("A SpeechTranscription") {
            var results: SpeechRecognitionResults!
            var transcription: SpeechTranscription!

            context("created with an Watson SpeechRecognitionResults without any results") {
                beforeEach {
                    results = SpeechRecognitionResults(results: [])
                    transcription = SpeechTranscription(watsonSpeechRecognitionResults: results, keywords: [])
                }

                it("should be empty") {
                    expect(transcription.transcript).to(equal(""))
                    expect(transcription.wordTimestamps.isEmpty).to(beTrue())
                }
            }

            context("created with a Watson SpeechRecognitionResults with a single result") {
                context("with a single word alternative") {
                    beforeEach {
                        results = SpeechRecognitionResults(results: [
                            SpeechRecognitionResult(final: true, alternatives: [
                                SpeechRecognitionAlternative.createAlternative(withTranscript: "Hello")
                            ])
                        ])
                        transcription = SpeechTranscription(watsonSpeechRecognitionResults: results, keywords: [])
                    }

                    it("should have a transcript equal to the one word") {
                        expect(transcription.transcript).to(equal("Hello"))
                    }

                    it("should have one converted timestamp") {
                        expect(transcription.wordTimestamps).to(equal([SpeechWordTimestamp(word: "Hello", startOffset: 0, endOffset: 1)]))
                    }
                }

                context("with a multi word alternative") {
                    beforeEach {
                        results = SpeechRecognitionResults(results: [
                            SpeechRecognitionResult(final: true, alternatives: [
                                SpeechRecognitionAlternative.createAlternative(withTranscript: "How are you")
                                ])
                            ])
                        transcription = SpeechTranscription(watsonSpeechRecognitionResults: results, keywords: [])
                    }

                    it("should have a transcript equal to the words joined together") {
                        expect(transcription.transcript).to(equal("How are you"))
                    }

                    it("should have one converted timestamp") {
                        expect(transcription.wordTimestamps).to(equal([
                            SpeechWordTimestamp(word: "How", startOffset: 0, endOffset: 1),
                            SpeechWordTimestamp(word: "are", startOffset: 1, endOffset: 2),
                            SpeechWordTimestamp(word: "you", startOffset: 2, endOffset: 3)
                        ]))
                    }
                }

                context("with a multi word alternative with word alternatives") {
                    beforeEach {
                        let alternative = SpeechRecognitionAlternative.createAlternative(withTranscript: "Colin and carry go to the store")
                        let wordAlts = [
                            WordAlternativeResults(startTime: 0, endTime: 1, alternatives: [
                                WordAlternativeResult(confidence: 1, word: "Colin"),
                                WordAlternativeResult(confidence: 0.5, word: "Colden"),
                            ]),
                            WordAlternativeResults(startTime: 2, endTime: 3, alternatives: [
                                WordAlternativeResult(confidence: 1, word: "carry"),
                                WordAlternativeResult(confidence: 0.5, word: "Kerry"),
                            ])
                        ]
                        let result = SpeechRecognitionResult(final: true, alternatives: [alternative], wordAlternatives: wordAlts)
                        results = SpeechRecognitionResults(results: [result])
                        transcription = SpeechTranscription(watsonSpeechRecognitionResults: results, keywords: ["Colden", "Colin", "Kerry"])
                    }

                    it("should have a transcript equal to the words joined together") {
                        expect(transcription.transcript).to(equal("Colin and Kerry go to the store"))
                    }

                    it("should have converted timestamps for all of the words") {
                        expect(transcription.wordTimestamps).to(equal([
                            SpeechWordTimestamp(word: "Colin", startOffset: 0, endOffset: 1),
                            SpeechWordTimestamp(word: "and", startOffset: 1, endOffset: 2),
                            SpeechWordTimestamp(word: "Kerry", startOffset: 2, endOffset: 3),
                            SpeechWordTimestamp(word: "go", startOffset: 3, endOffset: 4),
                            SpeechWordTimestamp(word: "to", startOffset: 4, endOffset: 5),
                            SpeechWordTimestamp(word: "the", startOffset: 5, endOffset: 6),
                            SpeechWordTimestamp(word: "store", startOffset: 6, endOffset: 7),
                        ]))
                    }
                }
            }

            context("created with a Watson SpeechRecognitionResults with multiple results") {
                context("with multiple multi-word alternatives with word alternatives") {
                    beforeEach {
                        let alternative1 = SpeechRecognitionAlternative.createAlternative(withTranscript: "Colin and carry go to the store")
                        let wordAlts1 = [
                            WordAlternativeResults(startTime: 0, endTime: 1, alternatives: [
                                WordAlternativeResult(confidence: 1, word: "Colin"),
                                WordAlternativeResult(confidence: 0.5, word: "Colden"),
                                ]),
                            WordAlternativeResults(startTime: 2, endTime: 3, alternatives: [
                                WordAlternativeResult(confidence: 1, word: "carry"),
                                WordAlternativeResult(confidence: 0.5, word: "Kerry"),
                                ])
                        ]
                        let result1 = SpeechRecognitionResult(final: true, alternatives: [alternative1], wordAlternatives: wordAlts1)

                        let alternative2 = SpeechRecognitionAlternative.createAlternative(withTranscript: "Colin and carry go to the store", startOffset: 10)
                        let wordAlts2 = [
                            WordAlternativeResults(startTime: 10, endTime: 11, alternatives: [
                                WordAlternativeResult(confidence: 1, word: "Colin"),
                                WordAlternativeResult(confidence: 0.5, word: "Colden"),
                                ]),
                            WordAlternativeResults(startTime: 12, endTime: 13, alternatives: [
                                WordAlternativeResult(confidence: 1, word: "carry"),
                                WordAlternativeResult(confidence: 0.5, word: "Kerry"),
                                ])
                        ]
                        let result2 = SpeechRecognitionResult(final: true, alternatives: [alternative2], wordAlternatives: wordAlts2)


                        results = SpeechRecognitionResults(results: [result1, result2])
                        transcription = SpeechTranscription(watsonSpeechRecognitionResults: results, keywords: ["Colden", "Colin", "Kerry"])
                    }

                    it("should have a transcript equal to the words from both results joined together") {
                        expect(transcription.transcript).to(equal("Colin and Kerry go to the store Colin and Kerry go to the store"))
                    }

                    it("should have converted timestamps for all of the words") {
                        expect(transcription.wordTimestamps).to(equal([
                            SpeechWordTimestamp(word: "Colin", startOffset: 0, endOffset: 1),
                            SpeechWordTimestamp(word: "and", startOffset: 1, endOffset: 2),
                            SpeechWordTimestamp(word: "Kerry", startOffset: 2, endOffset: 3),
                            SpeechWordTimestamp(word: "go", startOffset: 3, endOffset: 4),
                            SpeechWordTimestamp(word: "to", startOffset: 4, endOffset: 5),
                            SpeechWordTimestamp(word: "the", startOffset: 5, endOffset: 6),
                            SpeechWordTimestamp(word: "store", startOffset: 6, endOffset: 7),
                            SpeechWordTimestamp(word: "Colin", startOffset: 10, endOffset: 11),
                            SpeechWordTimestamp(word: "and", startOffset: 11, endOffset: 12),
                            SpeechWordTimestamp(word: "Kerry", startOffset: 12, endOffset: 13),
                            SpeechWordTimestamp(word: "go", startOffset: 13, endOffset: 14),
                            SpeechWordTimestamp(word: "to", startOffset: 14, endOffset: 15),
                            SpeechWordTimestamp(word: "the", startOffset: 15, endOffset: 16),
                            SpeechWordTimestamp(word: "store", startOffset: 16, endOffset: 17),
                        ]))
                    }
                }
            }
        }
    }
}
