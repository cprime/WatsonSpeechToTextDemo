# WatsonSpeechToTextDemo
Simple demo for the IBM Watson Streaming Library.

This project contains code the IBM Watson SDK (https://github.com/watson-developer-cloud/ios-sdk, v0.8.1). I chose to add the code directly, rather than using their preferred method of Carthage, because I need intend to use any SpeechToText abstractions generated here in another project that needs to use Cocoapods.

In order to build and run this project you will need to create `keys.plist` and fill it in with the necessary API keys. See `keys_sample.plist` as a reference.