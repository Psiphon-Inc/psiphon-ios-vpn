# HyprMX Mobile SDK AdMob Adapter Overview

## Introduction

HyprMX iOS AdMob Adapter allows you to integrate HyprMX in your AdMob rewarded and interstitial waterfall.

## Setup Instructions

This guide assumes you already have the AdMob iOS SDK integrated into your Xcode project.

- Drag and drop the HyprMX-AdMob-Adapter folder (available in the SDK zip) into your Xcode project, making sure that the files are copied and not just referenced.

- Select the HyprMX.framework and all the adapter implementation .m files (listed below) in the Project Navigation tab.  From the File Explorer tab, ensure they have been added to your Main Application&#39;s build target in the &quot;Target Membership&quot; pane.
    - HYPRAdMobVideoAdapter.m
    - HyprMXAdNetworkExtras.m

- Once the framework has been copied into your project directory, add the HyprMX.framework to your Link Binary With Libraries section of your project&#39;s Build Phases tab.

- Find the key &quot;Other Linker Flags&quot; in the &quot;Linking&quot; section of your project&#39;s build settings. For that key, add the value -ObjC. Make sure not to select just &quot;Debug&quot; or &quot;Release&quot; within &quot;Other Linker Flags&quot;, but rather the general line above those. 

- Ensure that your ATS (App Transport Security) settings are as described by [AdMob](https://developers.google.com/admob/ios/app-transport-security).

### Required Frameworks

To integrate the HyprMX Framework, the following frameworks must be added to your project:

    - HyprMX.framework
    - AdSupport.framework
    - AVFoundation.framework
    - CoreGraphics.framework
    - CoreTelephony.framework
    - Foundation.framework
    - MessageUI.framework
    - MobileCoreServices.framework
    - QuartzCore.framework
    - SystemConfiguration.framework
    - UIKit.framework
    - libxml2.tbd
    - WebKit.framework (Status set to Optional)
    - SafariServices.framework (Status set to Optional)
    - StoreKit.framework (Status set to Optional)
    - EventKit.framework
    - EventKitUI.framework

### Configuring Privacy Controls

iOS requires that the use of a user&#39;s camera, calendar, photo library, etc. be declared by advertisers in the plist. In order to maximize fill rate, please add all of the following entries to your app&#39;s plist.  

    <key>NSCalendarsUsageDescription</key>
    <string>${PRODUCT_NAME} requests access to the Calendar</string>
    <key>NSPhotoLibraryUsageDescription</key>
    <string>${PRODUCT_NAME} requests access to the Photo Library</string>
    <key>NSPhotoLibraryAddUsageDescription</key>
    <string>${PRODUCT_NAME} requests write access to the Photo Library</string>

Note: Photo Usage and the Photo Add Usage keys are required by the framework to ensure all rich media advertisements are supported.

## Integrating HyprMX On The AdMob Dashboard Using Custom Events

1. Create your Mediation Group on the AdMob Dashboard. If you are integrating Interstitial and Rewarded Video, follow these steps for both.
2. In the Ad Sources, select `Add Custom Event`.
3. In the popup, enter &#39;HyprMX&#39; in the label field and set the default eCPM (e.g. $15.00).
4. Click Continue.
5. Set `HYPRAdMobVideoAdapter` as your classname.
6. In the parameter field, enter the distributor ID assigned to you by your HyprMX account manager.
7. Click &#39;Done&#39;.

## Optional: User ID

If your app relies on server-to-server callbacks and requires you to set a static user ID that is publisher-defined for Rewarded Video, pass the user ID by registering a HyprMXAdNetworkExtras object to your GADRequest as shown below. Please contact your HyprMX account services representative if you would like to implement a postback.

The user ID should not contain personal information such as an email address, screen name, or Apple&#39;s Advertising Identifier (IDFA).

```
GADRequest *request = [GADRequest request];
HyprMXAdNetworkExtras *extras = [[HyprMXAdNetworkExtras alloc] init];
extras.userId = hyprMXUserId;
[request registerAdNetworkExtras:extras];
```

Replace `hyprMXUserId` with the the user ID.

## License

By downloading this SDK, you are agreeing to the LICENSE included with this zip.
