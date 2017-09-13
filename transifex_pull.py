#!/usr/bin/env python
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
'''

from __future__ import print_function
import os
import sys
import errno
import json
import codecs
import argparse
import requests
import localizable
import yaml


DEFAULT_LANGS = {
    'ar': 'ar',         # Arabic
    'de': 'de',         # German
    'bo': 'bo',         # Tibetan
    'el_GR': 'el',      # Greek
    'es': 'es',         # Spanish
    'fa': 'fa',         # Farsi/Persian
    'fi_FI': 'fi',      # Finnish
    'fr': 'fr',         # French
    'hr': 'hr',         # Croation
    'id': 'id',         # Indonesian
    #'it': 'it',         # Italian
    #'kk': 'kk',         # Kazakh
    'km': 'km',         # Khmer
    'ko': 'ko',         # Korean
    'nb_NO': 'nb',      # Norwegian
    'nl': 'nl',         # Dutch
    'pt_BR': 'pt-BR',   # Portuguese-Brazil
    'pt_PT': 'pt-PT',   # Portuguese-Portugal
    'ru': 'ru',         # Russian
    'th': 'th',         # Thai
    'tk': 'tk',         # Turkmen
    'tr': 'tr',         # Turkish
    #'ug': 'ug@Latn',    # Uighur (latin script)
    'vi': 'vi',         # Vietnamese
    'zh': 'zh-Hans',    # Chinese (simplified)
    'zh_TW': 'zh-Hant'  # Chinese (traditional)
}


RTL_LANGS = ('ar', 'fa', 'he')


def process_resource(resource, output_path_fn, output_mutator_fn, output_merge_fn,
                     bom, encoding='utf-8'):
    '''
    `output_path_fn` must be callable. It will be passed the language code and
    must return the path+filename to write to.
    `output_mutator_fn` must be callable. It will be passed the output and the
    current language code. May be None.
    '''

    langs = DEFAULT_LANGS

    print('\nResource: %s' % (resource,))

    # Check for high-translation languages that we won't be pulling
    stats = request('resource/%s/stats' % (resource,))
    for lang in stats:
        if int(stats[lang]['completed'].rstrip('%')) > 35:
            if lang not in langs and lang != 'en':
                print('Skipping language "%s" with %s translation (%d of %d)' %
                      (lang, stats[lang]['completed'],
                       stats[lang]['translated_entities'],
                       stats[lang]['translated_entities'] +
                       stats[lang]['untranslated_entities']))

    for in_lang, out_lang in langs.items():
        r = request('resource/%s/translation/%s' % (resource, in_lang))

        if output_mutator_fn:
            # Transifex doesn't support the special character-type
            # modifiers we need for some languages,
            # like 'ug' -> 'ug@Latn'. So we'll need to hack in the
            # character-type info.
            content = output_mutator_fn(r['content'], out_lang)
        else:
            content = r['content']

        # Make line endings consistently Unix-y.
        content = content.replace('\r\n', '\n')

        output_path = output_path_fn(out_lang)

        if output_merge_fn:
            content = output_merge_fn(out_lang, os.path.basename(output_path), content)

        # Path sure the output directory exists.
        try:
            os.makedirs(os.path.dirname(output_path))
        except OSError as ex:
            if ex.errno == errno.EEXIST and os.path.isdir(os.path.dirname(output_path)):
                pass
            else:
                raise

        with codecs.open(output_path, 'w', encoding) as f:
            if bom:
                f.write(u'\uFEFF')
            f.write(content)


def gather_resource(resource, langs=None, skip_untranslated=False):
    '''
    Collect all translations for the given resource and return them.
    '''
    if not langs:
        langs = DEFAULT_LANGS

    result = {}
    for in_lang, out_lang in langs.items():
        if skip_untranslated:
            stats = request('resource/%s/stats/%s' % (resource, in_lang))
            if stats['completed'] == '0%':
                continue

        r = request('resource/%s/translation/%s' % (resource, in_lang))
        result[out_lang] = r['content'].replace('\r\n', '\n')

    return result


def request(command, params=None):
    url = 'https://www.transifex.com/api/2/project/Psiphon3/' + command + '/'
    r = requests.get(url, params=params,
                     auth=(_getconfig()['username'], _getconfig()['password']))
    if r.status_code != 200:
        raise Exception('Request failed with code %d: %s' %
                            (r.status_code, url))
    return r.json()


def yaml_lang_change(in_yaml, to_lang):
    return to_lang + in_yaml[in_yaml.find(':'):]


def html_doctype_add(in_html, to_lang):
    return '<!DOCTYPE html>\n' + in_html


def merge_storeassets_translations(lang, fname, fresh):
    """
    Often using an old translation is better than reverting to the English when
    a translation is incomplete. So we'll merge old translations into fresh ones.
    """

    fresh_translation = yaml.load(fresh)

    with open('./StoreAssets/master.yaml') as f:
        english_translation = yaml.load(f)

    existing_fname = './StoreAssets/%s' % fname
    try:
        with open(existing_fname) as f:
            existing_translation = yaml.load(f)
    except Exception as ex:
        print('merge_storeassets_translations: failed to open existing translation: %s -- %s\n' % (existing_fname, ex))
        return fresh

    # Transifex does not populate YAML translations with the English fallback
    # for missing values.

    for key, value in english_translation['en']:
        if not fresh_translation[lang].get(key) and existing_translation[lang].get(key):
            fresh_translation[lang][key] = existing_translation[lang].get(key)

    return yaml.dump(fresh_translation)


def merge_applestrings_translations(lang, fname, fresh):
    """
    Often using an old translation is better than reverting to the English when
    a translation is incomplete. So we'll merge old translations into fresh ones.
    """
    fresh_translation = localizable.parse_strings(content=fresh)
    english_translation = localizable.parse_strings(filename='./Shared/Strings/en.lproj/%s' % fname)

    try:
        existing_fname = './Shared/Strings/%s.lproj/%s' % (lang, fname)
        existing_translation = localizable.parse_strings(filename=existing_fname)
    except Exception as ex:
        print('merge_applestrings_translations: failed to open existing translation: %s -- %s\n' % (existing_fname, ex))
        return fresh

    fresh_merged = ''

    for entry in fresh_translation:
        try: english = next(x['value'] for x in english_translation if x['key'] == entry['key'])
        except: english = None
        try: existing = next(x['value'] for x in existing_translation if x['key'] == entry['key'])
        except: existing = None

        fresh = entry['value']

        if fresh == english and existing is not None and existing != english:
            # DEBUG
            #print('merge_applestrings_translations:', entry['key'], fresh, existing)

            # The fresh translation has the English fallback
            fresh = existing

        escaped_fresh = fresh.replace('"', '\\"').replace('\n', '\\n')

        fresh_merged += '/*%s*/\n"%s" = "%s";\n\n' % (entry['comment'],
                                                      entry['key'],
                                                      escaped_fresh)

    return fresh_merged


def pull_ios_browser_translations():
    resources = (
        ('ios-vpn-app-localizablestrings', 'Localizable.strings'),
    )

    for resname, fname in resources:
        process_resource(resname,
                         lambda lang: './Shared/Strings/%s.lproj/%s' % (lang, fname),
                         None,
                         merge_applestrings_translations,
                         bom=False)
        print('%s: DONE' % (resname,))


def pull_ios_asset_translations():
    resname = 'ios-browser-app-store-assets'
    process_resource(
        resname,
        lambda lang: './StoreAssets/%s.yaml' % (lang, ),
        yaml_lang_change,
        None,
        bom=False)
    print('%s: DONE' % (resname, ))


# Transifex credentials.
# Must be of the form:
# {"username": ..., "password": ...}
_config = None  # Don't use this directly. Call _getconfig()
def _getconfig():
    global _config
    if _config:
        return _config

    DEFAULT_CONFIG_FILENAME = 'transifex_conf.json'

    # Figure out where the config file is
    parser = argparse.ArgumentParser(description='Pull translations from Transifex')
    parser.add_argument('configfile', default=None, nargs='?',
                        help='config file (default: pwd or location of script)')
    args = parser.parse_args()
    configfile = None
    if args.configfile and os.path.exists(args.configfile):
        # Use the script argument
        configfile = args.configfile
    elif os.path.exists(DEFAULT_CONFIG_FILENAME):
        # Use the conf in pwd
        configfile = DEFAULT_CONFIG_FILENAME
    elif __file__ and os.path.exists(os.path.join(
                        os.path.dirname(os.path.realpath(__file__)),
                        DEFAULT_CONFIG_FILENAME)):
        configfile = os.path.join(
                        os.path.dirname(os.path.realpath(__file__)),
                        DEFAULT_CONFIG_FILENAME)
    else:
        print('Unable to find config file')
        sys.exit(1)

    with open(configfile) as config_fp:
        _config = json.load(config_fp)

    if not _config:
        print('Unable to load config contents')
        sys.exit(1)

    return _config


def go():
    pull_ios_browser_translations()

    # TODO: Add assets resource
    #pull_ios_asset_translations()

    print('FINISHED')


if __name__ == '__main__':
    go()
