# md-open-in-obsidian

[中文](README.zh-CN.md)

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

## Permission prompts

macOS gates `~/Desktop`, `~/Documents`, and `~/Downloads` behind TCC. MDOpener
never reads your notes — Obsidian does that — but it does read
`<vault>/.obsidian/workspace.json` to confirm a jump landed, and that read is
what triggers *"MDOpener would like to access files in your Downloads folder"*.

The prompt appears **once per folder** and macOS remembers the answer, so for a
typical setup this is two or three clicks, ever. Allowing them is the smaller
grant and the recommended choice.

If you would rather see no prompt at all, Full Disk Access covers every folder
at once:

```sh
~/.local/bin/grant-full-disk-access          # opens the right pane, reveals the app
~/.local/bin/grant-full-disk-access --check  # report status and exit
```

The grant cannot be scripted — `/Library/Application Support/com.apple.TCC/TCC.db`
is root-owned and `tccd` rejects third-party writes even as root while SIP is
enabled. The helper does the automatable parts: it reports which vaults are
currently readable, opens System Settings on the exact pane, and reveals
`MDOpener.app` in the Finder so it can be dragged in.

Status is read from the launcher's own log rather than probed directly, because
TCC is per process — a terminal that happens to hold Full Disk Access would
report success while MDOpener still fails.

Declining costs you only the verification step: notes still open correctly,
they are just recorded as `OK unverified` rather than confirmed.

## Known limitations

**Filenames containing `#` fall back to the other app.** Obsidian's URI parser
runs the path through `decodeURI`, which by design does not decode reserved
characters — `%23` survives as a literal `%23`, so the path no longer exists.
`?vault=&file=`, `obsidian://vault/<name>/<path>`, double-encoding, and calling
`LSOpenCFURLRef` directly instead of `/usr/bin/open` were all tested; every one
fails the same way. Since no amount of retrying can fix it, such files are
handed to `fallback_app` immediately rather than spinning. Spaces, `&`, `+`,
`%`, and non-ASCII names all work.

**Vaults under TCC-protected directories cannot be verified without a grant.**
If a vault lives in `~/Downloads`, `~/Documents`, or `~/Desktop`, reading its
`.obsidian/workspace.json` returns `EPERM` until access is allowed — even though
the note itself opens fine. In that case the URI is fired once and logged as
`OK unverified` rather than retried blind. See [Permission prompts](#permission-prompts).

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
| `bin/grant-full-disk-access` | Reports TCC status per vault and walks you through the grant |
| `src/MDOpener.applescript` | Source for the `.app` that receives the Finder event |
| `install.sh` / `uninstall.sh` | Idempotent setup and teardown |

## License

MIT
