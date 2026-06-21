# Agentic DevOps webinar LinkedIn post

- **UUID:** ef101877-9206-461d-ab81-926ed6a02772
- **Created:** 2026-03-06T13:12:35.915891Z
- **Updated:** 2026-03-06T16:02:54.574628Z
- **Messages:** 21

## Summary

**Conversation overview**

The person is a KodeKloud instructor and DevOps content creator planning a 50-minute live webinar titled "Agentic DevOps: The Playbook for Working Engineers" targeting working DevOps and Platform Engineers (primary) and Engineering Managers (secondary), scheduled for April 2026. The session is 50 minutes of presentation plus 10 minutes of Q&A. The conversation began from a compacted prior session that had already established the webinar scope, completed a LinkedIn promotional post, and set a tool-neutral positioning stance (tools as examples, not endorsements) appropriate for a KodeKloud audience.

The core work accomplished in this session was: (1) confirming the tool positioning as neutral/balanced rather than Claude/Anthropic-first; (2) commissioning and receiving a comprehensive Agentic DevOps landscape research report covering the state of the field as of March 2026, including confirmed production deployments, tool landscape, CNCF ecosystem, engineer role shifts, maturity models, and a 30/60/90-day adoption framework; (3) building a full webinar framework and narrative outline with section-by-section timing, key stats, and structural rationale; (4) expanding that into a complete 30-slide deck document with exact on-screen content and detailed speaker notes including cumulative timing cues, delivery direction, pause markers, and scripted Q&A responses; and (5) initiating the build of the actual PPTX file from those notes.

The webinar narrative arc is structured as WHY NOW → WHAT IT IS → WHAT'S REAL → HOW YOU FIT → WHERE TO START, with a "Midnight Executive" visual theme (navy `#1E2761`, ice blue `#CADCFC`, white). The person's stated preference is for technically credible content grounded in confirmed production deployments rather than vendor claims, with speculative items flagged. The core thesis is that DevOps engineers are positioned to own the agentic layer because agents run on existing infrastructure (Kubernetes, CI/CD, observability tooling). Key case studies used are Elastic (self-healing CI/CD), Datadog Bits AI SRE Agent, Block/Square (Goose + PagerDuty MCP), and Spotify. The five skills framework covers context engineering, agent boundary design, evaluation/evals, agent observability, and multi-agent architecture design. The 90-day plan targets moving organizations from maturity Level 1 to Level 2 with a starting use case of automated CI build failure analysis in advisory mode.

## Michael — 2026-03-06T13:12:37.265961Z

So apparently I'm teaching this webinar coming up but I haven't seen the description before help me craft it quick LinkedIn post for this

Claude Code is writing 100% of Claude code now. But Anthropic has 100+ open dev positions."Boris Cherny's, Head of Claude Code, Anthropicreply: "Someone has to prompt the Claudes, talk to customers, coordinate with other teams, decide what to build next. Engineering is changing and great engineers are more important than ever."In the Agentic DevOps conversation, the engineers who will thrive aren't the ones who can write the most YAML. They're the ones who can design the boundaries for autonomous systems. Who can decide WHEN an AI agent should act on its own and when it needs a human. Who can deploy agents to Kubernetes, monitor what they're doing, and explain to their CTO why the system made the decisions it made.The DevOps skills our learners already have (Kubernetes, Docker, CI/CD, Terraform, cloud platforms) aren't becoming less valuable. They're becoming the foundation that AI agents need to operate.Agents run ON Kubernetes. They deploy through your CI/CD pipelines. They're monitored with your observability tools.Your existing skills aren't being replaced. A new layer is being added on top.The question is: are you building that layer?We're hosting a live session in April to break down exactly what Agentic DevOps means for working engineers, with practical frameworks and a real getting-started playbook.Register here👇 https://kode.wiki/3NhbZLdhashtag#DevOps hashtag#AgenticAI hashtag#AgenticDevOps hashtag#KodeKloud

## Claude — 2026-03-06T13:12:47.364831Z

 

Here's a quick LinkedIn post from your perspective as the presenter:

---

I'm teaching a live session in April that I think a lot of you need to hear.

The Claude Code news is making rounds — AI writing 100% of its own code while Anthropic still has 100+ open engineering roles. Boris Cherny's response said it plainly: someone has to prompt the models, talk to customers, and decide what to build next.

That's the conversation I want to have with working DevOps engineers.

Because here's what I keep seeing: engineers panicking about skills that aren't actually going away. Kubernetes, CI/CD, Terraform, observability — that's not legacy knowledge. That's the infrastructure agents literally run on. You're not being replaced. You're being positioned at the foundation of something bigger.

What IS changing is the layer above it. Agentic systems need engineers who can design boundaries, define decision thresholds, and explain autonomous behavior to leadership when something goes sideways.

That's what this session covers — what Agentic DevOps actually means for your career, and a practical playbook to start building that next layer.

Register here 👇
https://kode.wiki/3NhbZLd

#DevOps #AgenticAI #AgenticDevOps #KodeKloud

---

Kept it first-person, positioned you as someone with a real perspective rather than just "come see my webinar." Let me know if you want it shorter or punchier.

## Michael — 2026-03-06T14:34:39.793675Z

Should I have another post just about devops stays in general

## Claude — 2026-03-06T14:34:47.857447Z

 

Honestly, no — not right now.

You already covered that angle in this post. If you put out another one saying the same thing too close together, it reads as repetitive and dilutes the webinar post's impact.

If you want a second post, make it *different* — something like:

- A specific scenario or story (a real example of an agent running on Kubernetes)
- A contrarian take that challenges something people are getting wrong about agentic AI
- Something data-driven or from a customer/learner interaction

But a general "DevOps is still relevant" post on its own is also pretty saturated territory right now. Everyone's saying that. It needs a sharper angle to cut through.

Save your energy for a follow-up post *after* you get registrations and can say something like "we filled up fast — here's what resonated with people."

## Michael — 2026-03-06T14:36:38.156058Z

Excellent so what should this webinar be about 15 minutes for code cloud what is a genetic deadlocks do I look at like people like Brent Fisher and the other people that we researched before how do I make this a meaningful webinar based on the description that's been submitted

## Claude — 2026-03-06T14:37:00.934513Z

 

Let me pull up what we researched before so I'm not guessing.

I'm not finding prior research on "Brent Fisher" in our past conversations. That name might be from a different context or slightly misremembered — I don't want to guess. Let me ask before building around the wrong person.

Also — while you're answering those, one heads-up: 15 minutes is tight for Agentic DevOps. You can make it work, but it has to be razor-focused — one clear idea, one framework, one call to action. No rabbit holes.

## Michael — 2026-03-06T14:37:48.533535Z

Webinar is a full 50 minutes with 10 minutes for Q&A so this is a full webinar focused on everything that was in the description

## Claude — 2026-03-06T14:37:55.910030Z



Good, that's a real webinar then. A few things I need to nail down before building this out:

## Michael — 2026-03-06T14:38:47.242441Z

Q: Who is the primary audience?
A: Both individual contributors and liters with a primary emphasis on individual contributors

Q: What's the deliverable you want from this session? (Select all that apply)
A: Research on current agentic AI tools and landscape, I think we want to start with research right let's let's get a framework for what's been done and let's figure out our Cutting Edge kind of angle on it and then once we have that then let's start figuring out everything including full outlines with timing as well as speaker notes scripts that slides themselves and all the collateral for it

Q: On the 'Brent Fisher' reference — who did you mean?
A: Not important — skip the thought leaders angle

## Claude — 2026-03-06T14:38:56.471601Z



Good call — research first, then build everything around what's actually true as of March 2026, not what we assume.

A couple of things before I kick this off:

## Michael — 2026-03-06T14:40:43.659060Z

Q: What's the core angle you want to own? This will shape everything.
A: Sorry why wouldn't we touch on all of those in somewhere fashion I mean we always start with why right and then the future of Bill Ops and we want to end with how to get started in practical Frameworks so why wouldn't we do all of that

Q: Any tools you already want to feature or are already familiar with? (Select all that apply)
A: So I want this to primarily be Claude and Claude code and Claude AI and cowork Centric with some leanings towards land graph and you know I'll go workflows can be an agent registration but mainly it's going to be clock code and open AI ends langgraph

## Claude — 2026-03-06T14:40:49.686849Z



Fair point on the angles — you're right, a 50-minute webinar covers all of those in sequence. That's just good narrative structure.

One last clarification before I kick off the research:

## Michael — 2026-03-06T14:41:01.248976Z

Q: Since this is a KodeKloud webinar, how explicit should the Claude/Anthropic positioning be?
A: Neutral — tools are examples, not endorsements

## Claude — 2026-03-06T14:41:22.542794Z



Good. Neutral is the right call for credibility with a technical audience.

Kicking off the research now — I'm going to map the actual state of Agentic DevOps as of March 2026: what's real, what's hype, what tools matter, and what the cutting edge actually looks like so we can build a webinar that doesn't sound like it was written six months ago.

Your Agentic DevOps landscape report is ready. It covers the evolution from AI-assisted to fully agentic DevOps, what's actually in production vs. experimental across tools like Claude Code, GitHub Copilot, and OpenAI Codex, the Kubernetes agent runtime ecosystem, engineer role restructuring, and a practical 30/60/90-day adoption framework. The report includes analyst perspectives from Gartner, Forrester, and DORA, real deployment case studies from Elastic, Datadog, Block, and Spotify, and a detailed breakdown of the last 90 days of cutting-edge developments through March 2026.

## Michael — 2026-03-06T15:29:22.194150Z

So using that report has a basis let's talk about a gentric Bella soon let's create a framework in it outline for that 15-minute code Cloud webinar let's do it

## Claude — 2026-03-06T15:31:46.555205Z

 

Quick clarification before I build this — you said "15-minute" but we confirmed earlier it's 50 minutes + 10 Q&A. I'm going to build for the full 50. If you meant something different, correct me.

Here's what I built and why it's structured this way.

The narrative arc is **WHY NOW → WHAT IT IS → WHAT'S REAL → HOW YOU FIT → WHERE TO START** — that's the classic journey from "should I care?" to "what do I do Monday morning." Every section answers a question the audience is silently asking.

A few things worth flagging before we go further:

**What's strong:** Section 3 (What's Real) is grounded entirely in confirmed production deployments — Elastic, Datadog, Block, Spotify — not vendor promises. That's what will make a technical audience trust you.

**What to watch:** Section 4 (The 5 Skills) is the heaviest lift at 12 minutes. It's the densest section and where you'll need the tightest speaker notes to avoid going over.

**The closing is intentional:** The "go look at your last 5 CI failures" call-to-action is specific and actionable. Better than "register for our course" as the first ask.

When you're ready, tell me which piece you want to build next — slides, speaker notes, or the attendee playbook/takeaway doc.

## Michael — 2026-03-06T15:40:49.284706Z

And let's go ahead and frame that up into a set of slide notes and speaker notes first

## Claude — 2026-03-06T15:46:47.416758Z

 

Let me check the skill file first before I build anything.

Good. The request right now is slide content + speaker notes as a document — I'll build that as an MD file first, then we can use it to drive the actual PPTX build. This is the right order.

This is going to be long — 30 slides, full speaker notes with timing. Building it now.

## Claude — 2026-03-06T15:47:25.095760Z

 

You just asked this — and I already built it. Let me get it in front of you.

That's the full 30-slide document. What's in it:

Every slide has an **ON SCREEN** block (exactly what goes on the slide) and a **SPEAKER NOTES** block with cumulative timing, delivery direction, pause cues, and the actual words to say. Q&A section includes 5 anticipated questions with honest scripted answers. Critical delivery notes at the bottom flag the moments that can make or break the session.

When you're ready, say the word and we build the actual PPTX from this.

## Michael — 2026-03-06T15:57:01.373241Z

Yeah let's do it that's a good idea let's actually build the slides from here go for it

## Claude — 2026-03-06T16:02:54.574628Z

 
