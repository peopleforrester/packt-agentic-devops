# VTT enhancements backlog

Ideas for the student web terminal (`scripts/provision/vtt/`) that are not built yet.
Captured so they are not lost; not scheduled.

## 1. Interactive architecture diagram tab (progressive reveal)

A tab in the terminal section (to the left of "Terminal 1"), or a separate webpage the
presenter can point to, showing the whole build as an interactive, staged diagram.

- Start from the bare cluster and progressively reveal components as the build advances
  from Preflight (Phase 0) through Phase 8, with ArgoCD shown as the source of truth that
  reconciles each layer.
- Highlight the current objective so a student always sees where they are and what comes
  next. Advancing a phase lights up that phase's components.
- Dynamic or staged, referable live during the presentation.
- Candidate build: an SVG/HTML diagram driven by the same phase model the lab page uses,
  keyed off `spec/WORKSHOP-SPEC.md` and `components.yaml` so it stays in sync with the
  real component set. Could live at `/diagram` behind the same console nginx.

## 2. Centralized component URL directory for students

A single page where students find the live URLs of components as they come up on their own
cluster, so they can log in and view each one as they build it.

- Covers Backstage, ArgoCD, Grafana, Prometheus, Loki, Tempo, and the rest of the pinned
  set as each becomes reachable.
- Curated per phase, or auto-discovered from Ingress/HTTPRoute/Service annotations on the
  cluster so it reflects what is actually up.
- Reveals per phase, matching the diagram: a component's link activates once its phase has
  landed. Ties naturally to the interactive diagram above.
- Candidate build: a `/links` page behind the console nginx that reads the student's own
  cluster (the VTT already has kubectl wired) and lists the routable endpoints.
