# Building Psiphon iOS VPN

## Manual Build

### Prerequisites
* xcode `xcode-select --install`

* [git](https://git-scm.com/download/mac)

* [homebrew](http://brew.sh/)

### Build Steps
* Replace `Shared/psiphon_config.stub` with your configuration file.
* Replace `Shared/embedded_server_entries.stub` with your server entries file.
* Run `build.sh <app-store|testflight|internal>`. Supplying the intended distribution target as a parameter.
  - If you specify `app-store` `CFBundleVersion` and `CFBundleShortVersionString` will be incremented in `Psiphon/Info.plist` and 'PsiphonVPN/Info.plist`
  - If you specify `testflight` `CFBundleShortVersionString` will be incremented in `Psiphon/Info.plist` and 'PsiphonVPN/Info.plist`
* The result will be in `build/{app-store, testflight, internal}`.

## Automatic Build -- Jenkins
Build artifacts can be found in Jenkins.

### Deployment
* `Psiphon/Info.plist` and `PsiphonVPN/Info.plist` should have the same version numbers.
* Version numbers should be [semver](http://semver.org/)-compatible. They will be automatically incremented when you run `build.sh`. This is automatically done in Jenkins as it uses `build.sh`. Also, you can automate incrementing them with `increment_plist.py`.
* TODO: iTunes connect uploads

### Validating builds
* Get the signature from the .ipa:
  - Rename *.ipa to *.zip
  - `unzip *.ipa`
  - `codesign -d --extract-certificates Payload/*.app`
  - `openssl x509 -inform DER -in codesign0`
* Get signature from cert want to validate against:
  - `openssl x509 -inform der -in *.cer`
* Verify that both signatures match.
* Getting additional information:
  - Rename *.ipa to *.zip
  - `unzip *.ipa`
  - `cd ./Payload/*.app`
  - `codesign -d -dvvvv .`
  - Or install [shezen](https://github.com/nomad/shenzhen) and run `ipa info *.ipa`

## Uploading Store Assets

### Prerequisites
* xcode `xcode-select --install`

* [fastlane](https://github.com/fastlane/fastlane)

* iTMSTransporter `/Applications/Xcode.app/Contents/Applications/Application Loader.app/Contents/itms/bin/iTMSTransporter`

### Setup
* Do a [transifex pull](https://github.com/Psiphon-Inc/psiphon-ios-vpn/blob/master/README.md#i18nl10n) to ensure the
translations are up to date.
* Update the [Snapfile](https://github.com/Psiphon-Inc/psiphon-ios-vpn/blob/master/Snapfile) with the languages and
devices you want to generate screenshots for.
* Update the fields in [StoreAssets/metadata.json](https://github.com/Psiphon-Inc/psiphon-ios-vpn/blob/master/StoreAssets/metadata.json)
 as needed:
  - Languages supported by Apple on the App Store
  - Mappings of language codes used in `StoreAssets/*.yaml` to those supported by Apple on the App Store
  - Mappings from the device names used by fastlane to the display targets used by iTMSTransporter
   (e.g. `"iPhone 6 Plus": "iOS-5.5-in"`)
  - Array of screenshots defined in the order they will be displayed on the App Store.
  - See [store_assets_itmsp.py](https://github.com/Psiphon-Inc/psiphon-ios-vpn/blob/master/store_assets_itmsp.py) for more
  details.

### Build Steps
* Generate localized screenshots:
  - `fastlane snapshot`
  - Screenshots should now reside in `StoreAssets/screenshots`
* Generate the .itmsp package
  - `python store_assets_itmsp.py --provider $PROVIDER --team_id $TEAM_ID --vendor_id $VENDOR_ID
   --version_string $VERSION_STRING --whats_new $WHATS_NEW --output_path $OUTPUT_PATH`
  - `$TEAM_ID`: can be found in *.xcodeproj/project.pbxproj.
  - `$PROVIDER`: Provider ID. Commonly equal to team ID. Can be found with: `{path_to_iTMSTransporter} -m provider -u
   {username} -p {password} -account_type itunes_connect -v off`
  - `$VENDOR_ID`: Bundle ID of the app. Can be found on iTunes Connect or in Xcode.
  - `$VERSION_STRING`: CFBundleShortVersionString found in Info.plist.
  - `$WHATS_NEW`: Description of what is new in this version of the app. Used on the App Store.
  - `$OUTPUT_PATH`: Directory where the *.itmsp package will be generated.

### Validating itmsp package
* Use iTMSTransporter to verify the package before uploading it:
  - `iTMSTransporter -m verify -f /path/to/my/package.itmsp -u $ITUNES_CONNECT_USERNAME -p $ITUNES_CONNECT_PASSWORD`

### Uploading the itmsp package
* Use iTMSTransporter to upload the package to iTunes Connect:
  - `iTMSTransporter -m upload -f /path/to/my/package.itmsp -u $ITUNES_CONNECT_USERNAME -p $ITUNES_CONNECT_PASSWORD`

### Retrieving the current itmsp package:
* Use iTMSTransporter to retrieve the latest itmsp package from iTunes Connect:
  - `iTMSTransporter -m lookupMetadata -u $ITUNES_CONNECT_USERNAME -p $ITUNES_CONNECT_PASSWORD -vendor_id $VENDOR_ID
   -destination ~/iTMSPackages/`
  - `$VENDOR_ID`: Bundle ID of the app. Can be found on iTunes Connect or in Xcode.
* `.itmsp/metadata.xml` is a useful reference for seeing some of the fields that can be modified by uploading a new package.
