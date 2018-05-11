#!/usr/bin/env python
# -*- coding: utf-8 -*-

#
# Copyright (c) 2017, Psiphon Inc.
# All rights reserved.
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.


import argparse
import hashlib
import json
import os
import shutil
import sys
import yaml
import psiphon_website_info
from datetime import datetime
from jinja2 import Template


def get_itmsp_xml():
    return """
<package xmlns="http://apple.com/itunes/importer" version="software5.7">
    <team_id>{{ team_id }}</team_id>
    <provider>{{ provider }}</provider>
    <software>
        <vendor_id>{{ vendor_id }}</vendor_id> 
        <software_metadata>
            <versions>
                <version string="{{ version_string }}">
                    <locales>
                        {% for locale in locales %}
                            {{ locale }}
                        {% endfor %}
                    </locales>
                </version>
            </versions>
        </software_metadata>
    </software>
</package>
"""


def get_locale_xml():
    return """
<locale name="{{ locale_name }}">
    <title>{{ title }}</title>
    <subtitle>{{ subtitle }}</subtitle>
    <description>{{ description }}</description>
    {% if keywords %}
    <keywords>
    {% for keyword in keywords %}
        <keyword>{{ keyword }}</keyword>
    {% endfor %}
    </keywords>
    {% endif %}
    <version_whats_new>{{ version_whats_new }}</version_whats_new>
    {% if privacy_url %}
    <privacy_url>{{ privacy_url }}</privacy_url>
    {% endif %}
    {% if support_url %}
    <support_url>{{ support_url }}</support_url>
    {% endif %}
    {% if screenshots|length > 0 %}
    <software_screenshots>
    {%for screenshot in screenshots %}
        <software_screenshot display_target="{{ screenshot['display_target'] }}"
                                                position="{{ screenshot['position'] }}">
            <file_name>{{ screenshot['file_name'] }}</file_name>
            <size>{{ screenshot['size'] }}</size>
            <checksum type="md5">{{ screenshot['checksum'] }}</checksum>
        </software_screenshot>
    {% endfor %}
    </software_screenshots>
    {% endif %}
</locale>
"""


# https://stackoverflow.com/a/3431838
def md5(fname):
    """Returns md5 hash of file at path `fname`"""
    hash_md5 = hashlib.md5()
    with open(fname, "rb") as f:
        for chunk in iter(lambda: f.read(4096), b""):
            hash_md5.update(chunk)
    return hash_md5.hexdigest()


def create_locale_template(defaults, localized_store_strings_yaml, itmsp_path, store_assets_path, website, metadata,
                           whats_new):
    """Returns rendered template for locale in itmsp package metadata"""
    # Expected format for <localized_store_strings_yaml> file is:
    # <language_code>:
    #   app_name: <localized_app_name>
    #   subtitle: <localized_app_subtitle>
    #   description: <localized_app_description>
    #   keywords: <list>, <of>, <localized>, <keywords>

    yaml_file_path = os.path.join(store_assets_path, localized_store_strings_yaml)

    # Open yaml file with localized store descriptions
    if os.path.exists(yaml_file_path):
        with open(yaml_file_path, 'r') as f:
            yaml_dict = yaml.load(f)
            yaml_keys = yaml_dict.keys()

            if len(yaml_keys) != 1:
                sys.exit('Invalid yaml file for l10n: {}'.format(yaml_dict))

            locale = yaml_keys[0]  # this should hold if the yaml file follows the expected format
            localized = yaml_dict[locale]

            privacy_policy_url = website.privacy_policy_url(locale)
            support_url = website.faq_url(locale)

            screenshots = []

            if locale in metadata['language_code_mappings']:
                # Translate locale code to the corresponding one used by Apple
                locale = metadata['language_code_mappings'][locale]

            if locale not in metadata['app_store_supported_languages']:
                # If the locale is not supported by Apple then pass and
                # generate a warning.
                print("WARNING: {} is not supported by the app store".format(locale))
                return None

            screenshots_folder_path = os.path.join(store_assets_path, 'screenshots', locale)
            if not os.path.exists(screenshots_folder_path):
                print("WARNING: localized screenshots missing for {}".format(locale))

            for device_type, display_target in metadata['display_targets'].items():
                for index, screenshot in enumerate(metadata["screenshots"]):
                    screenshot_file_name = screenshot['filename_pattern'].replace('<device_type>', device_type)
                    screenshot_file_path = os.path.join(screenshots_folder_path, screenshot_file_name)

                    # copy the screenshot into the package (.itmsp directory) as:
                    # <locale>_<display_target>_<screenshot_name>
                    copied_screenshot_filename = locale + '_' + screenshot['filename_pattern'].replace('<device_type>-',
                                                                                                       display_target
                                                                                                       + '_')
                    copied_screenshot_path = os.path.join(itmsp_path, copied_screenshot_filename)
                    shutil.copy2(screenshot_file_path, copied_screenshot_path)

                    # add screenshot data for xml
                    screenshots.append({
                        "file_name": copied_screenshot_filename,
                        "display_target": display_target,
                        "position": index,
                        "checksum": md5(copied_screenshot_path),
                        "size": os.stat(copied_screenshot_path).st_size
                    })

            keywords = localized.get('keywords', defaults['keywords'])

            # sanitize keywords string
            if u'，' in keywords:
                keywords = keywords.replace(u'，', u',')

            keywords = map(unicode.strip, keywords.split(u','))

            # add any important keywords if they don't exist
            # if u'Psiphon Pro' not in keywords:
            #     keywords = keywords[:1] + ["Psiphon Pro"] + keywords[1:]

            context = {
                'locale_name': locale,
                'title': localized.get('app_name', defaults['app_name']),
                'subtitle': localized.get('subtitle', defaults['subtitle']),
                'description': localized.get('description', defaults['description']),
                'keywords': keywords,
                'screenshots': screenshots,
                'privacy_url': privacy_policy_url,
                'support_url': support_url,
                'version_whats_new': whats_new
            }

            return Template(get_locale_xml()).render(context)
    else:
        sys.exit("{} does not exist".format(yaml_file_path))


def create_itmsp_package(output_path, provider, team_id, vendor_id, version_string, whats_new):
    """Creates itmsp package for uploading localized store assets at <output_path>"""
    # Construct package
    itmsp_path = os.path.abspath(os.path.join(output_path, vendor_id + '.itmsp'))
    if os.path.exists(itmsp_path):
        # Delete any pre-existing package at <output_path>
        shutil.rmtree(itmsp_path)

    os.mkdir(itmsp_path, 0744)

    with open("StoreAssets/master.yaml") as f:
        # Use english store description as a fallback
        en_yaml = yaml.load(f)['en']

        store_assets_path = os.path.abspath('./StoreAssets')

        # Load the json file which provides metadata used by create_locale_template.
        # This file specifies:
        #   - which languages are supported by Apple and language code mappings from the codes used in
        #     StoreAssets/*.yaml to those used by Apple.
        #   - mappings of <device_name> to display targets that need to be specified in itmsp metadata
        #   - screenshot patterns used for finding screenshot files
        #
        # create_locale_template will look for screenshot files for each screenshot pattern display target pairing.
        # With "<device_name>" replaced with the display target key. For example with the sample json below the
        # screenshots for the en locale would be:
        #   - ./StoreAssets/screenshots/en-US/iPhone 5s-screenshot_name.png
        #   - ./StoreAssets/screenshots/en-US/iPad Pro (12.9 inch)-screenshot_name.png
        # And they would be respectively renamed in the itmsp package as:
        #   - <output_path>/<vendor_id>.itmsp/en-US_iOS-5.5-in_screenshot_name.png
        #   - <output_path>/<vendor_id>.itmsp/en-US_iOS-iPad-Pro_screenshot_name.png
        #
        # The expected format of metadata.json is:
        # '{
        #   "_comments": "..."
        #   "app_store_supported_languages": [
        #     "en",
        #     "fr",
        #     ...
        #   ],
        #   "language_code_mappings": {
        #     "en": "en-US",
        #     ...
        #   },
        #   "display_targets": {
        #     "iPhone 5s": "iOS-5.5-in",
        #     "iPad Pro (12.9 inch)": "iOS-iPad-Pro"
        #     ...
        #   },
        #   "screenshots": [
        #     "filename_pattern": "<device_name>-screenshot_name.png",
        #     ...
        #   ]
        #  }'
        #
        metadata_file_path = os.path.join(store_assets_path, 'metadata.json')
        if os.path.exists(metadata_file_path):
            with open(metadata_file_path) as metadata_file:
                metadata = json.load(metadata_file)

                # Generate itmsp locale xml for each *.yaml file in the ./StoreAssets directory
                yaml_files = filter(lambda filename: filename.endswith('.yaml'), os.listdir("StoreAssets"))
                templates = [create_locale_template(defaults=en_yaml,
                                                    localized_store_strings_yaml=x,
                                                    itmsp_path=itmsp_path,
                                                    store_assets_path=store_assets_path,
                                                    website=psiphon_website_info.PsiphonWebsiteInfo(),
                                                    metadata=metadata,
                                                    whats_new=whats_new)
                             for x in yaml_files]

                # Combine locales to create completed metadata.xml file for upload
                context = {
                    'locales': filter(lambda locale: locale is not None, templates),
                    'provider': provider,
                    'team_id': team_id,
                    'vendor_id': vendor_id,
                    'version_string': version_string
                }
                metadata_template = Template(get_itmsp_xml()).render(context)

                with open(itmsp_path + '/metadata.xml', "wb") as itmsp_metadata_file:
                    itmsp_metadata_file.write(metadata_template.encode('utf8'))
        else:
            sys.exit("Metadata file not found. Exiting...")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(
        description="""
Generate itmsp package for uploading localized store assets (descriptions and screenshots).
The expected directory structure from where run this program is:

 r store_assets_itmsp.py
 r StoreAssets/
 r|-- metadata.json # create_locale_template (see description in create_itmsp_package)
 r|-- master.yaml # default store descriptions (will fallback on these when strings are not yet localized)
  |-- <language_code_1>.yaml
  |-- ...
  |-- <language_code_N>.yaml
 r|-- screenshots
  |   |-- en-US
  |   |   |-- iPad Pro (12.9 inch)-main.png
  |   |   |-- iPad Pro (12.9 inch)-settings.png
  |   |   |-- iPhone 5s-main.png
  |   |   |-- iPhone 5s-settings.png
  |   |   |-- ...
  |   |-- ...
  
  * required files/directories are marked with 'r'. Other files are for example.
        """,
        formatter_class=argparse.RawTextHelpFormatter,
        prog="store_assets_itmsp",
    )

    parser.add_argument("--output_path",
                        help="Output directory. Package named <vendor_id>.itmsp will be created at this location.",
                        required=True, type=str)
    parser.add_argument("--provider",
                        help="Provider ID. Commonly equal to team ID. Can be found with: "
                             "{path_to_iTMSTransporter} -m provider -u {username} -p {password} "
                             "-account_type itunes_connect -v off",
                        required=True, type=str)
    parser.add_argument("--team_id",
                        help="Can be found in *.xcodeproj/project.pbxproj.",
                        required=True, type=str)
    parser.add_argument("--vendor_id",
                        help="Bundle ID of the app. Can be found on iTunes Connect or in Xcode.",
                        required=True, type=str)
    parser.add_argument("--version_string",
                        help="CFBundleShortVersionString found in Info.plist.",
                        required=True, type=str)
    parser.add_argument("--whats_new",
                        help="Description of what is new in this version of the app. Used on the App Store.",
                        required=True, type=str)

    args = parser.parse_args()

    create_itmsp_package(args.output_path,
                         args.provider,
                         args.team_id,
                         args.vendor_id,
                         args.version_string,
                         args.whats_new)

else:
    print("[%s] Initialized as a library" % (datetime.now()))
