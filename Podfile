# Uncomment the next line to define a global platform for your project
platform :ios, '8.0'

 # Disable sending stats
ENV['COCOAPODS_DISABLE_STATS'] = 'true'

target 'Psiphon' do
  # Comment the next line if you're not using Swift and don't want to use dynamic frameworks
  #use_frameworks!

  # Pods for Psiphon
  pod "InAppSettingsKit", :git => "https://github.com/Psiphon-Inc/InAppSettingsKit.git", :commit => '598c498'
  #pod "InAppSettingsKit", :path => "../InAppSettingsKit"
  pod 'PsiphonClientCommonLibrary', :git => "https://github.com/Psiphon-Inc/psiphon-ios-client-common-library.git", :commit => 'c6f86c2'
  #pod "PsiphonClientCommonLibrary", :path => "../psiphon-ios-client-common-library"

  pod 'OpenSSL', '1.0.210'
  pod 'mopub-ios-sdk', '4.16.0'
  pod 'Google-Mobile-Ads-SDK', '7.24.0'
  pod 'VungleSDK-iOS', '5.2.0'
end

target 'PsiphonVPN' do
  # Comment the next line if you're not using Swift and don't want to use dynamic frameworks
  #use_frameworks!

end
