<!-- ABOUTME: Workshop distribution machinery, not a pattern to copy. The terminal it builds is -->
<!-- ABOUTME: unauthenticated by design of the delivery, and that is a known blocker, not an oversight. -->

# Web terminal image

> **Do not copy this pattern into anything real.**
>
> This image builds the browser terminal that was handed to attendees during a live workshop. Every
> terminal it serves is an unauthenticated, `sudo`-capable, cluster-admin shell on a predictable
> public URL. That is a **known production blocker**, recorded as one, and it is not fixed here.

## What actually happened

On 23 July 2026, during the live delivery, an attendee reached the **instructor's** cluster through
its terminal URL. Terminal hostnames are sequential and enumerable, and nothing on the path checks
who is calling.

Two fixes that look obvious were measured and do not work:

- **Allow-listing at the load balancer cannot allow-list attendees.** The only source address the
  load balancer sees is the router's, so the rule blocks the router and nothing else.
- **An unguessable hostname is not a credential.** Measured 2026-07-25: the cluster load balancer
  answers on its **bare IP** with no Host header, and `/terminal/token` returned an empty token,
  meaning the terminal was running with no credential at all. Anything a router enforces is
  bypassed by dialling the load balancer directly.

The consequence is that enforcement has to happen **at the terminal process itself**, or the public
Service has to stop existing. Neither is done in this image.

## Why it is still in the repository

It is the machinery that delivered the workshop, and the workshop is where the platform's claims
were tested at scale. Deleting it would make the repo tidier and the record less honest.

It is here as **provenance**, not as a recommendation. Nothing in the platform under
`solution/platform/` depends on it, and no phase of the build installs it.

## If you want the pattern done properly

The sibling repository `Unleash_an_Agent_Watch_It_Burn` runs the same delivery shape with the
terminal credential enforced at the terminal process, provisioned per cluster during the build so a
cluster is closed the moment it exists. That is the version to read.

## Full write-up

`docs/fleet/09-lessons-learned.md`, final section, including the 2026-07-25 addendum with the
bare-IP measurement.
