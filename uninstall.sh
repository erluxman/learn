#!/bin/bash
# Remove Learn and reset every permission it was granted.
#   ./uninstall.sh          app + permissions
#   ./uninstall.sh --purge  also its shortcut database, recorded shortcuts and settings
set -uo pipefail
ID=com.erluxman.learn

# Learn took ⌘Space from Spotlight (Settings ▸ General) → give it back.
if [ "$(defaults read "$ID" spotlightMode 2>/dev/null)" = replace ] || [ "$(defaults read "$ID" spotlightMode 2>/dev/null)" = swap ]; then
  defaults write com.apple.symbolichotkeys AppleSymbolicHotKeys -dict-add 64 \
    "<dict><key>enabled</key><true/><key>value</key><dict><key>parameters</key><array><integer>32</integer><integer>49</integer><integer>1048576</integer></array><key>type</key><string>standard</string></dict></dict>"
  /System/Library/PrivateFrameworks/SystemAdministration.framework/Resources/activateSettings -u 2>/dev/null
  echo "Spotlight: ⌘Space restored"
fi

echo "Quitting Learn…"
osascript -e "tell application id \"$ID\" to quit" 2>/dev/null || true
sleep 1; pkill -x Learn 2>/dev/null || true

# Reset permissions BEFORE deleting: tccutil resolves the bundle id through the installed app.
echo "Resetting permissions…"
for service in Accessibility ListenEvent PostEvent; do
  out=$(tccutil reset "$service" "$ID" 2>&1) && echo "  $service: reset" || echo "  $service: $out"
done

for app in /Applications/Learn.app ~/Applications/Learn.app; do
  [ -d "$app" ] && rm -rf "$app" && echo "Removed $app"
done

if [ "${1:-}" = "--purge" ]; then
  rm -rf ~/Library/Application\ Support/Learn && echo "Removed ~/Library/Application Support/Learn"
  defaults delete "$ID" >/dev/null 2>&1 && echo "Removed settings ($ID)"
fi
echo "Done. Login item (if enabled) disappears with the app."
