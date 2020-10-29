#!/bin/bash

# Copyright (c) 2020, Psiphon Inc.
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

set -ue


usage () {
    echo " Usage: ${0} <none|patch|minor|major> [upstram-branch]"
    echo ""
    echo " Bumps build number and version number based on bump type, commiting the changes." 
    echo " If bump type"
    echo " e.g.: '${0} none' increments build number only without changing version number."
    echo " e.g.: '${0} minor upstream/master' increments build number and minor version number, using 'upstream/mater' as the upstream branch."
    exit 1
}

guard_cmd_exists() {
    if ! command -v "$1" &> /dev/null
    then
        echo " ${1} could not be found"
        exit 1
    fi
}

guard_main_branch_checkout_out() {
    # Guards main ("master") branch is checked out.
    ACTIVE_BRANCH=$(git rev-parse --abbrev-ref HEAD)
    if [ "$ACTIVE_BRANCH" != "master" ];then
        echo " Script should be called from the main branch. Called on '$ACTIVE_BRANCH'."
        exit 1
    fi
}

guard_against_uncommitted_changes() {
    if [ -z "$(git status --untracked-files=no --porcelain)" ]; then 
        # Working directory clean excluding untracked files
        true
    else 
        # Uncommitted changes in tracked files
        echo " There are uncommitted changes"
        exit 1
    fi
}

# Guards all required commands exist.
guard_cmd_exists git
guard_cmd_exists agvtool
guard_cmd_exists fastlane

case "${1:-}" in
    none)
        BUMP_TYPE="none"
        ;;
    patch)
        BUMP_TYPE="patch"
        ;;
    minor)
        BUMP_TYPE="minor"
        ;;
    major)
        BUMP_TYPE="major"
        ;;
    *)
        usage
        ;;
esac

# Sets UPSTREAM to $2 if set, otherwise sets value to "@{u}".
UPSTREAM=${2:-'@{u}'}

# Ensure main branch is checked out.
guard_main_branch_checkout_out

# Ensure there are no uncommitted changes (excluding untracked files).
guard_against_uncommitted_changes

# Fetches upstream
git fetch

# Checks if checked-out branch is even with the upstream branch.
# This is to try to guarantee that local branch is even with main upstream branch.
# Solution is inspired by this answer: https://stackoverflow.com/a/3278427
LOCAL=$(git rev-parse @);
REMOTE=$(git rev-parse "$UPSTREAM");
BASE=$(git merge-base @ "$UPSTREAM");

if [ "$LOCAL" = "$REMOTE" ]; then
    echo " This branch is even with upstream"

    # Always increments build number
    echo " Incrementing build number..."
    fastlane run increment_build_number

    # Increments version number if BUMP_TYPE is not "none".
    if [ $BUMP_TYPE != "none" ]; then
        echo " Incrementing @{BUMP_TYPE} version number..."
        fastlane run increment_version_number bump_type:"patch"
    fi

    # Commits files that are changed by incrementing build/version numbers.
    VERSION_NUMBER=$(agvtool what-marketing-version -terse1)
    BUILD_NUMBER=$(agvtool what-version -terse)

    git add Psiphon.xcodeproj/project.pbxproj
    git add ./*/Info.plist
    git commit -m "Build number ${BUILD_NUMBER}; Version number ${VERSION_NUMBER}"

elif [ "$LOCAL" = "$BASE" ]; then
    echo " This branch is behind upstream"
    exit 1

elif [ "$REMOTE" = "$BASE" ]; then
    echo " This branch is ahead of upstream"
    exit 1

else
    echo " This branch has divereged from upstream"
    exit 1
fi
