#!/bin/bash

set -xev

# Build the project under .build/release/
swift build -c release

# Copies it to /usr/local/bin/ under name appStateParser
cp -f .build/release/parser /usr/local/bin/appStateParser
