# Proficiency-Level Tailoring Guide

This guide shows how to adapt assessment content for each proficiency level.

## Quick Reference

| Section | Business/Sales | Product Manager | Operations | Developer | Senior Eng/Architect |
|---------|---------------|-----------------|------------|-----------|---------------------|
| **Code Examples** | None | Minimal | Config only | Full | Advanced |
| **Technical Depth** | None | Concepts | Procedures | Implementation | Patterns |
| **Focus** | Timeline, cost, who | Decisions, trade-offs | Deploy, monitor | Code, test | Optimize, scale |

## Example: Same Blocker, 5 Proficiency Levels

### Blocker: Snowflake Browser Authentication

#### Level 1: Business/Sales

```markdown
### Blocker: Snowflake Database Access

**What's the issue?**  
The app can't connect to Snowflake automatically when deployed to App Foundry.

**Who needs to fix it?**  
The data platform team needs to create a special "service account" for the app.

**How long will it take?**  
3-5 business days (external team approval process)

**What does it cost?**  
No additional cost - service accounts are free

**Your action:**  
Submit a request to the data platform team with:
- App name
- What Snowflake data it needs access to
- Business justification

**Who to contact:**  
data-platform-team@zendesk.com
```

#### Level 2a: Product Manager

```markdown
### Blocker: Snowflake Authentication Method

**Problem:**  
Current authentication requires human interaction (browser popup for SSO). Cloud Run containers can't open browsers, blocking automatic data refresh.

**Impact:**  
- App cannot query Snowflake without this fix
- Blocks deployment timeline by 3-5 days (service account approval)
- No workaround available

**Decision required:**  
Service account vs OAuth token

| Option | Pros | Cons | Recommendation |
|--------|------|------|----------------|
| **Service account** | Reliable, no maintenance, secure | 3-5 day approval | ✅ Recommended |
| **OAuth token** | Faster setup (1 day) | Requires token refresh logic, adds complexity | Not recommended |

**Trade-off:**  
One-time 5-day delay for long-term reliability vs quick but complex solution

**User impact:**  
None - purely infrastructure change, invisible to end users

**Next steps:**  
1. Developer submits service account request
2. PM provides business justification
3. Data platform team approves (~3-5 days)
4. Developer configures app with credentials
```

#### Level 2b: Operations

```markdown
### Blocker: Snowflake Authentication

**Problem:**  
App uses `externalbrowser` auth which opens SSO login popup. Cloud Run containers have no display, so connection fails.

**How to identify:**  
- Deployment succeeds but app crashes on first Snowflake query
- Error in Cloud Run logs: `DatabaseError: 250001: Could not open browser`
- Health check fails if it tests Snowflake connection

**What Operations needs to do:**

**Step 1: Request service account (3-5 day lead time)**  
Email: data-platform-team@zendesk.com  
Template:
```
Subject: Service Account Request for [App Name]

App: [app-name]
Purpose: Query Salesforce data from CLEANSED.SALESFORCE schema
Warehouse: PUBLIC_ZENDESK_L
Permissions needed: SELECT on CLEANSED.SALESFORCE.* tables
Business owner: [PM name]
```

**Step 2: Receive credentials**  
You'll receive:
- Service account email (e.g., `svc_appname@zendesk.com`)
- Private key file (`private_key.pem`)

**Step 3: Add to App Foundry environment variables**  
In App Foundry portal → Your App → Configuration:
```
SNOWFLAKE_USER=svc_appname@zendesk.com
SNOWFLAKE_PRIVATE_KEY=<paste entire contents of private_key.pem file>
SNOWFLAKE_ACCOUNT=ttb18570.us-west-2
SNOWFLAKE_WAREHOUSE=PUBLIC_ZENDESK_L
```

**Step 4: Redeploy**  
App will pick up new environment variables on next deployment

**Step 5: Verify**  
- Check Cloud Run logs for successful Snowflake connection
- Test app UI - Snowflake queries should work
- If still failing, check logs for new error message

**Troubleshooting:**
| Error | Cause | Fix |
|-------|-------|-----|
| "Could not open browser" | Env vars not set | Add SNOWFLAKE_* variables |
| "Invalid credentials" | Wrong key or user | Verify pem file contents, check user email |
| "Insufficient privileges" | Missing warehouse access | Request warehouse permission from data team |

**Monitoring:**  
- Set alert: Snowflake connection errors >5% of requests
- Dashboard metric: Snowflake query success rate
- Log pattern: `snowflake.connector.errors.*`

**Rollback:**  
If service account auth breaks existing functionality:
1. Revert to previous deployment (Cloud Run keeps last 10 versions)
2. Re-add old environment variables
3. Investigate service account permissions
```

#### Level 3: Developer

```markdown
### Blocker: Snowflake Browser-Based Authentication

**Problem:**  
`externalbrowser` authenticator requires interactive SSO popup. Cloud Run containers are headless (no display), causing authentication to fail.

**Current code (broken):**
```python
# config.py
SNOWFLAKE = {
    "account": "ttb18570.us-west-2",
    "user": "akirby@zendesk.com",
    "authenticator": "externalbrowser",  # ❌ Opens browser
    "warehouse": "PUBLIC_ZENDESK_L",
    "database": "CLEANSED",
    "schema": "SALESFORCE",
}

# First query triggers SSO popup
conn = snowflake.connector.connect(**SNOWFLAKE)
# ❌ DatabaseError: 250001: Could not open browser
```

**Solution: Service account with RSA key-pair JWT authentication**

**Step 1: Request service account** (3-5 business days)  
Contact: data-platform-team@zendesk.com

**Step 2: Update connection config**

```python
# config.py
import os
from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.backends import default_backend

def get_private_key():
    """Load private key from environment variable"""
    pem_key = os.environ["SNOWFLAKE_PRIVATE_KEY"].encode()
    return serialization.load_pem_private_key(
        pem_key,
        password=None,
        backend=default_backend()
    )

SNOWFLAKE = {
    "account": os.environ["SNOWFLAKE_ACCOUNT"],  # ttb18570.us-west-2
    "user": os.environ["SNOWFLAKE_USER"],         # Service account email
    "authenticator": "SNOWFLAKE_JWT",              # ✅ Headless auth
    "private_key": get_private_key(),              # RSA key from env
    "warehouse": "PUBLIC_ZENDESK_L",
    "database": "CLEANSED",
    "schema": "SALESFORCE",
}

# Connection now works without browser
conn = snowflake.connector.connect(**SNOWFLAKE)
# ✅ Success
```

**Step 3: Add dependencies**

```txt
# requirements.txt
snowflake-connector-python==3.6.0
cryptography==41.0.7  # For key parsing
```

**Step 4: Test locally**

```bash
# Get service account credentials from Ops
export SNOWFLAKE_USER="svc_myapp@zendesk.com"
export SNOWFLAKE_PRIVATE_KEY="$(cat private_key.pem)"
export SNOWFLAKE_ACCOUNT="ttb18570.us-west-2"

# Test connection
python -c "from config import SNOWFLAKE; import snowflake.connector; conn = snowflake.connector.connect(**SNOWFLAKE); print('✅ Connected')"
```

**Step 5: Add to Cloud Run environment variables** (via App Foundry portal)

**Alternative: Connection via SQLAlchemy**

```python
from sqlalchemy import create_engine
from snowflake.sqlalchemy import URL

engine = create_engine(
    URL(
        account=os.environ["SNOWFLAKE_ACCOUNT"],
        user=os.environ["SNOWFLAKE_USER"],
        authenticator="SNOWFLAKE_JWT",
        private_key=get_private_key(),
        warehouse="PUBLIC_ZENDESK_L",
        database="CLEANSED",
        schema="SALESFORCE"
    ),
    pool_size=5,  # Connection pooling
    max_overflow=10,
    pool_pre_ping=True
)

# Execute query
with engine.connect() as conn:
    result = conn.execute("SELECT COUNT(*) FROM OPPORTUNITY_SCD2")
```

**Testing checklist:**
- [ ] Service account credentials received
- [ ] Local connection test passes
- [ ] No browser popup appears
- [ ] Queries return expected results
- [ ] Environment variables added to Cloud Run
- [ ] Deployed app connects successfully
```

#### Level 4: Senior Engineer/Architect

```markdown
### Blocker: Snowflake Authentication - Browser Dependency

**Root cause:**  
`externalbrowser` authenticator delegates to SAML 2.0 IdP via browser redirect flow (RFC 7522). Cloud Run containers lack X11/display server, causing connection initialization to fail at `snowflake.connector.network.SnowflakeRestful._authenticate`.

**Architecture decision: Service account vs alternatives**

| Method | Pros | Cons | Verdict |
|--------|------|------|---------|
| **JWT key-pair** | Headless, no token expiry, audit trail | Requires key rotation policy | ✅ Recommended |
| **OAuth refresh token** | Standard flow, revocable | 90-day expiry, refresh logic complexity | Avoid |
| **Credential passthrough** | Simple | Security risk, no MFA, breaks SSO audit | ❌ Never |

**Implementation: JWT authentication with connection pooling**

```python
# snowflake_client.py
import os
from sqlalchemy import create_engine
from snowflake.sqlalchemy import URL
from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.backends import default_backend

def get_snowflake_engine():
    """
    Create SQLAlchemy engine with connection pooling.
    
    Key design decisions:
    - pool_size=5: Limits per-container connections (Cloud Run scales horizontally)
    - max_overflow=10: Allows bursts, max 15 connections/container
    - pool_pre_ping=True: Validates connection before use (handles network blips)
    - pool_recycle=3600: Recycle after 1hr (Snowflake warehouse auto-suspend)
    """
    pem_key = os.environ["SNOWFLAKE_PRIVATE_KEY"].encode()
    private_key = serialization.load_pem_private_key(
        pem_key,
        password=None,
        backend=default_backend()
    )
    
    return create_engine(
        URL(
            account=os.environ["SNOWFLAKE_ACCOUNT"],
            user=os.environ["SNOWFLAKE_USER"],
            authenticator="SNOWFLAKE_JWT",
            private_key=private_key,
            warehouse="PUBLIC_ZENDESK_L",
            database="CLEANSED",
            schema="SALESFORCE"
        ),
        pool_size=5,
        max_overflow=10,
        pool_pre_ping=True,
        pool_recycle=3600,
        echo_pool=True  # Debug connection pool in logs
    )

# Module-level singleton (initialized once per container)
engine = get_snowflake_engine()
```

**Connection pool sizing calculation:**

```
Max Cloud Run containers: 100 (typical autoscale limit)
Connections per container: 5 (pool_size) + 10 (max_overflow) = 15
Peak total connections: 100 × 15 = 1,500

Snowflake recommendation: <2,000 connections per warehouse
Conclusion: Safe for X-Small to Small warehouse
```

**Security considerations:**

1. **Key rotation strategy:**  
   - Generate new key-pair quarterly (automate via Terraform)
   - Add new key to Snowflake user (allows 2 concurrent keys)
   - Deploy app with new key
   - After 48hr grace period, remove old key

2. **Least privilege:**  
   ```sql
   -- Request minimal permissions
   GRANT USAGE ON WAREHOUSE PUBLIC_ZENDESK_L TO ROLE svc_myapp_role;
   GRANT SELECT ON ALL TABLES IN SCHEMA CLEANSED.SALESFORCE TO ROLE svc_myapp_role;
   -- No DDL/DML grants
   ```

3. **Audit logging:**  
   ```python
   # Log all queries for security audit
   @event.listens_for(engine, "before_cursor_execute")
   def receive_before_cursor_execute(conn, cursor, statement, params, context, executemany):
       logger.info(json.dumps({
           "event": "snowflake_query",
           "statement": statement[:200],  # Truncate for PII
           "user": os.environ["SNOWFLAKE_USER"]
       }))
   ```

**Performance optimization:**

- **Query result caching:** Implement TTL-based cache in PostgreSQL (reduces Snowflake query costs by 80-95%)
- **Query pushdown:** Use SQLAlchemy ORM to ensure filters pushed to Snowflake (not post-processing in Python)
- **Connection pre-warming:** Health check endpoint queries Snowflake (keeps pool warm, reduces first-request latency)

**Observability:**

```python
# Custom metrics
from google.cloud import monitoring_v3

def record_snowflake_metrics(query_duration_ms, rows_returned, cache_hit):
    # Track: query latency p50/p95/p99, cache hit rate, connection pool exhaustion
    pass
```

**Alternative: Snowpark for advanced use cases**

If using Snowflake for compute (UDFs, stored procs):
```python
from snowflake.snowpark import Session

session = Session.builder.configs({
    "account": os.environ["SNOWFLAKE_ACCOUNT"],
    "user": os.environ["SNOWFLAKE_USER"],
    "authenticator": "SNOWFLAKE_JWT",
    "private_key_file": "/tmp/key.pem"  # Write env var to /tmp
}).create()
```
```

---

## Section-by-Section Tailoring

### Executive Summary

**Business/Sales:**
"The app is 70% ready. The data team needs to create a service account (5 days). After that, developers need 2-3 days to fix authentication code. Total timeline: 1-2 weeks. Cost: $150-300/month to run."

**Product Manager:**
"Application requires 3 critical fixes before deployment. Primary blocker is Snowflake authentication (requires service account, 5-day approval). Two code changes needed (2-3 dev days). Trade-off: 5-day delay for reliable long-term solution. Deployment-ready in 1-2 weeks."

**Operations:**
"Deployment blocked by missing service account (request from data platform team, 3-5 day SLA). Post-approval: update environment variables, redeploy app, verify connection. No infrastructure changes needed. Monitoring: alert on Snowflake connection failures."

**Developer:**
"Three code-level blockers: (1) Replace `externalbrowser` with JWT auth, (2) Add PostgreSQL connection pooling, (3) Store sessions in database instead of memory. Estimated effort: 2-3 days. All fixes have established patterns (see code examples). Service account dependency: 5 days (external team)."

**Senior Engineer/Architect:**
"Architecture assessment: stateless design with external state (PostgreSQL). Three anti-patterns detected: browser-based auth, in-memory session state, no connection pooling. Recommended patterns: JWT auth with key rotation, database-backed sessions with TTL, SQLAlchemy pooling (pool_size=5). Performance optimization opportunities: Snowflake result caching (80% cost reduction), lazy loading (cold start <5s). Deployment confidence: HIGH after fixes."

### Cost Considerations

**Business/Sales:**
"Monthly cost: ~$200-300 total. Breakdown: App Foundry ($20), Database ($100), Snowflake queries ($80-180). One-time setup cost: None. Ways to reduce cost: Cache Snowflake data (saves $100/month)."

**Product Manager:**
"Cost vs feature trade-offs: (1) Real-time data refresh = $300/month, (2) Hourly refresh with caching = $150/month. Recommend caching: 50% cost reduction, <1 hour data lag acceptable for this use case. Scale-to-zero vs always-on: Internal dashboard with low traffic suggests scale-to-zero (saves $50/month, adds 2-second cold start)."

**Operations:**
"Resource sizing: Start with 512MB/1vCPU (adequate for estimated load). Monitor memory usage; upgrade if >80% utilization. Connection pooling required: Without it, need expensive database tier ($500/month vs $100/month). Alert on cost spikes: Cloud Run >$100/month, Snowflake >$200/month."

**Developer:**
"Implement Snowflake result caching (1-hour TTL) to reduce query costs 93%. Code pattern: PostgreSQL cache table with `expires_at` column. Connection pooling: `pool_size=5, max_overflow=10` prevents database connection exhaustion. Lazy load heavy dependencies to reduce cold start costs."

**Senior Engineer/Architect:**
"Cost modeling: P50 request (cached): $0.0001, P95 request (Snowflake query): $0.01, P99 request (cold start + query): $0.02. Monthly cost breakdown: 80% Snowflake queries, 15% database, 5% compute. Optimization ROI: Caching implementation (4 dev hours) saves $1,200/year. Connection pooling prevents $4,800/year database upgrade. Recommend: Implement both, payback period <1 month."

---

This guide should be referenced when generating assessments to ensure consistent proficiency-level tailoring.
