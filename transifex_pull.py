#!/usr/bin/env python3
# -*- coding: utf-8 -*-

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

'''
Pulls and massages our translations from Transifex.

Run with
# If you don't already have pipenv:
$ python3 -m pip install --upgrade pipenv

$ pipenv install --ignore-pipfile
$ pipenv run python transifex_pull.py

# To reset your pipenv state (e.g., after a Python upgrade):
$ pipenv --rm
'''


import transifexlib


DEFAULT_LANGS = {
    'am': 'am',         # Amharic
    'ar': 'ar',         # Arabic
    'az@latin': 'az',   # Azerbaijani
    'be': 'be',         # Belarusian
    'bo': 'bo',         # Tibetan
    'bn': 'bn',         # Bengali
    'de': 'de',         # German
    'el_GR': 'el',      # Greek
    'es': 'es',         # Spanish
    'fa': 'fa',         # Farsi/Persian
    'fa_AF': 'fa-AF',   # Dari (Afgan Farsi)
    'fi_FI': 'fi',      # Finnish
    'fr': 'fr',         # French
    'he': 'he',         # Hebrew
    'hi': 'hi',         # Hindi
    'hr': 'hr',         # Croation
    'id': 'id',         # Indonesian
    'it': 'it',         # Italian
    'kk': 'kk',         # Kazakh
    'km': 'km',         # Khmer
    'ko': 'ko',         # Korean
    'ky': 'ky',         # Kyrgyz
    'my': 'my',         # Burmese
    'nb_NO': 'nb',      # Norwegian
    'nl': 'nl',         # Dutch
    'pt_BR': 'pt-BR',   # Portuguese-Brazil
    'pt_PT': 'pt-PT',   # Portuguese-Portugal
    'ru': 'ru',         # Russian
    'sw': 'sw',         # Swahili
    'tg': 'tg',         # Tajik
    'th': 'th',         # Thai
    'ti': 'ti',         # Tigrinya
    'tk': 'tk',         # Turkmen
    'tr': 'tr',         # Turkish
    'uk': 'uk',         # Ukrainian
    'uz': 'uz',         # Uzbek
    'vi': 'vi',         # Vietnamese
    'zh': 'zh-Hans',    # Chinese (simplified)
    'zh_TW': 'zh-Hant'  # Chinese (traditional)
}


RTL_LANGS = ('ar', 'fa', 'he')


def pull_ios_app_translations():
    resources = (
        ('ios-vpn-app-localizablestrings', 'Localizable.strings'),
    )

    for resname, fname in resources:
        transifexlib.process_resource(f'https://www.transifex.com/otf/Psiphon3/{resname}/',
                                      DEFAULT_LANGS,
                                      './Shared/Strings/en.lproj/Localizable.strings',
                                      lambda lang: './Shared/Strings/%s.lproj/%s' % (lang, fname), 
                                      transifexlib.merge_applestrings_translations, 
                                      bom=False)
        print('%s: DONE' % (resname,))


def pull_ios_asset_translations():
    resname = 'ios-vpn-app-store-assets'

    def mutator_fn(master_fpath, lang, fname, content):
        content = transifexlib.yaml_lang_change(lang, fname, content)
        content = transifexlib.merge_yaml_translations(master_fpath, lang, fname, content)
        return content

    transifexlib.process_resource( 
        f'https://www.transifex.com/otf/Psiphon3/{resname}/',
        DEFAULT_LANGS,
        './StoreAssets/master.yaml',
        lambda lang: './StoreAssets/%s.yaml' % (lang, ),
        mutator_fn,
        bom=False)
    print('%s: DONE' % (resname, ))


def go():
    pull_ios_app_translations()

    pull_ios_asset_translations()

    print('FINISHED')


if __name__ == '__main__':
    go()
