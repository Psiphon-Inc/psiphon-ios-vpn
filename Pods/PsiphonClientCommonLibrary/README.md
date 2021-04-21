# PsiphonClientCommonLibrary

## Versioning

As of version 1.0.0 this pod adheres to [Semantic Versioning 2.0.0](https://semver.org/)

## Example

To run the example project, clone the repo, and run `pod install` from the Example directory first. Then open `PsiphonClientCommonLibrary.xcworkspace` in Xcode.

## Requirements

[CocoaPods](https://cocoapods.org/).

## Installation

To install, simply add the following line to your Podfile:

```ruby
pod 'PsiphonClientCommonLibrary', :git => "https://github.com/Psiphon-Inc/psiphon-ios-client-common-library.git"
```

## App Integration

### Psiphon Settings

Copy `psiphon-ios-client-common-library/Example/PsiphonClientCommonLibrary/InAppSettings.bundle` into your project and customize it to fit the needs of the project it is being used in. You can find more information on how InAppSettingsKit works [here](https://github.com/Psiphon-Inc/InAppSettingsKit/blob/master/README.md).

Use `PsiphonSettingsViewController` for displaying the shared settings menu. Subclass it to provide any functionality for new project specific settings.

## Development

### Getting Started
```bash
cd ./Example
pod install
open PsiphonClientCommonLibrary.xcworkspace
```
Now you can start making changes to the pod by working with the files in `Pods/Development Pods` in the Xcode project.

### Adding a new server region

1. In Xcode, under the Resources group, click on `Images.xcassets`. Note the assets list that appears.
2. In Finder, go to `psiphon-ios-client-common-library/External/flag-icon-css/flags/4x3`. Select the files `flag-zz.png`, `flag-zz@2x.png`, and `flag-zz@3x.png`, where `zz` is the region you want.
3. Drag the selected files onto the assets list in Xcode.
4. In `RegionAdapter.m`, update the `init` and `getLocalizedRegionTitles` functions with the new region.
5. Compile the app, so that the strings files get updated.

## I18n/L10n

After making any changes, to see the result in the Example app, go into the `Example` directory and run `pod update PsiphonClientCommonLibrary`.

The library version number must be incremented when a translation change is made.

### Adding or modifying strings

All user-facing strings must be localized; logs and strings not visible to users should not be.

#### ...in an Objective-C file

When adding a string to Objective-C, use this function:
```no-highlight
NSLocalizedStringWithDefaultValue(<key>, nil, [PsiphonClientCommonLibraryHelpers commonLibraryBundle], <string>, <description>)
```
`<string>` is the actual string shown to the user (in English). `<description>` is a description and of and context for the string to help translators correctly localize it.

`<key>` must be in an `ALL_CAPS` form, and not just the string itself. This allows us to change or fix the string without changing its key, thereby allowing us to not lose existing translations just because we fix a typo in the English (for example).

So, when making a minor edit to a string that does not fundamentally change its meaning, do not change the key. When making a major edit that should invalidate existing translations, also change the key. Do not be precious about existing translations: if meaning changes, change the key -- the translations will catch up.

After adding or modifying a string, build the project, that will trigger `genstrings.py`, which will update `en.lproj/Localizable.strings`. Commit that file with your change and Transifex will automatically pick up the change (overnight).

#### ...in a `.plist` file`

There are three `.plist` files in this project (all under `Example/PsiphonClientCommonLibrary/InAppSettings.bundle`). They should be used as the basis for the plists in the app projects.

* [`Root.inApp.plist`][Root.inApp.plist]: The root of -- and majority of -- the settings.
* [`PsiphonSettings.plist`][PsiphonSettings.plist]: More Psiphon-specific settings.
* [`ConnectionHelp.plist`][ConnectionHelp.plist]: Settings specifically broken out to help with connection problems.
* [`Feedback.plist`][Feedback.plist]: The feedback interface.

[`en.lproj/Root.strings`][Root.strings] is generated from the `.plist` files by `genstrings.py`. A typical `.plist` item looks like this:
```xml
<dict>
    <key>Title</key>
    <string>SELECT_SERVER_REGION</string>
    <key>TitleDefault</key>
    <string>Select server region</string>
    <key>TitleDescription</key>
    <string>Settings item text. Leads to the user being able to choose which country/region they want to use a Psiphon Server in. Should be kept short.</string>
    <key>BundleTable</key>
    <string>PsiphonClientCommonLibrary</string>
    <key>Key</key>
    <string>regionSelection</string>
    <key>Type</key>
    <string>IASKCustomViewSpecifier</string>
    <key>DefaultValue</key>
    <string></string>
</dict>
```

* `Title` is the string key for the string. It must not be the string itself. (For the minor/major edit reasons described above.)
* `TitleDefault` is the "default" (i.e., English) value for the string, as passed to `NSLocalizedStringWithDefaultValue`.
* `TitleDescription` is the description/comment/directive for the translator. It should contain context, instructions, etc.
* `BundleTable` will always be `PsiphonClientCommonLibrary` for `.plist` files in this project (but not so for the app projects that use this library).

If a string in a `.plist` should _not_ be translated, it should look like this:
```xml
<dict>
    <key>Title</key>
    <string>Français</string>
</dict>
```

In addition to `Title`, `TitleDefault`, `TitleDescription`, there are similar attributes for `FooterText`, `IASKSubtitle`, and `IASKPlaceholder`.

### Updating translations

To update the strings in this app, run `./transifex_pull.py` from the project root (with a valid `transifex_conf.json` in place). `git status` will show you which languages changed. Do some smoke tests on those languages.

While running `transifex_pull.py` you may see some output like this:
```no-highlight
Resource: ios-vpn-app-localizablestrings
Skipping language "uz" with 56% translation (13 of 23)
```
This indicates that there is a well-translated language that is currently not part of the pull (and not part of the currently supported languages). You may wish to consider adding this language. See the next section for instructions how.

### Adding a new language

1. **Add the language to `transifex_pull.py`.** At the top of `transifex_pull.py` is a dict containing all supported languages. It is a map from the Transifex locale codes to the iOS locale codes. Add the new language to this dict, in alphabetical order. You can find the correct language mapping for iOS apps by going to *Project* settings, *Info* tab, and clicking `+` to show the languages and codes (don't actually add the language, though).

2. **Run `transifex_pull.py`.** This will pull all translations, including the newly added one. You should see that `PsiphonClientCommonLibrary/Resources/Strings/<new-language>.lproj/Root.strings` and `Localizable.strings` have been created.

3. **Add the language to our in-app language selector.** In `Example/PsiphonClientCommonLibrary/InAppSettings.bundle/Root.inApp.plist`, add the new language code and the name of the language as it's written in that language. If the language is not one of our top 3 or 4, it should be added in alphabetical order, based on the language code.

To get the name of a language in that language, check the [Windows code](https://bitbucket.org/psiphon/psiphon-circumvention-system/src/0211b8c0106c907f3e2b4611f1cd11decab449e1/Client/psiclient/webui/_locales/locale-names.json?at=default) or [website code](https://bitbucket.org/psiphon/psiphon-circumvention-system/src/0211b8c0106c907f3e2b4611f1cd11decab449e1/Website/docpad.coffee?at=default#docpad.coffee-313), or look at the [Omniglot list](http://www.omniglot.com/language/names.htm).

Run `pod update PsiphonClientCommonLibrary` in the `Example` directory. Do some testing. Commit.


## Author

Psiphon Inc.

## License

PsiphonClientCommonLibrary is available under the GPLv3 license. See the LICENSE file for more info.

[Root.strings]: https://github.com/Psiphon-Inc/psiphon-ios-client-common-library/blob/master/PsiphonClientCommonLibrary/Resources/Strings/en.lproj/Root.strings
[Root.inApp.plist]: https://github.com/Psiphon-Inc/psiphon-ios-client-common-library/blob/master/Example/PsiphonClientCommonLibrary/InAppSettings.bundle/Root.inApp.plist
[PsiphonSettings.plist]: https://github.com/Psiphon-Inc/psiphon-ios-client-common-library/blob/master/Example/PsiphonClientCommonLibrary/InAppSettings.bundle/PsiphonSettings.plist
[ConnectionHelp.plist]: https://github.com/Psiphon-Inc/psiphon-ios-client-common-library/blob/master/Example/PsiphonClientCommonLibrary/InAppSettings.bundle/ConnectionHelp.plist
[Feedback.plist]: https://github.com/Psiphon-Inc/psiphon-ios-client-common-library/blob/master/Example/PsiphonClientCommonLibrary/InAppSettings.bundle/Feedback.plist
