#!/bin/zsh
# Baut Insel, installiert sie nach ~/Applications und startet sie.
#   ./install.sh               bauen + installieren + starten
#   ./install.sh --autostart   zusätzlich beim Login starten
#   ./install.sh --uninstall   alles wieder entfernen
set -e
cd "$(dirname "$0")"
APP="$HOME/Applications/Insel.app"
AGENT="$HOME/Library/LaunchAgents/com.mehmetali.insel.plist"

launchctl bootout "gui/$(id -u)" "$AGENT" 2>/dev/null || true
pkill -x Insel 2>/dev/null && sleep 1 || true

if [[ "$1" == "--uninstall" ]]; then
    rm -f "$AGENT"
    rm -rf "$APP"
    defaults delete com.mehmetali.insel 2>/dev/null || true
    echo "Insel entfernt."
    exit 0
fi

swift build -c release
rm -rf build/Insel.app
mkdir -p build/Insel.app/Contents/MacOS "$HOME/Applications"
cp .build/release/Insel build/Insel.app/Contents/MacOS/
cp Info.plist build/Insel.app/Contents/
# Mit festem Zertifikat signieren, damit macOS Freigaben (Bedienungshilfen) über Neubauten hinweg behält
if security find-identity -p codesigning | grep -q "Insel Dev"; then
    codesign --force --sign "Insel Dev" build/Insel.app
else
    codesign --force --sign - build/Insel.app
fi
rm -rf "$APP"
cp -R build/Insel.app "$APP"

if [[ "$1" == "--autostart" || -f "$AGENT" ]]; then
    mkdir -p "$HOME/Library/LaunchAgents"
    cat > "$AGENT" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.mehmetali.insel</string>
    <key>ProgramArguments</key>
    <array>
        <string>$APP/Contents/MacOS/Insel</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>ProcessType</key>
    <string>Interactive</string>
</dict>
</plist>
EOF
    launchctl bootstrap "gui/$(id -u)" "$AGENT"
    echo "Installiert mit Autostart: $APP"
else
    open "$APP"
    echo "Installiert: $APP"
fi
