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

set -e

STRINGS_DIR="Shared/Strings/en.lproj"
TEMP_DIR="${STRINGS_DIR}.temp"

mkdir -p "${STRINGS_DIR}"

rm -rf "${TEMP_DIR}"
mkdir -p "${TEMP_DIR}"

# Go through all source files, extracting localizable strings into appropriate
# `x.strings` files in a temp directory.
# NOTE: We are excluding cocoapods files. This may need to be revisited in the future.
find . Pods/InAppSettingsKit -path ./Pods -prune -o -name "*.m" -o -name "*.h" -o -name "*.swift" | xargs genstrings -o ${TEMP_DIR}

# Go through the `x.strings` files, converting from UTF-16 to UTF-8 and moving
# them into their proper location.
find ${TEMP_DIR} -name "*.strings"|while read fname; do
  bname=$(basename ${fname})
  echo "${bname} ${fname}"
  iconv -c -f UTF-16 -t UTF-8 ${fname} > ${STRINGS_DIR}/${bname}
done

rm -rf ${TEMP_DIR}
