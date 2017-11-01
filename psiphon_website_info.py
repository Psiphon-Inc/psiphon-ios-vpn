#!/usr/bin/env python

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
import json
import re
import urllib2
from datetime import datetime


class PsiphonWebsiteInfo:
    default_language_code = 'en'

    def __init__(self):
        self._localization = self.Localization()

    class Localization:
        def __init__(self):
            self.supported_languages = []
            self.sync()

        def sync(self):
            """Syncs Localization object's state with languages supported programmatically by the Psiphon website"""
            data = urllib2.urlopen(
                'https://bitbucket.org/psiphon/psiphon-circumvention-system/raw/default/Website/docpad.coffee').read()

            # Rough regex for declaration of the form:
            #   languages: ['en', 'fa', 'ar', 'zh', 'bo', '...']
            # This is an attempt to detect which languages are enabled on the Psiphon website.
            #
            # An IndexError will be raised if no matches are found. This will likely occur if
            # the target file in source control changes significantly.
            # In this scenario failing fast seems desirable.
            result = re.search(r'[\s]*languages:.*', data)
            line_match = result.group(0)
            language_codes = re.search('(\'\w+\',?\s*)+', line_match).group(0).replace(' ', '').replace('\'', '').split(
                ',')

            self.supported_languages = language_codes

        def supported(self, code):
            return code in self.supported_languages

        def languages(self):
            return self.supported_languages

    class FAQ:
        def __init__(self):
            self.data = None  # stubbed for extension

        @staticmethod
        def localized_url(code):
            return 'https://psiphon.ca/' + code + '/faq.html'

    class PrivacyPolicy:
        def __init__(self):
            self.data = None  # stubbed for extension

        @staticmethod
        def localized_url(code):
            return 'https://psiphon.ca/' + code + '/privacy.html'

    @property
    def localization(self):
        return self._localization

    def faq_url(self, code):
        """Returns Psiphon faq url for target l10n, falling back on english url"""
        if not self._localization.supported(code):
            code = self.default_language_code
        return self.FAQ.localized_url(code)

    def privacy_policy_url(self, code):
        """Returns Psiphon privacy policy url for target l10n, falling back on english url"""
        if not self._localization.supported(code):
            code = self.default_language_code
        return self.PrivacyPolicy.localized_url(code)


def query_supported_languages_json(website):
    """Returns list of supported language codes in a json string"""
    # Example return value is:
    # '["en", "fr", "es", ...]'
    return json.dumps(website.localization.languages())


def query_supported_languages_with_metadata_json(website, faq=False, privacy_policy=False):
    """Returns mapping of supported language codes to corresponding faq/privacy policy urls in a json string"""
    # Example return value is:
    # '{
    #    "en": {
    #            "faq_url": "https://...",
    #            "privacy_policy_url": "https://..."
    #          }
    #    "fr": {
    #             ...
    #          }
    #    ...
    #  }'
    j = dict()
    if faq or privacy_policy:
        for code in website.localization.languages():
            j[code] = dict()
            if faq:
                j[code]['faq_url'] = website.faq_url(code)
            if privacy_policy:
                j[code]['privacy_policy'] = website.privacy_policy_url(code)

    return json.dumps(j)


def query_language_support_json(website, code, faq=False, privacy_policy=False):
    """Returns json string which indicates whether the language is supported and what the corresponding faq/privacy
       policy urls are"""
    # E.g. the following would be returned if queried with code='fr', faq=True, privacy_policy=True:
    # '{
    #   "supported": true,
    #   "faq_url": "https://psiphon.ca/fr/faq.html",
    #   "privacy_policy_url": "https://psiphon.ca/fr/privacy.html"
    #  }'
    j = dict()
    j['supported'] = website.localization.supported(code)
    if faq:
        j['faq_url'] = website.faq_url(code)
    if privacy_policy:
        j['privacy_policy_url'] = website.privacy_policy_url(code)

    return json.dumps(j)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(
        formatter_class=argparse.RawTextHelpFormatter,
        prog="psiphon_website_info",
    )

    parser.add_argument("-l", "--language_code",
                        help="Query if the given language code is supported on Psiphon's website.",
                        required=False, type=str)
    parser.add_argument("-f", "--faq",
                        help="Provide corresponding faq page info with query results.",
                        required=False, action='store_true')
    parser.add_argument("-p", "--privacy_policy",
                        help="Provide corresponding support page info with query results",
                        required=False, action='store_true')
    args = parser.parse_args()

    psiphon_website = PsiphonWebsiteInfo()

    query_response_json = None
    if not args.language_code:
        if args.faq or args.privacy_policy:
            query_response_json = query_supported_languages_with_metadata_json(psiphon_website,
                                                                               args.faq,
                                                                               args.privacy_policy)
        else:
            query_response_json = query_supported_languages_json(psiphon_website)
    else:
        query_response_json = query_language_support_json(psiphon_website, args.language_code, args.faq,
                                                          args.privacy_policy)

    print query_response_json


else:
    print("[%s] Initialized as a library" % (datetime.now()))
