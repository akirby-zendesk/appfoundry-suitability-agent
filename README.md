# App Foundry Suitability Agent

A Claude Code agent that assesses application suitability for deployment on **App Foundry**, Zendesk's internal developer platform built on Google Cloud Run.

## What It Does

This agent helps you:

1. **Assess existing codebases** - Evaluate if your application can deploy to App Foundry and identify blockers
2. **Design new applications** - Get architecture guidance to build Cloud Run-compatible apps from the start
3. **Fix deployment issues** - Diagnose why your app failed on Cloud Run and get remediation steps
4. **Tailored to your role** - Automatically adjusts technical depth based on your proficiency level

## Key Features

✅ **Proficiency-Based Assessments** - Tailors output to 5 levels: Business/Sales, Product Manager, Operations, Developer, Senior Engineer/Architect  
✅ **Cost Estimation** - Provides monthly cost estimates and optimization strategies  
✅ **Comprehensive Template** - 11-section structured assessment covering architecture, security, monitoring, testing, and deployment  
✅ **Cloud Run Expertise** - Deep knowledge of Cloud Run constraints and best practices  
✅ **Code Examples** - Before/after code for every fix (when appropriate for your role)

## Quick Start

### Installation

```bash
cd appfoundry-suitability-agent
./setup.sh
```

This creates a symlink in `~/.claude/agents/` so the agent is available across all your Claude Code sessions.

### Basic Usage

#### Option 1: Assess Existing Project

1. Open your project in Claude Code
2. Invoke the agent:
   ```
   @appfoundry-suitability Can this app deploy to App Foundry?
   ```
3. The agent will analyze your codebase and provide:
   - Compatibility score (LOW/MEDIUM/HIGH)
   - Critical blockers with solutions
   - Step-by-step remediation plan
   - Timeline estimate

#### Option 2: Design New Application

1. Start Claude Code in any directory
2. Invoke the agent:
   ```
   @appfoundry-suitability I want to build a [describe app] for App Foundry
   ```
3. The agent will provide:
   - Recommended tech stack
   - Architecture guidance
   - Code templates
   - Deployment checklist

## Example Scenarios

### Scenario 1: Assess a Flask App

```
@appfoundry-suitability 

I have a Flask app that:
- Connects to Snowflake with externalbrowser auth
- Runs a background scheduler with APScheduler
- Stores user uploads in ./uploads/
- Uses in-memory sessions

Can it deploy to App Foundry?
```

**Expected Output:**
- Compatibility: MEDIUM (fixable)
- 3 critical blockers identified
- Solutions with code examples
- Estimate: 2-3 days

### Scenario 2: Design a New Dashboard

```
@appfoundry-suitability

I need to build a dashboard that:
- Shows Salesforce opportunity data from Snowflake
- Uses AI to summarize account activity
- Refreshes data daily
- Only accessible to Zendesk employees

Design this for App Foundry.
```

**Expected Output:**
- Recommended stack: Python + Flask + PostgreSQL
- Architecture: Cloud Scheduler for daily refresh
- Code template with Pomerium auth
- Deployment steps

### Scenario 3: Troubleshoot Failed Deployment

```
@appfoundry-suitability

My app crashes on Cloud Run with:
"snowflake.connector.errors.DatabaseError: 250001: Could not open browser"

How do I fix this?
```

**Expected Output:**
- Root cause: Browser-based auth not supported
- Solution: Service account with JWT auth
- Code example for fix
- Steps to request service account

## What the Agent Checks

### ✅ Cloud Run Compatible Patterns

- Request-driven architecture (HTTP endpoints)
- Stateless design (no in-memory sessions)
- External databases (PostgreSQL, Cloud SQL)
- Service account authentication
- Read-only filesystem usage
- Environment-based configuration

### ❌ Cloud Run Anti-Patterns (Blockers)

- Background jobs (APScheduler, cron, daemons)
- Local file storage (writes outside `/tmp`)
- In-memory state (sessions, cache)
- Browser-based auth (OAuth popups, SSO redirects)
- WebSocket servers (unreliable on Cloud Run)
- Heavy cold starts (>10 seconds)

## Output Format

The agent provides structured assessments:

```markdown
# App Foundry Suitability Assessment: [Project Name]

## Executive Summary
[Quick verdict: ready/needs work/not suitable]

## Compatibility Score: HIGH/MEDIUM/LOW

## ✅ What's Already Compatible
[Patterns that work on Cloud Run]

## ⚠️ Critical Blockers
### Blocker 1: [Name]
**Problem**: [What's broken]
**Solution**: [How to fix with code example]

## 📋 Remediation Plan
- [ ] Phase 1: Critical fixes (X days)
- [ ] Phase 2: Optimization (X days)

## 🎯 Final Stack Recommendation
[Tech stack, dependencies, configuration]

## Next Steps
1. [Immediate action]
2. [Follow-up]
```

## Common Fixes

### Fix 1: Snowflake Browser Auth → Service Account

**Before:**
```python
SNOWFLAKE = {
    "authenticator": "externalbrowser",  # ❌ Needs browser
    # ...
}
```

**After:**
```python
SNOWFLAKE = {
    "authenticator": "SNOWFLAKE_JWT",  # ✅ Service account
    "private_key": os.environ["SNOWFLAKE_PRIVATE_KEY"],
    # ...
}
```

### Fix 2: Background Scheduler → Cloud Scheduler

**Before:**
```python
from apscheduler.schedulers.background import BackgroundScheduler

scheduler = BackgroundScheduler()  # ❌ Won't work on Cloud Run
scheduler.add_job(my_task, 'cron', hour=2)
scheduler.start()
```

**After:**
```python
# Expose HTTP endpoint
@app.route('/_internal/scheduled_task', methods=['POST'])
def scheduled_task():
    # Verify Cloud Scheduler token
    if request.headers.get('Authorization') != f"Bearer {os.environ['INTERNAL_TOKEN']}":
        abort(403)
    
    my_task()  # ✅ Triggered by Cloud Scheduler
    return jsonify({"status": "success"})
```

### Fix 3: File Storage → PostgreSQL

**Before:**
```python
with open('results/data.json', 'w') as f:  # ❌ Ephemeral filesystem
    json.dump(results, f)
```

**After:**
```python
# Store in PostgreSQL
result = Result(data=results, created_at=datetime.utcnow())  # ✅ Persistent
db.session.add(result)
db.session.commit()
```

### Fix 4: In-Memory Sessions → Database

**Before:**
```python
sessions = {}  # ❌ Lost on container restart

@app.route('/login')
def login():
    session_id = str(uuid.uuid4())
    sessions[session_id] = user_data
```

**After:**
```python
# PostgreSQL model
class Session(Base):
    __tablename__ = 'sessions'
    id = Column(String, primary_key=True)
    data = Column(JSON)
    expires_at = Column(DateTime)

@app.route('/login')
def login():
    session = Session(
        id=str(uuid.uuid4()),
        data=user_data,
        expires_at=datetime.utcnow() + timedelta(hours=24)
    )
    db.session.add(session)  # ✅ Persistent
    db.session.commit()
```

## Stack-Specific Guidance

### Python + Flask
- ✅ Excellent fit (lightweight, fast startup)
- Use `gunicorn` as WSGI server
- Connection pooling with SQLAlchemy
- SSE support via `gevent` workers

### Python + Django
- ⚠️ Heavier (watch cold start time)
- Use `--preload` flag with gunicorn
- Disable unnecessary middleware
- Consider Flask for simpler use cases

### Node.js + Express
- ✅ Excellent fit (async-native, fast)
- Use `pg-pool` for PostgreSQL
- No cluster mode needed (Cloud Run scales)

### Next.js
- ✅ Good fit with App Router
- Use `output: 'standalone'`
- API routes work great
- SSR/ISR supported

### Static HTML
- ✅ Perfect for dashboards
- No build step needed
- Serve with Python `http.server`

### Go
- ✅ Excellent fit (fastest cold starts)
- Native concurrency
- Use `pgxpool` for connections

## Advanced Usage

### Multi-File Assessment

```
@appfoundry-suitability

Review these files for App Foundry compatibility:
- app.py (Flask server)
- detector.py (background job)
- config.py (Snowflake connection)

Focus on authentication and state management.
```

### Architecture Comparison

```
@appfoundry-suitability

I can build this as either:
A) Flask + PostgreSQL + Cloud Scheduler
B) Next.js API routes + Vercel Postgres

Which is better for App Foundry?
```

### Migration Planning

```
@appfoundry-suitability

We have a Django monolith. Can we extract the reporting module 
to App Foundry while keeping the main app on our VMs?

The reporting module:
- Queries Snowflake hourly
- Generates PDFs
- 200 users/day
```

## Troubleshooting

### Agent Not Found

```bash
# Check if agent is installed
ls -la ~/.claude/agents/appfoundry-suitability.md

# Reinstall if missing
cd appfoundry-suitability-agent
./setup.sh
```

### Agent Not Loading in Claude Code

1. Restart Claude Code
2. Check for syntax errors:
   ```bash
   cat ~/.claude/agents/appfoundry-suitability.md | head -20
   ```
3. Verify symlink:
   ```bash
   readlink ~/.claude/agents/appfoundry-suitability.md
   ```

### Assessment Too Generic

Provide more context:
```
@appfoundry-suitability

Project: Duplicate Finder Dashboard
Stack: Flask + Snowflake + OpenAI API
Current deployment: Runs on my laptop via `python app.py`

Key files:
- app.py: Flask server, port 5001
- detector.py: CLI that queries Snowflake, saves to results/latest.json
- config.py: Uses externalbrowser auth for Snowflake

Assess for App Foundry deployment.
```

## App Foundry Background

**What is App Foundry?**
- Zendesk's internal developer platform
- Deploys to Google Cloud Run
- Automatic Pomerium SSO authentication
- PostgreSQL databases available
- Internal URLs: `https://<name>.internal.zenai-apps.com`
- Portal UI and API for deployment

**Key Constraints:**
- Request-driven (no background daemons)
- Stateless (containers restart frequently)
- 60-second default timeout (configurable to 60 minutes)
- Ephemeral filesystem (except `/tmp`)
- Service account auth required (no browser)

## Contributing

Found an issue or have a suggestion? This agent is used internally at Zendesk. Contact the App Foundry team or the original author.

## License

Internal Zendesk tool. Not for external distribution.

## Support

For App Foundry platform questions:
- **Portal**: https://portal.idp.zenai-apps.com
- **Docs**: Check platform documentation
- **Team**: Contact Zendesk platform team

For agent issues:
- Check this README's troubleshooting section
- Verify Cloud Run constraints are understood
- Ensure codebase access for assessment

## Version History

- **v1.0.0** (2026-05-13): Initial release
  - Compatibility assessment for existing apps
  - Architecture guidance for new apps
  - Common anti-pattern detection
  - Remediation plans with code examples

---

**Made with Claude Code** • Assess smarter, deploy faster
