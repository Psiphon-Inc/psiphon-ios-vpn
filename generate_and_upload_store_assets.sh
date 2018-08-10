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


#!/bin/bash -u

BASE_DIR=$(cd "$(dirname "$0")" ; pwd -P)
iTMSTransporter="/Applications/Xcode.app/Contents/Applications/Application Loader.app/Contents/itms/bin/iTMSTransporter"

cd "${BASE_DIR}"

# Check that the necessary tools are installed
command -v fastlane
if [[ $? != 0 ]]; then
    echo "fastlane could not be found. Exiting..."
    exit 1
fi

command -v python
if [[ $? != 0 ]]; then
    echo "python could not be found. Exiting..."
    exit 1
fi

command -v "${iTMSTransporter}"
if [[ $? != 0 ]]; then
    echo "iTMSTransporter could not be found. Exiting..."
    exit 1
fi

echo "Generating screenshots..."
fastlane snapshot
if [[ $? != 0 ]]; then
    echo "Failed to generate screenshots. Exiting..."
    exit 1
fi

echo "Screenshots generated successfully."
echo "Generating itmsp package..."

short_version_number=$(agvtool what-marketing-version -terse1)

VERSION_STRING="${short_version_number}"

python store_assets_itmsp.py --provider "${PROVIDER}" --team_id "${TEAM_ID}" --vendor_id "${VENDOR_ID}" --whats_new "${WHATS_NEW}" --version_string "${VERSION_STRING}" --output_path "${BASE_DIR}"
if [[ $? != 0 ]]; then
    echo "Failed to generate itmsp package. Exiting..."
    exit 1
fi

ITMSP="${BASE_DIR}/${VENDOR_ID}.itmsp"

"${iTMSTransporter}" -m verify -f "${ITMSP}" -u "${ITUNES_CONNECT_USERNAME}" -p "${ITUNES_CONNECT_PASSWORD}"
if [[ $? != 0 ]]; then
    echo "${ITMSP} failed validation. Exiting..."
    exit 1
fi

echo "Successfully generated itmsp package ${ITMSP}"
echo "Uploading itmsp package to iTunes Connect..."

"${iTMSTransporter}" -m upload -f "${ITMSP}" -u "${ITUNES_CONNECT_USERNAME}" -p "${ITUNES_CONNECT_PASSWORD}"
if [[ $? != 0 ]]; then
    echo "Failed to upload ${ITMSP} to iTunes Connect. Exiting..."
    exit 1
fi

echo "Successfully uploaded ${ITMSP} to iTunes Connect."

