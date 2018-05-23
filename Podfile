# Uncomment the next line to define a global platform for your project
platform :ios, '10.0'

 # Disable sending stats
ENV['COCOAPODS_DISABLE_STATS'] = 'true'

target 'Psiphon' do
  # Comment the next line if you're not using Swift and don't want to use dynamic frameworks
  #use_frameworks!

  # Pods for Psiphon
  pod "InAppSettingsKit", :git => "https://github.com/Psiphon-Inc/InAppSettingsKit.git", :commit => '598c498'
  #pod "InAppSettingsKit", :path => "../InAppSettingsKit"
  pod 'PsiphonClientCommonLibrary', :git => "https://github.com/Psiphon-Inc/psiphon-ios-client-common-library.git", :commit => '73789ac'
  #pod "PsiphonClientCommonLibrary", :path => "../psiphon-ios-client-common-library"

  pod 'ReactiveObjC', :git => "https://github.com/Psiphon-Inc/ReactiveObjC.git", :commit => 'b2ac770'
  pod 'OpenSSL', '1.0.210'
  pod 'mopub-ios-sdk', '4.18.0'
  pod 'Google-Mobile-Ads-SDK', '7.25.0'
  pod 'VungleSDK-iOS', '5.3.0'
  pod 'PureLayout', '3.0.2'
  pod 'MBProgressHUD', '~> 1.1.0'
  pod 'CustomIOSAlertView', '~> 0.9.5'
end

target 'PsiphonVPN' do
  # Comment the next line if you're not using Swift and don't want to use dynamic frameworks
  #use_frameworks!

  pod 'ReactiveObjC', :git => "https://github.com/Psiphon-Inc/ReactiveObjC.git", :commit => 'b2ac770'

end
