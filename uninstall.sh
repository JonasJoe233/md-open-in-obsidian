#!/bin/zsh
# uninstall.sh — remove MDOpener and hand Markdown back to another app.

set -euo pipefail

PREFIX="${PREFIX:-$HOME/.local}"
APP_DIR="${APP_DIR:-$HOME/Applications}"
APP="$APP_DIR/MDOpener.app"
MD_UTI="net.daringfireball.markdown"
# Who should own .md after removal. Obsidian by default — double-clicking will
# open the vault but not navigate, which is the stock behaviour.
NEW_HANDLER="${NEW_HANDLER:-md.obsidian}"

info() { print -P "%F{cyan}==>%f $*" }

if [[ -x "$PREFIX/bin/set-default-handler" ]]; then
  info "handing $MD_UTI back to $NEW_HANDLER"
  "$PREFIX/bin/set-default-handler" "$MD_UTI" "$NEW_HANDLER" || true
fi

info "removing files"
rm -rf "$APP"
rm -f "$PREFIX/bin/md-open-in-obsidian" "$PREFIX/bin/set-default-handler"

LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
"$LSREGISTER" -kill -r -domain local -domain system -domain user >/dev/null 2>&1 || true

print -P "%F{green}done%f — log and config left in place:"
print "  ~/Library/Logs/md-open-in-obsidian.log"
print "  ~/.config/md-open-in-obsidian/"
print "LaunchServices plist backups (if any) are next to:"
print "  ~/Library/Preferences/com.apple.LaunchServices/com.apple.launchservices.secure.plist"
