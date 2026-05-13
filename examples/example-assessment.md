# Example Assessment Output

This shows what the agent produces when assessing a typical Flask application.

## Input

```
@appfoundry-suitability

I have a Flask app that:
- Queries Snowflake using externalbrowser auth
- Runs detection logic in a CLI script (detector.py)
- Stores results in results/latest.json
- Flask app reads the JSON file and serves a dashboard
- Uses Server-Sent Events for real-time LLM investigation
- Stores follow-up chat context in a Python dict in memory

Can this deploy to App Foundry?
```

## Agent Output

---

# App Foundry Suitability Assessment: Flask Detection Dashboard

## Executive Summary

This application is **70% ready** for App Foundry with **3 critical blockers** that must be addressed. With fixes, it can deploy within **1-2 weeks** (pending Snowflake service account approval).

## Compatibility Score: MEDIUM (Fixable)

---

## ✅ What's Already Compatible

- **Flask Framework**: Lightweight, fast startup, excellent Cloud Run fit
- **Server-Sent Events**: Supported on Cloud Run (with improvements needed)
- **Request-Driven UI**: Dashboard pattern works perfectly
- **External Data Source**: Snowflake queries are fine (auth needs fixing)
- **LLM Integration**: API-based AI calls work great

---

## ⚠️ Critical Blockers

### Blocker 1: Snowflake Browser Authentication

**Problem**: `externalbrowser` auth opens a browser window for SSO. Cloud Run containers have no browser.

**Impact**: First Snowflake query will crash with `DatabaseError: Could not open browser`

**Solution**: Use service account with key-pair JWT authentication

**Before:**
```python
SNOWFLAKE = {
    "account": "ttb18570.us-west-2",
    "user": "akirby@zendesk.com",
    "authenticator": "externalbrowser",  # ❌ Needs browser
    "warehouse": "PUBLIC_ZENDESK_L",
}
```

**After:**
```python
SNOWFLAKE = {
    "account": "ttb18570.us-west-2",
    "user": os.environ["SNOWFLAKE_USER"],  # Service account
    "authenticator": "SNOWFLAKE_JWT",      # ✅ Headless auth
    "private_key": os.environ["SNOWFLAKE_PRIVATE_KEY"],  # From env var
    "warehouse": "PUBLIC_ZENDESK_L",
}
```

**Action Required**: 
1. Request Snowflake service account from Zendesk data platform team
2. Get private key in PEM format
3. Add to App Foundry environment variables

---

### Blocker 2: File-Based Result Storage

**Problem**: `results/latest.json` is written to local filesystem. Cloud Run filesystem is ephemeral—data is lost on container restart.

**Impact**: 
- Detection results disappear after container restart
- Multiple containers (load balancing) can't share data
- No audit trail of historical runs

**Solution**: Store results in PostgreSQL

**Add Database Model:**
```python
from sqlalchemy import Column, Integer, String, JSON, DateTime
from sqlalchemy.ext.declarative import declarative_base

Base = declarative_base()

class DetectorRun(Base):
    __tablename__ = 'detector_runs'
    
    id = Column(Integer, primary_key=True)
    status = Column(String(20))  # pending, completed, failed
    results_count = Column(Integer)
    completed_at = Column(DateTime)

class Result(Base):
    __tablename__ = 'results'
    
    id = Column(Integer, primary_key=True)
    run_id = Column(Integer, ForeignKey('detector_runs.id'))
    lost_opp_id = Column(String(20), index=True)
    new_opp_id = Column(String(20), index=True)
    score = Column(Integer)
    confidence = Column(String(20))
    data = Column(JSON)  # Full result as JSON
    created_at = Column(DateTime)
```

**Update Flask App:**
```python
@app.route("/api/results")
def api_results():
    session = SessionLocal()
    
    # Get latest completed run
    run = session.query(DetectorRun).filter_by(status="completed").order_by(
        DetectorRun.completed_at.desc()
    ).first()
    
    if not run:
        return jsonify([])
    
    # Get results for that run
    results = session.query(Result).filter_by(run_id=run.id).all()
    
    return jsonify([r.data for r in results])
```

---

### Blocker 3: In-Memory Investigation Context

**Problem**: Follow-up chat context stored in Python dict (`_investigation_contexts = {}`). Lost on container restart or unavailable to other container instances.

**Impact**: 
- Users lose chat context after container restart
- "Context expired" errors if request hits different container
- No persistence for audit/debugging

**Solution**: Store context in PostgreSQL with TTL

**Add Model:**
```python
class InvestigationContext(Base):
    __tablename__ = 'investigation_contexts'
    
    id = Column(Integer, primary_key=True)
    pair_id = Column(String(100), unique=True, nullable=False, index=True)
    context_data = Column(JSON, nullable=False)  # Full context
    created_at = Column(DateTime, default=datetime.utcnow)
    expires_at = Column(DateTime, nullable=False)  # 24-hour TTL
```

**Update Endpoints:**
```python
@app.route('/investigate/<lost_id>/<new_id>')
def investigate(lost_id, new_id):
    # Build context
    context = build_investigation_context(lost_id, new_id)
    
    # Store in database (expires in 24 hours)
    pair_id = f"{lost_id}_{new_id}"
    db_context = InvestigationContext(
        pair_id=pair_id,
        context_data=context,
        expires_at=datetime.utcnow() + timedelta(hours=24)
    )
    db.session.merge(db_context)  # Upsert
    db.session.commit()
    
    # ... return investigation

@app.route('/followup/<lost_id>/<new_id>', methods=['POST'])
def followup(lost_id, new_id):
    # Retrieve from database
    pair_id = f"{lost_id}_{new_id}"
    db_context = InvestigationContext.query.filter_by(pair_id=pair_id).first()
    
    if not db_context:
        return jsonify({"error": "Context expired"}), 404
    
    context = db_context.context_data
    # ... use context for follow-up
```

**Add Cleanup Job:**
```python
@app.route('/_internal/cleanup_contexts', methods=['POST'])
def cleanup_expired_contexts():
    # Verify Cloud Scheduler token
    if request.headers.get('Authorization') != f"Bearer {os.environ['INTERNAL_TOKEN']}":
        abort(403)
    
    InvestigationContext.query.filter(
        InvestigationContext.expires_at < datetime.utcnow()
    ).delete()
    db.session.commit()
    
    return jsonify({"status": "ok"})
```

---

## 🔧 Recommended Changes (Not Blockers)

### 1. Detection Job Trigger

**Current**: `detector.py` runs manually from command line

**Recommendation**: Expose as HTTP endpoint for Cloud Scheduler

```python
@app.route('/_internal/run_detection', methods=['POST'])
def run_detection():
    # Verify Cloud Scheduler token
    if request.headers.get('Authorization') != f"Bearer {os.environ['INTERNAL_TOKEN']}":
        abort(403)
    
    # Run detection
    results = run_detector()
    
    # Store in database
    run = DetectorRun(
        status='completed',
        results_count=len(results),
        completed_at=datetime.utcnow()
    )
    db.session.add(run)
    db.session.commit()
    
    return jsonify({"status": "success", "count": len(results)})
```

**Setup Cloud Scheduler** (via GCP Console):
- URL: `https://<app-name>.internal.zenai-apps.com/_internal/run_detection`
- Schedule: `0 2 * * *` (daily at 2 AM)
- Auth: `Authorization: Bearer <secret-token>`

### 2. SSE Reliability Improvements

**Add heartbeat to prevent proxy timeouts:**
```python
@app.route('/stream_investigation/<lost_id>/<new_id>')
def stream_investigation(lost_id, new_id):
    def generate():
        last_heartbeat = time.time()
        
        for chunk in investigate_with_llm(lost_id, new_id):
            yield f"data: {json.dumps(chunk)}\n\n"
            last_heartbeat = time.time()
        
        # Heartbeat every 15 seconds if no data
        while time.time() - last_heartbeat > 15:
            yield ": heartbeat\n\n"
            last_heartbeat = time.time()
    
    return Response(generate(), mimetype='text/event-stream')
```

**Configure Cloud Run timeout** (in portal UI or catalog-info.yaml):
```yaml
spec:
  cloudRunConfig:
    timeout: 300s  # 5 minutes for investigation
```

### 3. Connection Pooling

**Add SQLAlchemy pooling for PostgreSQL:**
```python
engine = create_engine(
    DATABASE_URL,
    pool_size=5,           # Max 5 concurrent connections
    max_overflow=10,       # Allow 15 total during bursts
    pool_pre_ping=True,    # Verify connection health
    pool_recycle=3600      # Recycle after 1 hour
)
```

**Add Snowflake pooling:**
```python
from snowflake.sqlalchemy import URL

snowflake_engine = create_engine(
    URL(
        account=os.environ['SNOWFLAKE_ACCOUNT'],
        user=os.environ['SNOWFLAKE_USER'],
        authenticator='SNOWFLAKE_JWT',
        private_key=os.environ['SNOWFLAKE_PRIVATE_KEY'],
        warehouse='PUBLIC_ZENDESK_L'
    ),
    pool_size=5,
    max_overflow=10,
    pool_pre_ping=True
)
```

---

## 📋 Remediation Plan

### Phase 1: Critical Fixes (1-2 days)

**Priority 1: Database Migration**
- [ ] Add SQLAlchemy models (DetectorRun, Result, InvestigationContext)
- [ ] Create database init script
- [ ] Update `detector.py` to write to database
- [ ] Update Flask routes to read from database
- [ ] Test locally with PostgreSQL

**Priority 2: Snowflake Service Account**
- [ ] Submit request to Zendesk data platform team
- [ ] Wait for service account creation (external dependency)
- [ ] Receive private key (PEM format)
- [ ] Update connection config
- [ ] Test Snowflake queries with new auth

**Priority 3: Investigation Context Storage**
- [ ] Add InvestigationContext model
- [ ] Update `/investigate` endpoint
- [ ] Update `/followup` endpoint
- [ ] Add cleanup endpoint
- [ ] Test context persistence

### Phase 2: Optimization (1 day)

**Detection Job Endpoint**
- [ ] Add `/_internal/run_detection` route
- [ ] Generate internal auth token (UUID)
- [ ] Add token to environment variables
- [ ] Document Cloud Scheduler setup

**SSE Improvements**
- [ ] Add heartbeat to generator
- [ ] Configure 5-minute timeout
- [ ] Test stream reliability

**Connection Pooling**
- [ ] Add pooling to PostgreSQL engine
- [ ] Add pooling to Snowflake engine
- [ ] Monitor connection usage

### Phase 3: Production Readiness (0.5 days)

**Health Checks**
- [ ] Add `/_health` endpoint
- [ ] Check database connectivity
- [ ] Check Snowflake connectivity

**Monitoring**
- [ ] Structured JSON logging
- [ ] Log detection run stats
- [ ] Log investigation durations

---

## 🎯 Final Stack Recommendation

```
Frontend:
  - HTML/CSS/JS (keep as-is)

Backend:
  - Flask 3.0+
  - Gunicorn (WSGI server)
  - Python 3.11+

Database:
  - PostgreSQL (App Foundry-provisioned)
  - SQLAlchemy 2.0+ ORM
  - Connection pooling (pool_size=5)

External Services:
  - Snowflake (JWT auth)
  - OpenAI via Zendesk AI Gateway
  - Pomerium SSO (automatic)

Deployment:
  - App Foundry / Cloud Run
  - Cloud Scheduler (detection job)
```

**Dependencies (requirements.txt):**
```txt
flask==3.0.0
gunicorn==21.2.0
sqlalchemy==2.0.23
psycopg2-binary==2.9.9
snowflake-connector-python==3.6.0
snowflake-sqlalchemy==1.5.1
pandas==2.1.4
requests==2.31.0
python-jose[cryptography]==3.3.0
```

**Environment Variables:**
```bash
# PostgreSQL (auto-provided)
DB_HOST=<postgres-host>
DB_NAME=<database-name>
DB_USER=<username>
DB_PASS=<password>

# Snowflake (configure in portal)
SNOWFLAKE_USER=<service-account>
SNOWFLAKE_PRIVATE_KEY=<pem-key>
SNOWFLAKE_ACCOUNT=ttb18570.us-west-2
SNOWFLAKE_WAREHOUSE=PUBLIC_ZENDESK_L

# AI Gateway
AI_GATEWAY_URL=https://ai-gateway.zende.sk/v1
AI_GATEWAY_API_KEY=<api-key>

# Internal auth
INTERNAL_TOKEN=<random-uuid>
```

---

## 📊 Deployment Readiness

- **Effort**: 2-3 days of development
- **Risk**: MEDIUM (external dependency on Snowflake service account)
- **Timeline**: 1-2 weeks (including service account approval)
- **Confidence**: HIGH (patterns are well-understood)

**External Dependencies:**
1. Snowflake service account (blocks deployment until available)
2. PostgreSQL database (App Foundry provides automatically)

---

## Next Steps

1. **[IMMEDIATE]** Request Snowflake service account from data platform team
2. **[DAY 1]** Implement database models and migrations
3. **[DAY 2]** Update detector.py and Flask routes for database storage
4. **[DAY 3]** Test locally with PostgreSQL
5. **[WEEK 2]** Receive service account, update auth, deploy to App Foundry
6. **[WEEK 2]** Configure Cloud Scheduler for detection job
7. **[WEEK 2]** Monitor production, tune connection pooling

---

**Assessment Complete** ✅

This application is an excellent candidate for App Foundry. The architecture (internal tool, Pomerium auth, database-backed, periodic batch job + interactive UI) aligns perfectly with the platform's design. Once the three critical blockers are addressed, deployment should be straightforward.
