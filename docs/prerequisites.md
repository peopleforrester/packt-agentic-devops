# Prerequisites

Attendee-facing. Finalized in Phase 6.

## Bring an agentic coding CLI

The workshop is built around Claude Code, so **Claude Code is recommended** for the smoothest experience. You bring your own.

You may bring an equivalent agentic coding CLI instead, as long as it runs headless in the browser terminal, supports a permissioned (non-auto-approve) mode, and ideally has lifecycle hooks for the audit-trail beat. Verified working as of June 2026:

- Claude Code (recommended), OpenAI Codex CLI, GitHub Copilot CLI
- Google Antigravity CLI, Amazon Kiro CLI 2.0
- opencode, Goose, Cursor CLI

**No paid plan? Two free, open-source options work and can use the in-cluster model directly:** opencode (MIT) and Goose (Apache-2.0).

Two products to avoid: **Gemini CLI** (retired for free/Pro/Ultra plans June 18, 2026; bring **Antigravity CLI** instead) and **Amazon Q Developer CLI** (new signups closed May 15, 2026; bring **Kiro CLI** instead). Cursor CLI works but is locked to its own hosted models, so it cannot use the in-cluster model.

## The rest

- Cluster access is provided in the browser. No local Kubernetes setup required.
- A modern web browser.
- Working familiarity with Kubernetes, Helm, and GitOps (Argo CD or Flux experience helps).

No prior Backstage experience required.
