#!/bin/bash

GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

ICONS_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/icons"
THEME_DIR="$ICONS_DIR/Exhibit"

echo "► Installing Exhibit Icon Theme..."

# Ensure the local icons directory exists
mkdir -p "$ICONS_DIR"

# Remove existing installation to ensure a clean link
rm -rf "$THEME_DIR"

# Create symlink
if ln -s "$PWD" "$THEME_DIR"; then
	echo -e "${GREEN}✓ Successfully installed!${NC}"
	echo "Symlink: $THEME_DIR -> $PWD"
else
	echo -e "${RED}✗ Installation failed!${NC}"
	exit 1
fi
