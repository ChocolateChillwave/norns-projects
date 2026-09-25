# norns-projects

Personal repo for monome norns Lua scripts. See `CLAUDE.md` for coding conventions and API notes.

## Scripts

Each subfolder is one standalone norns script (copy of what lives in `dust/code/<name>` on the norns device itself).

| Script | What it is | Docs |
|---|---|---|
| [cascade](cascade/) | Chord strumming instrument, out to MIDI and/or Just Friends over crow. Hold a grid cell and the chord under it strums; hold several and they merge into one strum. Arc edits timing, dynamics and pattern while it rings. | [Manual](cascade/MANUAL.md) · [Notes](cascade/NOTES.md) |
| [segue](segue/) | MIDI-out drum sequencer for the Elektron Analog Rytm. Eight lanes of patterns, each with its own playhead and Ableton-style follow actions; eight genre banks of kits, and settings that inherit global → lane → pattern. | [Manual](segue/MANUAL.md) · [Follow actions](segue/FOLLOW.md) · [Notes](segue/NOTES.md) |
| [polyphasic](polyphasic/) | 4-track polymetric MIDI sequencer with generative evolve/randomize, arc paging, and grid entry. Adapted from pitter-patter. | [Notes](polyphasic/NOTES.md) |
| [rytmpatch](rytmpatch/) | CC patch randomizer/editor for the Elektron Analog Rytm MKII. | [Notes](rytmpatch/NOTES.md) |
| [summitpatch](summitpatch/) | Patch randomizer and per-key overlays for the Novation Summit/Peak. | [Notes](summitpatch/NOTES.md) |

Only cascade and segue have a full user manual so far; for the others, `NOTES.md` is the best reference for what the script does and why. Several of these are new — each script's `NOTES.md` says whether it has been run on real hardware yet.

**[ROADMAP.md](ROADMAP.md)** is the cross-script view: where each script stands, what the next move is, and one gathered list of everything waiting on a norns being in front of you.

**[CONVENTIONS.md](CONVENTIONS.md)** is the standard every script here is written to, checked against the norns API source. **[IDEAS.md](IDEAS.md)** is the backlog of candidate new scripts. **[TODO.md](TODO.md)** is the checklist: every open item, tagged by whether it's waiting on you at the norns, on a decision from you, or on desk work. Ask "where am I at?" and that's what gets reviewed.

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

**Run the test suites** (desktop Lua, no norns needed — see `CLAUDE.md`):
```bash
lua run-tests.lua
```

**Add a new script folder:**
1. Copy the script folder from norns (`\\norns.local\` or SFTP via WinSCP, `/home/we/dust/code/<script>`) into this repo folder on your PC.
2. `git add .`
3. `git commit -m "Add <script name>"`
4. `git push`

## Notes

- Line endings for `.lua` files are locked to LF via `.gitattributes` — don't need to think about this, it's automatic.
- `data/` and `audio/` folders from norns are intentionally excluded (see `.gitignore`) — those are runtime state/samples, not code.
