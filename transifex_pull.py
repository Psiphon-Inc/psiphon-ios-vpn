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

# To install this dependency on macOS:
# pip install --upgrade setuptools --user python
# pip install --upgrade ruamel.yaml --user python
from ruamel.yaml import YAML
from ruamel.yaml.compat import StringIO


DEFAULT_LANGS = {
    'am': 'am',         # Amharic
    'ar': 'ar',         # Arabic
    'az@latin': 'az',   # Azerbaijani
    'be': 'be',         # Belarusian
    'bo': 'bo',         # Tibetan
    'de': 'de',         # German
    'el_GR': 'el',      # Greek
    'es': 'es',         # Spanish
    'fa': 'fa',         # Farsi/Persian
    'fi_FI': 'fi',      # Finnish
    'fr': 'fr',         # French
    'hr': 'hr',         # Croation
    'id': 'id',         # Indonesian
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
    'tg': 'tg',         # Tajik
    'th': 'th',         # Thai
    'tk': 'tk',         # Turkmen
    'tr': 'tr',         # Turkish
    'uk': 'uk',         # Ukrainian
    'uz': 'uz',         # Uzbek
    'vi': 'vi',         # Vietnamese
    'zh': 'zh-Hans',    # Chinese (simplified)
    'zh_TW': 'zh-Hant'  # Chinese (traditional)
}


RTL_LANGS = ('ar', 'fa', 'he')


UNTRANSLATED_FLAG = '[UNTRANSLATED]'


# From https://yaml.readthedocs.io/en/latest/example.html#output-of-dump-as-a-string
class YAML_StringDumper(YAML):
    def dump(self, data, stream=None, **kw):
        inefficient = False
        if stream is None:
            inefficient = True
            stream = StringIO()
        YAML.dump(self, data, stream, **kw)
        if inefficient:
            return stream.getvalue()


def process_resource(resource, output_path_fn, output_mutator_fn,
                     bom, encoding='utf-8'):
    '''
    `output_path_fn` must be callable. It will be passed the language code and
    must return the path+filename to write to.
    `output_mutator_fn` must be callable. It will be passed `lang, fname, translation`
    and must return the resulting translation. May be None.
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

        output_path = output_path_fn(out_lang)

        # Make sure the output directory exists.
        try:
            os.makedirs(os.path.dirname(output_path))
        except OSError as ex:
            if ex.errno == errno.EEXIST and os.path.isdir(os.path.dirname(output_path)):
                pass
            else:
                raise

        if output_mutator_fn:
            content = output_mutator_fn(out_lang, os.path.basename(output_path), r['content'])
        else:
            content = r['content']

        # Make line endings consistently Unix-y.
        content = content.replace('\r\n', '\n')

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


def yaml_lang_change(to_lang, _, in_yaml):
    """
    Transifex doesn't support the special character-type modifiers we need for some
    languages, like 'ug' -> 'ug@Latn'. So we'll need to hack in the  character-type info.
    """
    return to_lang + in_yaml[in_yaml.find(':'):]


def merge_storeassets_translations(lang, fname, fresh):
    """
    Often using an old translation is better than reverting to the English when
    a translation is incomplete. So we'll merge old translations into fresh ones.
    """

    yml = YAML_StringDumper()
    yml.encoding = None # unicode, which we'll encode when writing the file

    fresh_translation = yml.load(fresh)

    with codecs.open('./StoreAssets/master.yaml', encoding='utf-8') as f:
        english_translation = yml.load(f)

    existing_fname = './StoreAssets/%s' % fname
    try:
        with codecs.open(existing_fname, encoding='utf-8') as f:
            existing_translation = yml.load(f)
    except Exception as ex:
        print('merge_storeassets_translations: failed to open existing translation: %s -- %s\n' % (existing_fname, ex))
        return fresh

    # Transifex does not populate YAML translations with the English fallback
    # for missing values.

    for key in english_translation['en']:
        if not fresh_translation[lang].get(key) and existing_translation[lang].get(key):
            fresh_translation[lang][key] = existing_translation[lang].get(key)

    return yml.dump(fresh_translation)


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
        try:
            english = next(x['value'] for x in english_translation if x['key'] == entry['key'])
        except:
            english = None

        try:
            existing = next(x for x in existing_translation if x['key'] == entry['key'])

            # Make sure we don't fall back on an untranslated value. See comment
            # on function `flag_untranslated_*` for details.
            if UNTRANSLATED_FLAG in existing['comment']:
                existing = None
            else:
                existing = existing['value']
        except:
            existing = None

        fresh_value = entry['value']

        if fresh_value == english and existing is not None and existing != english:
            # DEBUG
            #print('merge_applestrings_translations:', entry['key'], fresh_value, existing)

            # The fresh translation has the English fallback
            fresh_value = existing

        escaped_fresh = fresh_value.replace('"', '\\"').replace('\n', '\\n')

        fresh_merged += '/*%s*/\n"%s" = "%s";\n\n' % (entry['comment'],
                                                      entry['key'],
                                                      escaped_fresh)

    return fresh_merged


def flag_untranslated_applestrings(lang, fname, fresh):
    """
    When retrieved from Transifex, Apple .strings files include all string table
    entries, with the English provided for untranslated strings. This counteracts
    our efforts to fall back to previous translations when strings change. Like so:
    - Let's say the entry `"CANCEL_ACTION" = "Cancel";` is untranslated for French.
      It will be in the French strings file as the English.
    - Later we change "Cancel" to "Stop" in the English, but don't change the key.
    - On the next transifex_pull, this script will detect that the string is untranslated
      and will look at the previous French "translation" -- which is the previous
      English. It will see that that string differs and get fooled into thinking
      that it's a valid previous translation.
    - The French UI will keep showing "Cancel" instead of "Stop".

    While pulling translations, we are going to flag incoming non-translated strings,
    so that we can check later and not use them a previous translation. We'll do
    this "flagging" by putting the string "[UNTRANSLATED]" into the string comment.

    (An alternative approach that would also work: Remove any untranslated string
    table entries. But this seems more drastic than modifying a comment could have
    unforeseen side-effects.)
    """

    fresh_translation = localizable.parse_strings(content=fresh)
    english_translation = localizable.parse_strings(filename='./Shared/Strings/en.lproj/%s' % fname)
    fresh_flagged = ''

    for entry in fresh_translation:
        try: english = next(x['value'] for x in english_translation if x['key'] == entry['key'])
        except: english = None

        if entry['value'] == english:
            # DEBUG
            #print('flag_untranslated_applestrings:', entry['key'], entry['value'])

            # The string is untranslated, so flag the comment
            entry['comment'] = UNTRANSLATED_FLAG + entry['comment']

        entry['value'] = entry['value'].replace('"', '\\"').replace('\n', '\\n')

        fresh_flagged += '/*%s*/\n"%s" = "%s";\n\n' % (entry['comment'],
                                                       entry['key'],
                                                       entry['value'])

    return fresh_flagged


def pull_ios_app_translations():
    resources = (
        ('ios-vpn-app-localizablestrings', 'Localizable.strings'),
    )

    def mutator_fn(lang, fname, content):
        content = merge_applestrings_translations(lang, fname, content)
        content = flag_untranslated_applestrings(lang, fname, content)
        return content

    for resname, fname in resources:
        process_resource(resname,
                         lambda lang: './Shared/Strings/%s.lproj/%s' % (lang, fname),
                         mutator_fn,
                         bom=False)
        print('%s: DONE' % (resname,))


def pull_ios_asset_translations():
    resname = 'ios-vpn-app-store-assets'

    def mutator_fn(lang, fname, content):
        content = yaml_lang_change(lang, fname, content)
        content = merge_storeassets_translations(lang, fname, content)
        return content

    process_resource(
        resname,
        lambda lang: './StoreAssets/%s.yaml' % (lang, ),
        mutator_fn,
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
    pull_ios_app_translations()

    pull_ios_asset_translations()

    print('FINISHED')


if __name__ == '__main__':
    go()
