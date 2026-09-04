# md-open-in-obsidian

Double-clicking a Markdown file on macOS with Obsidian set as the default app
opens Obsidian — but not the file you clicked. You land on whatever tab was
open last. This makes it open the actual note.

## Why it happens

It is not a setting. Obsidian's `open-file` handler — the Apple Event the
Finder sends on double-click — uses the incoming path only to work out which
vault contains the file, then throws the path away:

```js
app.on("open-file", function(event, filePath){
  event.preventDefault();
  let resolved = path.resolve(filePath), matched = "";
  for (let id in vaults) {                        // walk registered vaults
    let vaultPath = vaults[id].path;
    if (resolved.startsWith(vaultPath) && matched.length < vaultPath.length)
      matched = vaultPath;                        // longest matching vault root
  }
  matched && openVault(matched);                  // <- filePath never used again
})
```

*(extracted from `Obsidian.app`'s main-process bundle, v1.13.7; the same shape
is present in earlier versions)*

Meanwhile the `obsidian://` URI handler is a completely separate code path that
*does* navigate to a file. So the fix is not to configure Obsidian — it is to
stop handing it the raw file and hand it a URI instead.

## How this works

```
Finder double-click
      ↓  odoc Apple Event
MDOpener.app            ← claims the Markdown UTI, holds no logic
      ↓  argv
md-open-in-obsidian     ← resolve vault → fire obsidian:// → verify → retry
      ↓  obsidian://open?path=…
Obsidian navigates to the note
```

The interesting part is the verification. There is no reliable "Obsidian is
ready" signal:

- `obsidian.json`'s `open` flag flips to `true` within ~0.5 s of launch, long
  before the window can accept a navigation. Firing on that signal gets the URI
  silently swallowed.
- Fixed sleeps are a guess, and the guess has to be pessimistic to be safe.

So instead of predicting readiness, this reads the vault's own
`.obsidian/workspace.json` and checks whether the target file actually became
the active tab. If it did not, it fires the URI again. Re-firing is idempotent,
so the loop is safe, and it exits the moment the jump lands — typically on the
first attempt (~1 s warm, ~3 s cold).

## Install

```sh
git clone https://github.com/JonasJoe233/md-open-in-obsidian.git
cd md-open-in-obsidian
./install.sh
```

Installs to `~/.local/bin` and `~/Applications` — nothing outside your home
directory, no `sudo`, no dependencies beyond the system Python 3. Re-run it any
time; it is idempotent.

```sh
PREFIX=/opt/homebrew ./install.sh     # override install location
./uninstall.sh                        # hands .md back to Obsidian
NEW_HANDLER=com.microsoft.VSCode ./uninstall.sh
```

## Configuration

Optional, at `~/.config/md-open-in-obsidian/config.json`. Any key can also be
set as an environment variable (`MD_OPEN_FALLBACK_APP` etc.).

```json
{
  "fallback_app": "TextEdit",
  "max_attempts": 6,
  "attempt_timeout": 3.0,
  "poll_interval": 0.25
}
```

`fallback_app` gets files Obsidian cannot open — anything outside every vault,
plus the filename edge case below. Set it to `""` to do nothing instead.

Activity is logged to `~/Library/Logs/md-open-in-obsidian.log` (self-trimming).

## Known limitations

**Filenames containing `#` fall back to the other app.** Obsidian's URI parser
runs the path through `decodeURI`, which by design does not decode reserved
characters — `%23` survives as a literal `%23`, so the path no longer exists.
`?vault=&file=`, `obsidian://vault/<name>/<path>`, double-encoding, and calling
`LSOpenCFURLRef` directly instead of `/usr/bin/open` were all tested; every one
fails the same way. Since no amount of retrying can fix it, such files are
handed to `fallback_app` immediately rather than spinning. Spaces, `&`, `+`,
`%`, and non-ASCII names all work.

**Vaults under TCC-protected directories cannot be verified.** If a vault lives
in `~/Downloads`, `~/Documents`, or `~/Desktop`, reading its
`.obsidian/workspace.json` may return `EPERM` unless the calling process has
been granted Full Disk Access — even though the note itself opens fine. In that
case the URI is fired once and logged as `OK unverified` rather than retried
blind. Grant Full Disk Access to your terminal (or to `MDOpener.app`) if you
want verification there.

**`.mdown` / `.mkd` / `.mdtext` are not claimed.** Those extensions have no
registered UTI on macOS, only a per-machine dynamic one, and LaunchServices
refuses to bind a default handler to those (`kLSNotRegisteredErr`). They are
declared in the app bundle, so they show up under "Open With", but they cannot
be made the default. `.md` and `.markdown` share `net.daringfireball.markdown`
and both work.

**The `.md` icon changes.** `MDOpener.app` is an AppleScript bundle, so Finder
shows its droplet icon for Markdown files. Drop a `.icns` into
`MDOpener.app/Contents/Resources/` and update `CFBundleIconFile` to change it.

## Troubleshooting

**Still opening the old app.** Finder caches handlers per window. Run
`killall Finder`. To confirm what the system will actually use:

```sh
~/.local/bin/set-default-handler --show net.daringfireball.markdown
```

**`install.sh` reports the handler did not change.** On recent macOS,
`LSSetDefaultRoleHandlerForContentType` returns `noErr` while silently
declining to change some UTIs. `set-default-handler` detects this and falls
back to editing `~/Library/Preferences/com.apple.LaunchServices/com.apple.launchservices.secure.plist`
directly, then restarting the per-user `lsd`. It backs the plist up first
(`.bak.<timestamp>` alongside the original). If it still fails, restore the
backup and file an issue with your macOS version.

**Nothing happens at all.** Check the log. `SKIP not a file` means the path did
not survive the Apple Event; `FAIL after N attempts` means the URI was
delivered but the note never became active — worth an issue.

## Repository layout

| Path | Purpose |
|---|---|
| `bin/md-open-in-obsidian` | The logic: vault resolution, URI dispatch, landing verification |
| `bin/set-default-handler` | Sets a UTI's default app, with the plist fallback for when the API lies |
| `src/MDOpener.applescript` | Source for the `.app` that receives the Finder event |
| `install.sh` / `uninstall.sh` | Idempotent setup and teardown |

## License

MIT
