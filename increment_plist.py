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


#!/usr/bin/env python

import argparse
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

    version_key = 'CFBundleVersion' # for internal use, development
    short_version_key = 'CFBundleShortVersionString' # for release versions, app store

    def __init__(self, plist_path, debug=False):
        self.debug = debug
        self.plist_path = plist_path
        self.plist = plistlib.readPlist(self.plist_path)
        self.version = int(self.plist[self.version_key])
        self.short_version = CFBundleShortVersionString(self.plist[self.short_version_key])

    def sync(self):
        if self.plist[self.version_key] != str(self.version_key):
            if self.debug:
                print '{0} updated from {1} to {2}'.format(self.version_key, self.plist[self.version_key], self.version)
        if self.plist[self.short_version_key] != str(self.short_version):
            if self.debug:
                print '{0} updated from {1} to {2}'.format(self.short_version_key, self.plist[self.short_version_key], self.short_version)
        self.plist[self.version_key] = str(self.version)
        self.plist[self.short_version_key] = str(self.short_version)
        plistlib.writePlist(self.plist, self.plist_path)

    def increment_for_release(self):
        self.version += 1
        self.short_version.increment_patch()
        self.sync()

    def increment_for_testflight(self):
        self.version += 1
        self.sync()

    def version_string_for_release(self):
        return 'TestFlight version {0}; Release version {1}'.format(self.version, self.short_version)

    def version_string_for_testflight(self):
        return 'TestFlight version {0}'.format(self.version)

if __name__ == "__main__":

    parser = argparse.ArgumentParser(
        formatter_class=argparse.RawTextHelpFormatter,
        prog="increment_plist",
    )

    parser.add_argument("-p", "--plist", help="Path to the Info.plist file in your Xcode project that you wish to increment", required=True, type=str)
    parser.add_argument("-d", "--distribution_platform", help="Specify which platform the build will be distributed on: <release|testflight>.", required=True, type=str)
    parser.add_argument("-v", "--version_string", help="Specify that only the new version string should be printed to stdout. Useful for bash scripting.", required=False, action='store_true')
    args = parser.parse_args()

    info_plist = InfoPlist(args.plist)

    if args.distribution_platform == 'release':
        info_plist.increment_for_release()
        if args.version_string:
            print info_plist.version_string_for_release()
    elif args.distribution_platform == 'testflight':
        info_plist.increment_for_testflight()
        if args.version_string:
            print info_plist.version_string_for_testflight()
    else:
        sys.exit('Invalid distribution platform specified. Must be "release" or "testflight"')

else:
    print("[%s] Initialized as a library" % (datetime.now()))
