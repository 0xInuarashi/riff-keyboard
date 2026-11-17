# AGENTS.md — Dictus

## Projet

Dictus — iOS keyboard extension pour dictation vocale offline (WhisperKit).
Voir PRD.md pour les specs complètes et DEVELOPMENT.md pour le guide de développement.

## Stack

- Swift 5.9+ / SwiftUI
- WhisperKit (argmaxinc) via SPM
- FluidAudio (Parakeet STT) via SPM — DictusApp only
- App Group: group.solutions.pivi.dictus
- Minimum iOS: 17.0
- Design: Riff monochrome theme, using native system controls

## Targets Xcode

- **DictusApp** — App principale (onboarding, settings, model manager)
- **DictusKeyboard** — Keyboard Extension (clavier custom + dictation)
- **DictusCore** — Framework partagé (App Group, modèles, préférences)

## Conventions

- Nommage : camelCase pour variables/fonctions, PascalCase pour types/structs
- Un fichier = une responsabilité
- Pas de forceUnwrap (!) sauf cas justifié avec commentaire
- Commentaires en anglais dans le code
- UI strings : français (langue principale) + anglais

## Contraintes importantes

- DictusKeyboard : mémoire max ~50MB → modèles tiny/base/small uniquement
- Pas d'UIApplication.shared dans l'extension keyboard
- Toutes les données partagées passent par App Group
- RequestsOpenAccess = true dans Info.plist de l'extension (pour le micro)

## Contexte utilisateur

- Pierre est débutant en Swift/SwiftUI — expliquer les concepts clés au fur et à mesure
- Toujours expliquer le "pourquoi" derrière les choix d'architecture iOS
- Signaler les patterns Swift importants quand ils sont utilisés pour la première fois

## Brand & Design

Riff uses charcoal and white, fine borders and narrow animated audio bars.
The shared palette, typography and mark live in `DictusCore/Sources/DictusCore/Design/`.
Keep the logo path aligned with the SVG variants in `assets/brand/`.
Run `swift scripts/generate-app-icon.swift` from the repo root to update the app icon PNGs.
The Dictus brand kit remains in the repository as a reference for the original project.

## Agent skills

### Issue tracker

Issues and PRDs live as GitHub issues in `getdictus/dictus-ios`, managed via the `gh` CLI. See `docs/agents/issue-tracker.md`.

### Triage labels

Default canonical labels: `needs-triage`, `needs-info`, `ready-for-agent`, `ready-for-human`, `wontfix`. See `docs/agents/triage-labels.md`.

### Domain docs

Single-context — `CONTEXT.md` + `docs/adr/` at the repo root (created lazily by `/domain-modeling`). See `docs/agents/domain.md`.

### Headless simulator

Boot, build, install, launch, capture, and what a simulator cannot show. See `docs/agents/simulator.md`.

**Smoke test:** `scripts/simulator-smoke-test.sh` runs the app → keyboard → app path headlessly in about two minutes and ends with `SMOKE PASS` or `SMOKE FAIL step N`. Run it while verifying any change to DictusApp, DictusKeyboard, onboarding or the App Group hand-off, and before a TestFlight cut. A pass is not a device validation. See `docs/agents/simulator-smoke-test.md`.
