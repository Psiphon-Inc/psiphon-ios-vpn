# Building Psiphon iOS VPN

### Manual Build

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

### Automatic Build -- Jenkins
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

