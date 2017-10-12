#!/usr/bin/env python
# -*- coding: utf-8 -*-

# NOTE: The master copy of this file is in the psiphon-ios-client-common-library repo.

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

"""
This script extracts strings from source (`.m` and `.plist`) files to create `.strings` files.
"""

from __future__ import print_function
import json
import os
import shutil
import errno
import re
import subprocess
import shlex
import glob
import codecs
import plistlib
from collections import OrderedDict


def load_config():
    """
    Load config from file.
    """
    default_config_filename = 'i18n_conf.json'

    with open(default_config_filename) as config_fp:
        config = json.load(config_fp)

    if not config:
        raise Exception('Unable to load config contents from %s' %
                        default_config_filename)

    return config


def process_objc(config):
    """
    Generate strings file from Objective-C source files.
    """
    # Set up the temp dir
    temp_dir = config['enLprojDir'] + '.temp'
    shutil.rmtree(temp_dir, ignore_errors=True)
    _mkdir_p(temp_dir)

    # Gather our source files
    objc_files = [os.path.join(dirpath, f)
                  for dirpath, _, files in os.walk(config['objcRootDir'])
                  for f in files if re.match(r'.+\.(m|h|swift)$', f)]

    # Exclude ignored dirs
    if config['objcIgnoreDirs']:
        for ignore in config['objcIgnoreDirs']:
            ignore = os.path.join(config['objcRootDir'], ignore)
            objc_files = [f for f in objc_files
                          if os.path.commonprefix([f, ignore]) != ignore]

    # Create the UTF-16LE encoded .strings files with genstrings
    subprocess.check_call(shlex.split(
        'genstrings -o "%s" "%s"' % (temp_dir, '" "'.join(objc_files))))

    # Convert to UTF-8
    for strings_file in glob.glob(os.path.join(temp_dir, '*.strings')):
        with codecs.open(strings_file, 'r', 'utf-16-le') as infile:
            with codecs.open(os.path.join(config['enLprojDir'], os.path.basename(strings_file)),
                             'w', 'utf-8') as outfile:
                outfile.write('/* THIS FILE IS GENERATED. DO NOT EDIT. */\n\n')
                data = infile.read()
                if data[0] == u'\uFEFF':
                    # Strip the BOM
                    data = data[1:]
                outfile.write(data)

    shutil.rmtree(temp_dir, ignore_errors=True)

# From https://stackoverflow.com/a/600612/729729
def _mkdir_p(path):
    """
    Like `mkdir -p`
    """
    try:
        os.makedirs(path)
    except OSError as exc:  # Python >2.5
        if exc.errno == errno.EEXIST and os.path.isdir(path):
            pass
        else:
            raise


PLIST_STRING_KEYS = ['Title', 'ShortTitle', 'FooterText', 'IASKSubtitle', 'IASKPlaceholder']
PLIST_MULTISTRING_KEYS = ['Titles', 'ShortTitles']


def process_plist(plist_fname, strings):
    """
    Copy strings, keys, and comments from `plist_fname` into the
    `strings` dict, which is `key => {'key':..., 'default':..., 'description':...}`
    """
    plist = plistlib.readPlist(plist_fname)
    for item in plist['PreferenceSpecifiers']:
        _process_plist_dict(item, strings)


def _process_plist_dict(plist_dict, strings):
    """
    Helper for process_plist to process a single dict in a plist, which might
    contains strings.
    """
    if not isinstance(plist_dict, dict):
        return

    for multistring_key in PLIST_MULTISTRING_KEYS:
        if multistring_key not in plist_dict:
            continue

        for plist_subdict in plist_dict.get(multistring_key):
            _process_plist_dict(plist_subdict, strings)

    for string_key in PLIST_STRING_KEYS:
        if string_key not in plist_dict:
            continue

        key = plist_dict.get(string_key)
        default = plist_dict.get(string_key + 'Default')
        description = plist_dict.get(string_key + 'Description')

        if not key:
            raise Exception('ERROR: Empty key found: %s' % plist_dict)
        elif not default:
            # Skipping. This is probably an item covered by common-lib.
            print('SKIPPING: %s' % key.encode('utf-8'))
            continue
        elif not description:
            raise Exception(
                'ERROR: Missing string description (if this string belongs to common-lib, '
                'exclude the default; otherwise do not be lazy and add a description): %s'
                % plist_dict)

        default = default.replace('"', '\\"').replace('\n', '\\n')

        if key in strings:
            # The key is already present in strings, so we'll combine the
            # descriptions (if necessary).
            if default != strings[key]['default']:
                raise Exception(
                    'ERROR: key used multiple times with non-matching defaults '
                    '(same key must have same default): %s' % plist_dict)
            elif description != strings[key]['description']:
                strings[key]['description'] += '\n   ' + description
        else:
            strings[key] = {
                'key': key,
                'default': default,
                'description': description}


def process_all_plists(config):
    """
    Extract strings from configured plist files into Root.strings.
    """
    strings = OrderedDict()

    for plist_fname in config['plistFiles']:
        process_plist(plist_fname, strings)

    with codecs.open(os.path.join(config['enLprojDir'], 'Root.strings'),
                     'w', 'utf-8') as strings_file:
        strings_file.write('/* THIS FILE IS GENERATED. DO NOT EDIT. */\n\n')
        for key in strings:
            strings_file.write('/* %s */\n"%s" = "%s";\n\n' % (strings[key]['description'],
                                                               strings[key]['key'],
                                                               strings[key]['default']))


def main():
    """
    Do all of the string extraction work.
    """
    conf = load_config()  # pylint: disable=invalid-name
    process_objc(conf)
    process_all_plists(conf)


if __name__ == '__main__':
    main()
