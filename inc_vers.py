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
from inc_info_plist import InfoPlist
from subprocess import call, check_output


def inc_short_version():
    ref_info_plist = InfoPlist(plist_path="./Psiphon/Info.plist", debug=True)
    next_short_vers = "{}".format(ref_info_plist.inc_short_version())
    call(["agvtool", "new-marketing-version", next_short_vers])


def inc_version():
    call(["agvtool", "next-version", "-all"])


def call_with_output(cmd):
    return check_output(cmd).strip('\n')


if __name__ == "__main__":

    parser = argparse.ArgumentParser(
        formatter_class=argparse.RawTextHelpFormatter,
        prog="inc_vers",
    )

    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument("--testflight", action='store_true')
    group.add_argument("--release", action='store_true')

    args = parser.parse_args()

    active_branch = call_with_output(["git","rev-parse","--abbrev-ref","HEAD"])

    # get most up-to-date version numbers from versioning branch
    call(["git","checkout","versioning"])
    short_version = call_with_output(["agvtool","what-marketing-version","-terse1"])
    version = call_with_output(["agvtool","what-version","-terse"])

    # switch back to active branch
    call(["git","checkout",active_branch])

    # sync active branch version with versioning branch
    call(["agvtool","new-marketing-version",short_version])
    call(["agvtool","new-version","-all",version])

    # increment versions for next release
    inc_version()
    if args.release:
        inc_short_version()

    # commit version changes
    call(["git","add","Psiphon.xcodeproj/project.pbxproj","Psiphon/Info.plist","PsiphonUITests/Info.plist","PsiphonVPN/Info.plist"])
    call(["git","commit","-m","TestFlight version {}; Release version {}".format(version,short_version)])

    # cherry pick commit from active branch to versioning branch
    call(["git","checkout","versioning"])
    call(["git","cherry-pick",active_branch,"--strategy-option","theirs"])

    # return to active branch
    call(["git","checkout",active_branch])

