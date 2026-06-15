# Prompt Library

Every live Claude Code prompt, rehearsed verbatim. Improvised prompting during delivery is limited to Q&A. Each prompt maps to a beat ID from the build spec (section 7) and a backup recording slot.

Built phase by phase. Entries are filled as each module's beats are rehearsed.

## Format for each entry

- ID: P01 onward
- Beat: the matching beat ID (B01 onward)
- Prompt: the exact text
- Expected behavior: what Claude Code should do
- Known failure modes: observed in rehearsal
- Recovery move: what to do when it goes wrong

## Module 1

- P01 (B01): placeholder, read components.yaml and explain the App-of-Apps structure.
- P03 (B03): placeholder, diagnose and heal the scripted Grafana sync failure.

## Module 2

- P05 (B05): placeholder, install kgateway and review the Gateway API resources.
- P07 (B07): placeholder, write the kagent Agent CRD. Most-rehearsed prompt. The CRD is kagent.dev/v1alpha2 with systemMessage under spec.type and spec.declarative.

## Module 3

- P13 (B13): placeholder, write the agent-service scaffolder template.

## Wrap

- placeholders for the Kyverno and attribution beats.
