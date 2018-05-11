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
import datetime
import plistlib
import sys


class CFBundleShortVersionString:
    def __init__(self, version):
        self.major, self.minor, self.patch = version.split('.')

    def increment_major(self):
        self.major = str(int(self.patch)+1)

    def increment_minor(self):
        self.minor = str(int(self.patch)+1)

    def increment_patch(self):
        self.patch = str(int(self.patch)+1)

    def __str__(self):
        return '.'.join([self.major, self.minor, self.patch])


class InfoPlist:

    version_key = 'CFBundleVersion'  # for internal use, development
    short_version_key = 'CFBundleShortVersionString'  # for release versions, app store

    def __init__(self, plist_path, debug=False):
        self.debug = debug
        self.plist_path = plist_path
        self.plist = plistlib.readPlist(self.plist_path)
        self.version = int(self.plist[self.version_key])
        self.short_version = CFBundleShortVersionString(self.plist[self.short_version_key])

    def sync(self):
        self.plist[self.version_key] = str(self.version)
        self.plist[self.short_version_key] = str(self.short_version)
        plistlib.writePlist(self.plist, self.plist_path)

    def inc_short_version(self):
        self.short_version.increment_patch()
        if self.debug == False:
            self.sync()
        return self.short_version

    def inc_version(self):
        self.version += 1
        if self.debug == False:
            self.sync()
        return self.version


if __name__ == "__main__":

    parser = argparse.ArgumentParser(
        formatter_class=argparse.RawTextHelpFormatter,
        prog="inc_info_plist",
    )

    parser.add_argument("-p",
                        "--plist",
                        help="Path to the Info.plist file in your Xcode project that you wish to increment",
                        required=True,
                        type=str)
    
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument("--short_version", action='store_true')
    group.add_argument("--version", action='store_true')

    parser.add_argument("-d",
                        "--debug",
                        help="Specify that the program should run in debug mode and not flush any data to disk",
                        required=False,
                        action='store_true')

    args = parser.parse_args()

    info_plist = InfoPlist(args.plist, args.debug)

    if args.short_version:
        print(info_plist.inc_short_version())
    elif args.version:
        print(info_plist.inc_version())
