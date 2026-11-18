# Polish (clean-up of the transcript)

- **ID:** `polish`
- **Tier:** Gratuit (Free) — needs Apple Intelligence or a downloaded rewrite model
- **Targets:** DictusApp + DictusKeyboard + DictusCore
- **Screens:** `app.settings.smart-mode-model` — see [screens.md](screens.md)

## Sub-features

- `polish.toggle`: « Polir la transcription » switch in Réglages → Modèle des modes intelligents.
- `polish.clean-up`: After transcription, fillers and punctuation are cleaned up without changing the meaning.
- `polish.in-keyboard`: The same clean-up runs for dictations made from the keyboard.
- `polish.debug`: A hidden debug screen (tap « Version » five times).

## How to get to it (user POV)

1. Open Riff → Settings → Smart Mode model and select Apple Intelligence or a downloaded model.
2. Turn on **Polish transcription**.
3. Dictate as usual; the text arrives cleaned up.

## Driving it with axe + Argent

```bash
.claude/skills/verify-dictus-ios/scripts/launch.sh --skip-onboarding
.claude/skills/verify-dictus-ios/scripts/drive.sh tab Réglages
.claude/skills/verify-dictus-ios/scripts/drive.sh tap-id settings.smartModeModel
axe tap --label "Polir la transcription" --element-type CheckBox --wait-timeout 5 --udid <udid>   # the switch; a tap on the row's title does not flip it
.claude/skills/verify-dictus-ios/scripts/drive.sh tree | grep -A3 '"Polir la transcription"'   # AXValue flips
```

Debug builds show the toggle even without Apple Intelligence (`DICTUS_POLISH_DEBUG_VISIBLE`).

## Gotchas

- The downloaded models can polish in the simulator. Apple Intelligence requires a compatible iPhone.
- The text under the toggle and « Open iPhone Settings » follow the app language (#792; FR, EN, DE, ES captures in `docs/agents/evidence/792/`). The simulator reaches only the « Apple Intelligence not enabled » state; the other footer sentences are pinned in the catalog by `SettingsFrenchCopyTests`.
