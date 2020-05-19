# Uncomment the next line to define a global platform for your project
platform :ios, '10.2'

 # Disable sending stats
ENV['COCOAPODS_DISABLE_STATS'] = 'true'

use_modular_headers!

target 'Psiphon' do
  # Pods for Psiphon
  pod "InAppSettingsKit", :git => "https://github.com/Psiphon-Inc/InAppSettingsKit.git", :commit => '8bd203c'
  #pod "InAppSettingsKit", :path => "../InAppSettingsKit"
  #pod "PsiphonClientCommonLibrary", :path => "../psiphon-ios-client-common-library"
  pod 'PsiphonClientCommonLibrary', :git => "https://github.com/Psiphon-Inc/psiphon-ios-client-common-library.git", :commit => '3c04c40'

  # Swift dependencies
  pod 'ReactiveSwift', '~> 6.2'
  pod 'ReactiveCocoa', '~> 10.1'
  pod 'ReactiveObjC', :git => "https://github.com/Psiphon-Inc/ReactiveObjC.git", :commit => '8bbf9dd'
  pod 'PromisesSwift', '~> 1.2'
  pod 'Google-Mobile-Ads-SDK', '~> 7.59'
  pod 'PersonalizedAdConsent', '~> 1.0'  # Google Mobile Ads Consent SDK
  pod 'MBProgressHUD', '~> 1.1.0'
  pod 'SVProgressHUD'
end

target 'PsiphonVPN' do
end

target 'PsiphonTests' do
  pod 'PsiphonClientCommonLibrary', :git => "https://github.com/Psiphon-Inc/psiphon-ios-client-common-library.git", :commit => '3c04c40'
  pod 'ReactiveSwift', '~> 6.2'
  pod 'ReactiveCocoa', '~> 10.1'
  pod 'ReactiveObjC', :git => "https://github.com/Psiphon-Inc/ReactiveObjC.git", :commit => '8bbf9dd'
  pod 'PromisesSwift', '~> 1.2'
end

post_install do |installer|
  installer.pods_project.targets.each do |target|
    target.build_configurations.each do |config|
      config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '10.2'
    end
  end
end

