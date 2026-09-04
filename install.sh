#!/bin/zsh
# install.sh — build MDOpener.app, install the launcher, make it the default
# handler for Markdown. Idempotent: safe to re-run after a git pull.

set -euo pipefail

REPO_DIR="${0:A:h}"
PREFIX="${PREFIX:-$HOME/.local}"
APP_DIR="${APP_DIR:-$HOME/Applications}"
APP="$APP_DIR/MDOpener.app"
LAUNCHER="$PREFIX/bin/md-open-in-obsidian"
BUNDLE_ID="local.mdopener"
MD_UTI="net.daringfireball.markdown"

info() { print -P "%F{cyan}==>%f $*" }
warn() { print -P "%F{yellow}warning:%f $*" >&2 }
die()  { print -P "%F{red}error:%f $*" >&2; exit 1 }

[[ "$(uname)" == "Darwin" ]] || die "macOS only"
[[ -d /Applications/Obsidian.app || -d "$HOME/Applications/Obsidian.app" ]] \
  || warn "Obsidian.app not found in /Applications or ~/Applications"

# 1. launcher scripts
info "installing scripts to $PREFIX/bin"
mkdir -p "$PREFIX/bin"
install -m 755 "$REPO_DIR/bin/md-open-in-obsidian" "$LAUNCHER"
install -m 755 "$REPO_DIR/bin/set-default-handler" "$PREFIX/bin/set-default-handler"
install -m 755 "$REPO_DIR/bin/grant-full-disk-access" "$PREFIX/bin/grant-full-disk-access"

# 2. the .app that receives Finder's Apple Event
info "building $APP"
mkdir -p "$APP_DIR"
rm -rf "$APP"
SCRATCH=$(mktemp -d)
trap 'rm -rf "$SCRATCH"' EXIT
sed "s|__LAUNCHER__|$LAUNCHER|g" \
  "$REPO_DIR/src/MDOpener.applescript" > "$SCRATCH/MDOpener.applescript"
osacompile -o "$APP" "$SCRATCH/MDOpener.applescript"

PLIST="$APP/Contents/Info.plist"
pb() { /usr/libexec/PlistBuddy -c "$1" "$PLIST" >/dev/null 2>&1 || true }

pb "Set :CFBundleIdentifier $BUNDLE_ID"
pb "Add :CFBundleIdentifier string $BUNDLE_ID"
pb "Set :CFBundleName MDOpener"

# osacompile ships a catch-all "*" document type; drop it so MDOpener does not
# advertise itself as a handler for every file on the system.
pb "Delete :CFBundleDocumentTypes"
pb "Add :CFBundleDocumentTypes array"
pb "Add :CFBundleDocumentTypes:0 dict"
pb "Add :CFBundleDocumentTypes:0:CFBundleTypeName string Markdown Document"
pb "Add :CFBundleDocumentTypes:0:CFBundleTypeRole string Editor"
pb "Add :CFBundleDocumentTypes:0:LSHandlerRank string Owner"
pb "Add :CFBundleDocumentTypes:0:LSItemContentTypes array"
pb "Add :CFBundleDocumentTypes:0:LSItemContentTypes:0 string $MD_UTI"
pb "Add :CFBundleDocumentTypes:0:LSItemContentTypes:1 string public.markdown"
pb "Add :CFBundleDocumentTypes:0:CFBundleTypeExtensions array"
integer i=0
for ext in md markdown mdown mkd mdtext; do
  pb "Add :CFBundleDocumentTypes:0:CFBundleTypeExtensions:$i string $ext"
  (( i++ )) || true
done

codesign --force --deep -s - "$APP" >/dev/null 2>&1 \
  || warn "ad-hoc codesign failed; the app may still work"

# 3. register with LaunchServices and claim the Markdown UTI
info "registering with LaunchServices"
LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
"$LSREGISTER" -f "$APP"
sleep 1
"$PREFIX/bin/set-default-handler" "$MD_UTI" "$BUNDLE_ID"

# 4. verify end to end
info "verifying"
RESOLVED=$("$PREFIX/bin/set-default-handler" --show "$MD_UTI")
if [[ "$RESOLVED" == "$BUNDLE_ID" ]]; then
  print -P "%F{green}done%f — double-clicking .md now goes through MDOpener"
  print "  launcher: $LAUNCHER"
  print "  app:      $APP"
  print "  log:      ~/Library/Logs/md-open-in-obsidian.log"
  print ""
  print "macOS will ask once per protected folder (Desktop/Documents/Downloads)"
  print "the first time you open a note there. To skip those prompts entirely:"
  print "  $PREFIX/bin/grant-full-disk-access"
else
  die "handler is '$RESOLVED', expected '$BUNDLE_ID' — see README troubleshooting"
fi
