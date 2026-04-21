#!/usr/bin/env bash
# install.sh — Install Contexto.app to ~/Applications and launch it.
# After this runs, Contexto starts automatically every time you log in.
# You never need to open Terminal again unless you change the source code.

set -e

APP_NAME="Contexto"
APP_BUNDLE="build/${APP_NAME}.app"
INSTALL_DIR="${HOME}/Applications"
INSTALLED_APP="${INSTALL_DIR}/${APP_NAME}.app"

if [ ! -d "${APP_BUNDLE}" ]; then
    echo "ERROR: ${APP_BUNDLE} not found. Run ./build.sh first."
    exit 1
fi

echo "==========================================="
echo "  Installing ${APP_NAME}"
echo "==========================================="

# Create ~/Applications if needed
mkdir -p "${INSTALL_DIR}"

# Copy app
echo "Copying to ${INSTALL_DIR}..."
rm -rf "${INSTALLED_APP}"
cp -R "${APP_BUNDLE}" "${INSTALL_DIR}/"
echo "  Done"

# Flush macOS Services database
echo "Registering Services menu item..."
/System/Library/CoreServices/pbs -flush 2>/dev/null || true
echo "  Done"

# Add to Login Items so it starts automatically at login
echo "Adding to Login Items (starts automatically at login)..."
osascript << APPLESCRIPT 2>/dev/null || true
tell application "System Events"
    set loginItems to every login item whose path is "${INSTALLED_APP}"
    if (count of loginItems) is 0 then
        make new login item at end of login items ¬
            with properties {path:"${INSTALLED_APP}", hidden:false}
    end if
end tell
APPLESCRIPT
echo "  Done"

# Kill any existing instance and relaunch
echo "Launching ${APP_NAME}..."
pkill -x "${APP_NAME}" 2>/dev/null || true
sleep 0.5
open "${INSTALLED_APP}"

echo ""
echo "==========================================="
echo "  Contexto is installed and running!"
echo "==========================================="
echo ""
echo "The menu bar icon will appear in the top-right of your screen."
echo "Contexto now starts automatically every time you log in."
echo ""
echo "YOU ARE DONE WITH TERMINAL."
echo ""
echo "To use Contexto:"
echo "  Select text in any app -> Right-click -> Services -> Define with Contexto"
echo ""
echo "First-time setup (one time only):"
echo "  Click the Contexto icon in the menu bar -> Preferences"
echo "  Enter your OpenAI API key and click Save"
echo ""
echo "IMPORTANT — grant these permissions when macOS asks:"
echo "  1. Automation    (to read your browser tab)"
echo "  2. Accessibility (to read PDFs and other apps)"
echo "  Both are asked once and remembered permanently."
echo ""
echo "If Services does not appear in right-click menus:"
echo "  System Settings -> Keyboard -> Keyboard Shortcuts -> Services"
echo "  Enable 'Define with Contexto'"
