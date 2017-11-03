# Psiphon iOS VPN

### Prerequisites
- [Cocoapods](https://cocoapods.org/)
  `sudo gem install cocoapods`

### Building
- Replace `Shared/psiphon_config.stub` with your configuration file.
- Replace `Shared/embedded_server_entries.stub` with your server entries file.
- Replace `Psiphon/Bourbon-Oblique.otf` with the "Psiphon" font file.
- Run `pod install` to install the third-party libraries.

## I18n/L10n

### Adding or modifying strings

All user-facing strings must be localized; logs and strings not visible to users should not be.

#### ...in an Objective-C file

When adding a string, use this function:
```no-highlight
NSLocalizedStringWithDefaultValue(<key>, nil, [NSBundle mainBundle], <string>, <description>)
```
`<string>` is the actual string shown to the user (in English). `<description>` is a description and of and context for the string to help translators correctly localize it.

`<key>` must be in an `ALL_CAPS` form, and not just the string itself. This allows us to change or fix the string without changing its key, thereby allowing us to not lose existing translations just because we fix a typo in the English (for example).

So, when making a minor edit to a string that does not fundamentally change its meaning, do not change the key. When making a major edit that should invalidate existing translations, also change the key. Do not be precious about existing translations: if meaning changes, change the key -- the translations will catch up.

After adding or modifying a string, build the project, that will trigger `genstrings.sh`, which will update `en.lproj/Localizable.strings`. Commit that file with your change and Transifex will automatically pick up the change (overnight).

#### ...in a `.plist` file

There are three `.plist` files in this project (all under `Psiphon/InAppSettings.bundle`). They are all based on similar files in the [PsiphonClientCommonLibrary project](https://github.com/Psiphon-Inc/psiphon-ios-client-common-library/tree/master/Example/PsiphonClientCommonLibrary/InAppSettings.bundle).

* `Root.inApp.plist`: The root of -- and majority of -- the settings.
* `ConnectionHelp.plist`: Settings specifically broken out to help with connection problems.
* `Feedback.plist`: The feedback interface.

Many of the strings in those files are translated in PsiphonClientCommonLibrary, and so they should directly reference that bundle. Like so:
```
<key>BundleTable</key>
<string>PsiphonClientCommonLibrary</string>
```

For items and strings _not_ in PsiphonClientCommonLibrary: When adding or modifying strings, you _must_ reflect the changes in [`en.lproj/Root.strings`][Root.strings]. Use the `ALL_CAPS` form described above for the key (yes, that means that the plists will be full of non-English keys), as well as the minor/major edit considerations for changing a key. Provide a comment in `Root.strings` for every entry -- this is the description/context for translators.

Also, make sure you implement required methods when adding a new specifier of `IASKCustomViewSpecifier` type, see [InAppSettingsKit README](https://github.com/Psiphon-Inc/InAppSettingsKit#iaskcustomviewspecifier).

### Updating translations

Translations for this project are in two places: in [PsiphonClientCommonLibrary](https://github.com/Psiphon-Inc/psiphon-ios-client-common-library/tree/master/PsiphonClientCommonLibrary/Resources/Strings) and in [this project](https://github.com/Psiphon-Inc/psiphon-ios-vpn/tree/master/Shared/Strings). The former has the settings and feedback strings common to all Psiphon iOS apps. The latter has the strings specific to this app.

Updating the PsiphonClientCommonLibrary strings involves updating the pod for that library in this project. You can run `pod update PsiphonClientCommonLibrary` or modify the target commit hash in the [`Podfile`](https://github.com/Psiphon-Inc/psiphon-ios-vpn/blob/master/Podfile) and then run `pod install`. (Instructions for how to update the strings in PsiphonClientCommonLibrary can be found in that project's README.)

To update the strings in this app, run `./transifex_pull.py` from the project root (with a valid `transifex_conf.json` in place). `git status` will show you which languages changed. Do some smoke tests on those languages and commit.

While running `transifex_pull.py` you may see some output like this:
```no-highlight
Resource: ios-vpn-app-localizablestrings
Skipping language "uz" with 56% translation (13 of 23)
```
This indicates that there is a well-translated language that is currently not part of the pull (and not part of the currently supported languages). You may wish to consider adding this language. See the next section for instructions how.

### Adding a new language

As mentioned above, translations for this project are in two places: in [PsiphonClientCommonLibrary](https://github.com/Psiphon-Inc/psiphon-ios-client-common-library/tree/master/PsiphonClientCommonLibrary/Resources/Strings) and in [this project](https://github.com/Psiphon-Inc/psiphon-ios-vpn/tree/master/Shared/Strings). The former has the settings and feedback strings common to all Psiphon iOS apps. The latter has the strings specific to this app. Adding a new language requires updating both projects.

To learn about adding a new language to PsiphonClientCommonLibrary, see the README for that project. When it is updated, update its pod in this project (see above for instructions).

To add a language to this project, follow these steps:

1. **Add the language to the Xcode project.** In the *Project* settings, *Info* tab. Click `+` and select the desired language. (If it's not in the list, then it can't be added here. It isn't supported natively by iOS, but it can still be added and selected from the app settings. Skip to step 2.) Allow it to create `Localizable.strings`, but not `LaunchScreen.storyboard`. (If you had already pulled the translation, you'll need to re-pull, since this will clobber it.) Make note of the language code used by Xcode. If this differs from the code used by Transifex, there will need to be a mapping between them in the next step. You should see that `Shared/Strings/<new-language>.lproj/Localizable.strings` has been created.

2. **Add the language to `transifex_pull.py`.** At the top of `transifex_pull.py` is a dict containing all supported languages. It is a map from the Transifex locale codes to the iOS locale codes. Add the new language to this dict, in alphabetical order, with the correct mapping (noted in the previous step).

3. **Run `transifex_pull.py`.** This will pull all translations, including the newly added one. You should see that `Shared/Strings/<new-language>.lproj/Localizable.strings` has been updated (translated) and that `StoreAssets/<new-language>.yaml` has been created.

4. **Add the language to our in-app language selector.** In `Psiphon/InAppSettings.bundle/Root.inApp.plist`, add the new language code and the name of the language as it's written in that language. If the language is not one of our top 3 or 4, it should be added in alphabetical order, based on the language code. Note that if the language was first added to PsiphonClientCommonLibrary, then the name will be (should be) available in that project's [`Root.inApp.plist`](https://github.com/Psiphon-Inc/psiphon-ios-client-common-library/blob/master/Example/PsiphonClientCommonLibrary/InAppSettings.bundle/Root.inApp.plist). (Otherwise check the [Omniglot list](http://www.omniglot.com/language/names.htm).)

Do some testing. Commit.

### Using App Store assets

The App Store listing for this app requires an app name, subtitle, description, keywords, etc. These should be localized. These English values for these strings are contained in `StoreAssets/master.yaml`. These values _must be kept up to date_ with the values in iTunes Connect.

When `transifex_pull.py` is run, the translations for these values will be updated.

Adding a language for the listing is pretty obvious in iTunes Connect. As is switching between languages to modify them.

Note that the App Store does not support all the languages supported by apps -- the options you see available are all that there are. Notably, Arabic and Farsi are not supported. We may wish to append those languages to the bottom of the English description (as an example, see the [Psiphon Browser listing](https://itunes.apple.com/us/app/psiphon-browser/id1193362444)).

To update translations in iTunes Connect, switch between the languages in the web interface and paste in the corresponding translation from `StoreAssets/<language>.yaml`. _Remember to de-indent the description_.
