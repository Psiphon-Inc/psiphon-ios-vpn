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


#!/bin/bash -u -e

BASE_DIR=$(cd "$(dirname "$0")" ; pwd -P)
altool="/Applications/Xcode.app/Contents/Applications/Application Loader.app/Contents/Frameworks/ITunesSoftwareService.framework/Versions/A/Support/altool"

usage () {
    echo " Usage: ${0} <release|testflight|internal>"
    echo ""
    echo " This script can be used to create various Psiphon iOS VPN builds for different distribution platforms. I.E. app store, testflight and internal testing."
    exit 1
}

setup_env () {
    cd ${BASE_DIR}

    PSIPHON_IOS_VPN_XCODE_WORKSPACE="${BASE_DIR}"

    # The location of the final build
    BUILD_DIR="${PSIPHON_IOS_VPN_XCODE_WORKSPACE}/build/${TARGET_DISTRIBUTION_PLATFORM}"

    # Clean previous output
    rm -rf "${BUILD_DIR}"

    # Get the latest config values
    python psi_export_doc.py
    if [[ $? != 0 ]]; then
        echo "psi_export_doc.py failed. Failed to update config values. See psi_export_doc.log for details..."
        exit 1
    fi
}

build () {
    # Install pods
    pod install --repo-update

    # Build
    xcodebuild -workspace "${PSIPHON_IOS_VPN_XCODE_WORKSPACE}/Psiphon.xcworkspace" -scheme Psiphon -sdk iphoneos -configuration "${CONFIGURATION}" archive -archivePath "${BUILD_DIR}/Psiphon.xcarchive"
    if [[ $? != 0 ]]; then
        echo "xcodebuild failed. Failed to create Psiphon.xcarchive, aborting..."
        exit 1
    fi
    xcodebuild -exportArchive -archivePath "${BUILD_DIR}/Psiphon.xcarchive" -exportOptionsPlist "${PSIPHON_IOS_VPN_XCODE_WORKSPACE}/${EXPORT_OPTIONS_PLIST}" -exportPath "${BUILD_DIR}"
    if [[ $? != 0 ]]; then
        echo "xcodebuild failed. Failed to export Psiphon.xcarchive, aborting..."
        exit 1
    fi

    # Jenkins loses symlinks from the framework directory, which results in a build
    # artifact that is invalid to use in an App Store app. Instead, we will zip the
    # resulting build and use that as the artifact.
    cd "${BUILD_DIR}"
    zip --recurse-paths --symlinks build.zip * --exclude "*.DS_Store"

    echo "BUILD DONE"
}

increment_build_numbers_for_release () {
    increment_plists_and_commit release
}

increment_build_numbers_for_testflight () {
    increment_plists_and_commit testflight
}

increment_plists_and_commit () {
    git pull
    container_commit_message=$(python "${PSIPHON_IOS_VPN_XCODE_WORKSPACE}/info_plist.py" --plist "${PSIPHON_IOS_VPN_XCODE_WORKSPACE}/Psiphon/Info.plist" --increment_for $1 --output human_readable)
    if [[ $? != 0 ]]; then
        echo "Incrementing container plist failed, aborting..."
        exit 1
    fi
    extension_commit_message=$(python "${PSIPHON_IOS_VPN_XCODE_WORKSPACE}/info_plist.py" --plist "${PSIPHON_IOS_VPN_XCODE_WORKSPACE}/PsiphonVPN/Info.plist" --increment_for $1 --output human_readable)
    if [[ $? != 0 ]]; then
        echo "Incrementing extension plist failed, aborting..."
        exit 1
    fi
    if [[ "$container_commit_message" != "" ]] && [[ "$container_commit_message" != "$extension_commit_message" ]]; then
        echo "Container and extension version numbers out of sync, aborting..."
        exit 1
    fi

    commit_message="${container_commit_message}"
    git add "${PSIPHON_IOS_VPN_XCODE_WORKSPACE}/Psiphon/Info.plist"
    git add "${PSIPHON_IOS_VPN_XCODE_WORKSPACE}/PsiphonVPN/Info.plist"

    git commit -m "${commit_message}"
    if [[ $? != 0 ]]; then
        echo "Failed to git commit plist changes, aborting..."
        exit 1
    fi
}

upload_ipa () {
    echo "Validating exported ipa..."
    "${altool}" --validate-app -f "${BUILD_DIR}/Psiphon.ipa" -u "${ITUNES_CONNECT_USERNAME}" -p "${ITUNES_CONNECT_PASSWORD}"
    if [[ $? != 0 ]]; then
        echo "Psiphon.ipa failed validation, aborting..."
        exit 1
    fi

    echo "Uploading validated ipa to TestFlight..."
    "${altool}" --upload-app -f "${BUILD_DIR}/Psiphon.ipa" -u "${ITUNES_CONNECT_USERNAME}" -p "${ITUNES_CONNECT_PASSWORD}"
    if [[ $? != 0 ]]; then
        echo "Failed to upload Psiphon.ipa, aborting..."
        exit 1
    fi
}

if [ $# -ne 1 ]; then
    usage
fi

TARGET_DISTRIBUTION_PLATFORM=$1

# Option parsing
case $TARGET_DISTRIBUTION_PLATFORM in
    release)
        CONFIGURATION="Release"
        EXPORT_OPTIONS_PLIST="exportAppStoreOptions.plist"
        setup_env
        increment_build_numbers_for_release
        build
        upload_ipa
        ;;
    testflight)
        CONFIGURATION="Release"
        EXPORT_OPTIONS_PLIST="exportAppStoreOptions.plist"
        setup_env
        increment_build_numbers_for_testflight
        build
        upload_ipa
        ;;
    internal)
        CONFIGURATION="Debug"
        EXPORT_OPTIONS_PLIST="exportDevelopmentOptions.plist"
        setup_env
        build
        ;;
    *)
        usage
        ;;
esac

