# CLAUDE.md - App Foundry Suitability Agent

## Overview

This repository contains a Claude Code agent that assesses application suitability for deployment on **App Foundry** (Zendesk's Cloud Run platform).

## Repository Structure

```
.
├── agents/
│   └── appfoundry-suitability.md    # Main agent definition
├── setup.sh                          # Installation script
├── README.md                         # User documentation
├── CLAUDE.md                         # This file (developer guide)
└── .gitignore
```

## Agent Design

### Purpose

The agent serves two primary use cases:

1. **Assessment Mode**: Analyze existing codebases for Cloud Run compatibility
2. **Design Mode**: Guide architecture for new applications

### Core Expertise

The agent is an expert in:
- Google Cloud Run constraints and patterns
- Backstage component model
- Stateless architecture design
- Cloud-native authentication (service accounts, JWT)
- Database connection pooling
- Cloud Scheduler integration

### Key Behaviors

**Decisive, not tentative**:
- "This won't work" > "This might have issues"
- Provide specific solutions, not general advice

**Code-first**:
- Show code examples for every fix
- Include before/after comparisons
- Reference specific files and line numbers

**Realistic**:
- Give honest effort estimates (hours/days)
- Identify external dependencies (service accounts, platform team)
- Assess risk levels (LOW/MEDIUM/HIGH)

**Structured output**:
- Use consistent assessment format
- Break into phases (Critical → Optimization → Nice-to-have)
- Provide checklists, not paragraphs

## Common Assessment Patterns

### Pattern 1: Background Job Detection

**Trigger**: APScheduler, cron, daemon, threading.Thread with `while True`

**Response**:
1. Flag as CRITICAL BLOCKER
2. Explain Cloud Run request-driven model
3. Recommend Cloud Scheduler → HTTP endpoint
4. Show code for `/_internal/scheduled_task` endpoint
5. Document Cloud Scheduler setup

### Pattern 2: Browser Auth Detection

**Trigger**: `externalbrowser`, OAuth redirect, interactive login

**Response**:
1. Flag as CRITICAL BLOCKER
2. Explain headless container environment
3. Recommend service account + JWT
4. Show code for service account config
5. Document how to request service account

### Pattern 3: File Storage Detection

**Trigger**: `open(..., 'w')`, `os.makedirs`, SQLite, file uploads

**Response**:
1. Flag as CRITICAL BLOCKER
2. Explain ephemeral filesystem
3. Recommend PostgreSQL or Cloud Storage
4. Show code for database model or GCS upload
5. Explain `/tmp` exception (but still ephemeral)

### Pattern 4: In-Memory State Detection

**Trigger**: Global dict for sessions, `cache = {}`, WebSocket state

**Response**:
1. Flag as CRITICAL BLOCKER
2. Explain container restarts
3. Recommend PostgreSQL with TTL or Redis
4. Show code for database-backed storage
5. Document cleanup pattern

## Edge Cases

### When to say "Not Suitable"

Rare, but valid:
- Real-time multiplayer games (need persistent WebSocket state)
- Heavy ML inference with >60s latency (even with 60min timeout)
- Apps requiring root access or kernel modules
- Apps with strict latency SLAs <50ms (cold start impact)

**Response**: Explain why, suggest alternative (Compute Engine VM, GKE, etc.)

### When to say "Maybe" (with caveats)

- Heavy Django apps (cold start concern, but solvable)
- WebSocket servers (work but unreliable, recommend SSE)
- Large file processing (use `/tmp`, but size limits)

**Response**: Provide solution + trade-offs, let user decide

## Testing the Agent

### Manual Test Cases

1. **Flask + Snowflake externalbrowser** → Should flag auth blocker
2. **APScheduler background job** → Should recommend Cloud Scheduler
3. **File writes to `./uploads/`** → Should recommend database/GCS
4. **In-memory sessions dict** → Should recommend database sessions
5. **Next.js with API routes** → Should approve as compatible

### Validation Checklist

For each assessment, verify output includes:
- [ ] Compatibility score (LOW/MEDIUM/HIGH)
- [ ] Critical blockers with specific problems
- [ ] Code examples for each fix
- [ ] Phased remediation plan
- [ ] Effort estimate (hours or days)
- [ ] Risk assessment
- [ ] Next steps (numbered list)

## Maintaining the Agent

### When to Update

- New Cloud Run features (e.g., new timeout limits)
- App Foundry platform changes (e.g., new auth patterns)
- Common patterns discovered from usage (e.g., new anti-patterns)
- User feedback (unclear recommendations, missing solutions)

### Update Process

1. Edit `agents/appfoundry-suitability.md`
2. Test with existing projects
3. Update README with new examples if needed
4. Commit with descriptive message
5. Users get updates via git pull (symlink tracks repo file)

## Installation Flow

```bash
./setup.sh
  ↓
Check ~/.claude/agents/ exists
  ↓
Remove old symlink if present
  ↓
Create: ~/.claude/agents/appfoundry-suitability.md → agents/appfoundry-suitability.md
  ↓
Success message with usage examples
```

Users can update by:
```bash
cd appfoundry-suitability-agent
git pull
# Symlink automatically points to updated file
```

## Architecture Decisions

### Why a Claude Code Agent?

- Needs full codebase access (file reading, analysis)
- Benefits from conversation context (follow-up questions)
- Can provide inline code fixes
- Integrates with developer workflow (already in Claude Code)

### Why Not a Standalone Tool?

- Would need to duplicate Claude's code analysis capabilities
- Harder to provide context-aware recommendations
- Agent format allows iterative refinement with user

### Why Symlink Installation?

- Agent stays in repo (git pull updates work)
- No need to copy/paste updates
- Single source of truth
- Users can easily uninstall (remove symlink)

## Related Tools

- **appfoundry-architect agent**: Prevents anti-patterns during build (proactive)
- **This agent**: Diagnoses existing codebases (reactive)

**Difference**: 
- `appfoundry-architect` is invoked during development ("I'm building X")
- `appfoundry-suitability` is invoked for assessment ("Can this deploy?")

## Support Scenarios

### User: "Agent not working"
1. Check installation: `ls -la ~/.claude/agents/appfoundry-suitability.md`
2. Verify symlink: `readlink ~/.claude/agents/appfoundry-suitability.md`
3. Re-run setup: `./setup.sh`
4. Restart Claude Code

### User: "Assessment too generic"
- Ask for specific files to review
- Request architecture description
- Ask about specific concerns (auth, state, jobs)

### User: "Solution didn't work"
- Ask for error message
- Review deployed code vs recommended changes
- Check Cloud Run logs
- Verify environment variables set

## Contributing

This is an internal Zendesk tool. Updates should:
- Maintain structured output format
- Include code examples for all recommendations
- Focus on actionable guidance
- Stay specific to App Foundry/Cloud Run

## Links

- **App Foundry Portal**: https://portal.idp.zenai-apps.com
- **Backstage Docs**: https://backstage.io/docs/
- **Cloud Run Docs**: https://cloud.google.com/run/docs
