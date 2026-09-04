-- MDOpener — receives the Finder double-click (an `odoc` Apple Event) and hands
-- each file to bin/md-open-in-obsidian.
--
-- Deliberately thin: it detaches immediately so the Finder never waits on the
-- retry loop, and it holds no logic of its own. INSTALL_DIR is substituted at
-- build time by install.sh.

on open theFiles
	repeat with f in theFiles
		set p to POSIX path of f
		try
			do shell script "__LAUNCHER__ " & quoted form of p & " > /dev/null 2>&1 &"
		end try
	end repeat
end open

on run
	-- Launched with no document (e.g. double-clicked in Finder): just show Obsidian.
	try
		do shell script "/usr/bin/open -a Obsidian"
	end try
end run
