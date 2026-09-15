# polyphasic — status notes

4-track polymetric/polyphasic MIDI sequencer, adapted from open-source "pitter-patter." MIDI-out only, no internal sound engine.

## Key decisions
- Kept pitter-patter's grid-position-equals-note approach; note pool is scale-aware/quantized to a chosen scale
- Division list extended with odd/triplet divisions
- Removed mx.samples / sample-engine integration (was ~22% CPU on one track) since this build is MIDI-out only
- Visual: abstract glowing orbs, one per track — x = track lane, y = pitch just played, velocity shapes peak brightness + fade/decay time
- Interface kept minimal, visual style inspired by Torso Electronic S4

## Open items
- (add anything still unresolved here as it comes up)
