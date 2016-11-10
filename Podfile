# Uncomment this line to define a global platform for your project
platform :ios, '10.0'
use_frameworks!

target 'WatsonSpeechToTextDemo' do
    pod 'Intrepid', '~> 0.5.2'
    pod 'Alamofire', '~> 3.5.1'
    pod 'Freddy', '~> 2.1.0'
    pod 'Starscream', '~> 1.1.4'

    target 'WatsonSpeechToTextDemoTests' do
        pod 'Nimble', '~> 4.0'
        pod 'Quick', '~> 0.9.1'
    end

    post_install do |installer|
        installer.pods_project.targets.each do |target|
            target.build_configurations.each do |config|
                config.build_settings['EXPANDED_CODE_SIGN_IDENTITY'] = ""
                config.build_settings['CODE_SIGNING_REQUIRED'] = "NO"
                config.build_settings['CODE_SIGNING_ALLOWED'] = "NO"
                config.build_settings['CODE_SIGN_IDENTITY[sdk=iphoneos*]'] = ""
                config.build_settings['SWIFT_VERSION'] = '2.3'
            end
        end
    end
end
