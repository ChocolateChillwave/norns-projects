# norns-projects

Personal repo for monome norns Lua scripts. See `CLAUDE.md` for coding conventions and API notes.

## Structure

Each subfolder is one standalone norns script (copy of what lives in `dust/code/<name>` on the norns device itself).

## Common commands

**Check what's changed:**
```bash
git status
```

**Save changes (do this after editing/adding files):**
```bash
git add .
git commit -m "short description of what changed"
git push
```

**Pull down the latest version (if editing from another PC):**
```bash
git pull
```

**Add a new script folder:**
1. Copy the script folder from norns (`\\norns.local\` or SFTP via WinSCP, `/home/we/dust/code/<script>`) into this repo folder on your PC.
2. `git add .`
3. `git commit -m "Add <script name>"`
4. `git push`

## Notes

- Line endings for `.lua` files are locked to LF via `.gitattributes` — don't need to think about this, it's automatic.
- `data/` and `audio/` folders from norns are intentionally excluded (see `.gitignore`) — those are runtime state/samples, not code.
