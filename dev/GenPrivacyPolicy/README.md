# GenPrivacyPolicy

GenPrivacyPolicy is a command line executable that automatically generates Swift code
from the privacy policy source files used to generate Psiphon website's Privacy Policy section.

 ```
 $ swift run GenPrivacyPolicy --help
USAGE: cli --app-language-key <app-language-key> --privacy-policy-template-url <privacy-policy-template-url> --translations-url <translations-url>

OPTIONS:
  --app-language-key <app-language-key>
                          Key for the app language
  --privacy-policy-template-url <privacy-policy-template-url>
                          Privacy policy HTML .eco template file
  --translations-url <translations-url>
                          Translations URL
  -h, --help              Show help information.
 ```

## Example usage

```
$ swift run GenPrivacyPolicy --app-language-key languageCode --privacy-policy-template-url https://raw.githubusercontent.com/.../privacy.html.eco --translations-url https://raw.githubusercontent.com/.../messages.json > output.swift

```
