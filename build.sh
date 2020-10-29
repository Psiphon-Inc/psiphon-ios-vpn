#!/bin/bash

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

set -ue

BASE_DIR=$(cd "$(dirname "$0")" ; pwd -P)

usage () {
    echo " Usage: ${0} <release|dev-release|debug> [--dry-run]"
    echo ""
    echo " This script can be used to create various Psiphon iOS VPN builds for different distribution platforms. I.E. app store, testflight and internal testing."
    exit 1
}

setup_env () {
    cd "${BASE_DIR}"

    PSIPHON_IOS_VPN_XCODE_WORKSPACE="${BASE_DIR}"

    # The location of the final build
    BUILD_DIR="${PSIPHON_IOS_VPN_XCODE_WORKSPACE}/build/${TARGET_DISTRIBUTION_PLATFORM}"

    # Clean previous output
    rm -rf "${BUILD_DIR}"

    if ! [ -x "$(command -v xcrun)" ]; then
        echo "Error: 'xcrun' is not installed"
        exit 1
    fi
}

build () {
    # Install pods
    pod install --repo-update

    # Build
    if ! xcodebuild -workspace "${PSIPHON_IOS_VPN_XCODE_WORKSPACE}/Psiphon.xcworkspace" -scheme Psiphon -sdk iphoneos -configuration "${CONFIGURATION}" archive -archivePath "${BUILD_DIR}/Psiphon.xcarchive";
    then
        echo "xcodebuild failed. Failed to create Psiphon.xcarchive, aborting..."
        exit 1
    fi
    
    if ! xcodebuild -exportArchive -archivePath "${BUILD_DIR}/Psiphon.xcarchive" -exportOptionsPlist "${PSIPHON_IOS_VPN_XCODE_WORKSPACE}/${EXPORT_OPTIONS_PLIST}" -exportPath "${BUILD_DIR}";
    then
        echo "xcodebuild failed. Failed to export Psiphon.xcarchive, aborting..."
        exit 1
    fi

    # Jenkins loses symlinks from the framework directory, which results in a build
    # artifact that is invalid to use in an App Store app. Instead, we will zip the
    # resulting build and use that as the artifact.
    cd "${BUILD_DIR}"
    zip --recurse-paths --symlinks build.zip ./* --exclude "*.DS_Store"

    echo "BUILD DONE"
}

upload_ipa () {
    echo "Validating exported ipa..."
    if ! xcrun altool --validate-app -t ios -f "${BUILD_DIR}/Psiphon.ipa" -u "${ITUNES_CONNECT_USERNAME}" -p "${ITUNES_CONNECT_PASSWORD}";
    then
        echo "Psiphon.ipa failed validation, aborting..."
        exit 1
    fi

    echo "Uploading validated ipa to TestFlight..."
    if ! xcrun altool --upload-app -t ios -f "${BUILD_DIR}/Psiphon.ipa" -u "${ITUNES_CONNECT_USERNAME}" -p "${ITUNES_CONNECT_PASSWORD}";
    then
        echo "Failed to upload Psiphon.ipa, aborting..."
        exit 1
    fi
}

# If $1 is unset or null, prints usage.
# More information on parameter expansion: https://pubs.opengroup.org/onlinepubs/9699919799/utilities/V3_chap02.html#tag_18_06_02
if [ -z "${1:-}" ]; then
    usage 
fi

TARGET_DISTRIBUTION_PLATFORM="$1"

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

# Option parsing
case $TARGET_DISTRIBUTION_PLATFORM in
    release)
        CONFIGURATION="Release"
        EXPORT_OPTIONS_PLIST="exportAppStoreOptions.plist"
        setup_env
        build

        if [ "$DRY_RUN" = false ]; then
            upload_ipa
        fi

        ;;
    dev-release)
        CONFIGURATION="DevRelease"
        EXPORT_OPTIONS_PLIST="exportAppStoreOptions.plist"
        setup_env
        build

        if [ "$DRY_RUN" = false ]; then
            upload_ipa
        fi

        ;;
    debug)
        CONFIGURATION="Debug"
        EXPORT_OPTIONS_PLIST="exportDevelopmentOptions.plist"
        setup_env
        build
        ;;
    *)
        usage
        ;;
esac

