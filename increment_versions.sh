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
    echo " Usage: ${0} <none|patch|minor|major> [--dry-run]"
    echo ""
    echo " Automatically increments build number and version number based on"
    echo "  the lastest git tag at 'github.com/Psiphon-Inc/psiphon-ios-vpn.git.'"
    echo "  e.g.: '${0} none' increments build number only without changing version number."
    echo "  e.g.: '${0} minor' increments build number and minor version number."
    echo ""
    echo " You can  also manually set versions with:"
    echo " '$ fastlane run increment_build_number build_number:\"<build_number>\"'"
    echo " '$ fastlane run increment_version_number version_number:\"<version_number>\"'"
    exit 1
}

guard_cmd_exists() {
    if ! command -v "$1" &> /dev/null
    then
        echo " ${1} could not be found"
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

# Returns latest git tag (sorted by "creatordate") from "github.com/Psiphon-Inc/psiphon-ios-vpn.git".
# e.g.: "refs/tags/190v1.0.53"
get_psiphon_ios_vpn_main_repo_last_tag () {
    # `git ls-remote` (https://git-scm.com/docs/git-ls-remote.html)
    # lists tags present in the given repository, and sorts them by "-creatordate" (reversed order).
    # 
    # Output is something like:
    #  381a4abfd0b19f3169f1ffbfed04213ebce4648c  refs/tags/190v1.0.53
    #  2484062b691251b45081405e030bcac9dd765c08  refs/tags/189v1.0.52
    # 
    # `head -n1 | cut -f2` will return "refs/tags/190v1.0.53" from the output above.
    git ls-remote --refs --sort="-creatordate" --tags "git@github.com:Psiphon-Inc/psiphon-ios-vpn.git" | 
    head -n1 | 
    cut -f2
}

# From: https://github.com/cloudflare/semver_bash
semver_parse_into () {
    local _RE='[^0-9]*\([0-9]*\)[.]\([0-9]*\)[.]\([0-9]*\)\([0-9A-Za-z-]*\)'
    #MAJOR
    eval "$2=$(echo "$1" | sed -e "s#$_RE#\1#")"
    #MINOR
    eval "$3=$(echo "$1" | sed -e "s#$_RE#\2#")"
    #MINORs
    eval "$4=$(echo "$1" | sed -e "s#$_RE#\3#")"
    #SPECIAL
    eval "$5=$(echo "$1" | sed -e "s#$_RE#\4#")"
}

# Parses build number and version of type used in psiphon-ios-vpn git tags.
#
# Example usage for parsing "refs/tags/190v1.0.53":
# ```
# BUILD_NUM=0
# VERSION_NUM=""
# parse_git_tag_versions_into "refs/tags/190v1.0.53" BUILD_NUM VERSION_NUM
# ```
parse_git_tag_versions_into () {
    
    # Expects $1 to be like: "refs/tags/190v1.0.53"
    # Sets TAG to "190v1.0.53"
    local _TAG
    _TAG=$(echo "$1" | sed 's/^refs\/tags\///')

    # Gets build number from $TAG: "190v1.0.53" -> "190"
    local _BUILD_NUM
    _BUILD_NUM=$(echo "$_TAG" | sed 's/^\([0-9]*\).*/\1/')

    # Gets version number from $TAG: "190v1.0.53" -> "1.0.53"
    local _VERSION_NUM
    _VERSION_NUM=$(echo "$_TAG" | sed 's/[0-9]*v\(.*\)/\1/')

    eval "$2=$_BUILD_NUM"
    eval "$3=$_VERSION_NUM"
}

increment_version_number_into() {
    local _MAJOR=0
    local _MINOR=0
    local _PATCH=0
    local _SPECIAL=""

    # Parses semver $1 into it's parts.
    semver_parse_into "$1" _MAJOR _MINOR _PATCH _SPECIAL

    case $2 in
        patch)
            _PATCH=$((_PATCH + 1))
            ;;
        minor)
            _MINOR=$((_MINOR + 1))
            ;;
        major)
            _MAJOR=$((_MAJOR + 1))
            ;;
        *)
            echo "Incorrect case '${2}'"
            usage
            ;;
    esac

    eval "$3=${_MAJOR}.${_MINOR}.${_PATCH}${_SPECIAL}"
}

# Guards all required commands exist.
guard_cmd_exists git
guard_cmd_exists fastlane

# Parses $1 (version number bump type).
BUMP_TYPE=""
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

# if $2 is unset or null, sets DRY_RUN to false,
# otherwise if it is set to "--dry-run", sets DRY_RUN to true,
# otherwise it is incorrect usage.
if [ -z "${2:-}" ]; then
    DRY_RUN=false
elif [ "$2" = "--dry-run" ]; then
    DRY_RUN=true
else
    usage
fi

# Ensure there are no uncommitted changes (excluding untracked files).
guard_against_uncommitted_changes

# Gets latest tag. (e.g. "refs/tags/190v1.0.53").
GIT_REF_TAG=$(get_psiphon_ios_vpn_main_repo_last_tag)
echo " Git ref tag '${GIT_REF_TAG}'"

# Parses #GIT_REF_TAG for build number, and version number
# and sets $BUILD_NUM and $VERSION_NUM.
#
BUILD_NUM=0
VERSION_NUM=""
parse_git_tag_versions_into "$GIT_REF_TAG" BUILD_NUM VERSION_NUM
echo " Parsed build number: $BUILD_NUM"
echo " Parsed version number: $VERSION_NUM"
echo ""

# Evalutates incremented build number.
INCREMENTED_BUILD_NUM=$((BUILD_NUM + 1))
echo " Incremented build number: ${INCREMENTED_BUILD_NUM}"

# Evalutates incremented version number, if $BUMP_TYPE is not "none".
INCREMENTED_VERSION_NUM=$VERSION_NUM
if [ $BUMP_TYPE != "none" ]; then
    increment_version_number_into "$VERSION_NUM" "$1" INCREMENTED_VERSION_NUM
    echo " Incremented ${1} version number: ${INCREMENTED_VERSION_NUM}"
fi

# If this is not a dry-run, increments build number and version number.
if [ "$DRY_RUN" = false ]; then
    fastlane run increment_build_number build_number:"$INCREMENTED_BUILD_NUM"
    fastlane run increment_version_number version_number:"$INCREMENTED_VERSION_NUM"
fi
