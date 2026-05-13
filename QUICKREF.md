# Quick Reference: Cloud Run Anti-Patterns & Solutions

Quick lookup for common Cloud Run compatibility issues and their fixes.

## Authentication Patterns

### ❌ Browser-Based SSO
```python
# Snowflake externalbrowser
SNOWFLAKE = {"authenticator": "externalbrowser"}

# AWS SSO
session = boto3.Session(profile_name='sso')

# OAuth redirect flow
@app.route('/login')
def login():
    return redirect(oauth_provider.authorize_url)
```

### ✅ Service Account Auth
```python
# Snowflake JWT
SNOWFLAKE = {
    "authenticator": "SNOWFLAKE_JWT",
    "private_key": os.environ["SNOWFLAKE_PRIVATE_KEY"]
}

# AWS IAM role
session = boto3.Session()  # Uses IAM role from Cloud Run

# API token
headers = {"Authorization": f"Bearer {os.environ['API_TOKEN']}"}
```

---

## Background Jobs

### ❌ In-Process Scheduler
```python
from apscheduler.schedulers.background import BackgroundScheduler

scheduler = BackgroundScheduler()
scheduler.add_job(my_task, 'cron', hour=2)
scheduler.start()  # Won't work - container sleeps
```

### ✅ Cloud Scheduler → HTTP Endpoint
```python
@app.route('/_internal/scheduled_task', methods=['POST'])
def scheduled_task():
    # Verify token
    if request.headers.get('Authorization') != f"Bearer {os.environ['TOKEN']}":
        abort(403)
    
    my_task()
    return jsonify({"status": "success"})

# Configure in GCP Cloud Scheduler:
# URL: https://app.internal.zenai-apps.com/_internal/scheduled_task
# Schedule: 0 2 * * * (cron format)
# Auth: Authorization: Bearer <secret>
```

---

## File Storage

### ❌ Local Filesystem Writes
```python
# Save results
with open('results/data.json', 'w') as f:
    json.dump(results, f)

# User uploads
file.save(f'uploads/{filename}')

# SQLite database
conn = sqlite3.connect('app.db')
```

### ✅ Database or Cloud Storage
```python
# Save to PostgreSQL
result = Result(data=results)
db.session.add(result)
db.session.commit()

# User uploads to Cloud Storage
from google.cloud import storage
bucket = storage.Client().bucket('my-bucket')
blob = bucket.blob(f'uploads/{filename}')
blob.upload_from_file(file)

# PostgreSQL database
engine = create_engine(DATABASE_URL)
```

---

## Session Management

### ❌ In-Memory Sessions
```python
sessions = {}  # Lost on container restart

@app.route('/login')
def login():
    session_id = uuid.uuid4()
    sessions[session_id] = user_data
```

### ✅ Database Sessions
```python
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
    db.session.add(session)
    db.session.commit()
```

---

## WebSockets

### ❌ WebSocket Server
```python
from flask_socketio import SocketIO

socketio = SocketIO(app)

@socketio.on('message')
def handle_message(data):
    # Connection state lost on container restart
    emit('response', response_data)
```

### ✅ Server-Sent Events (SSE)
```python
@app.route('/stream')
def stream():
    def generate():
        for update in get_updates():
            yield f"data: {json.dumps(update)}\n\n"
            time.sleep(1)
    
    return Response(generate(), mimetype='text/event-stream')

# Frontend handles reconnection
let eventSource = new EventSource('/stream');
eventSource.onerror = () => {
    setTimeout(() => reconnect(), 1000);
};
```

---

## Cache Patterns

### ❌ In-Memory Cache
```python
cache = {}  # Lost on restart, not shared across containers

def get_data(key):
    if key not in cache:
        cache[key] = expensive_query(key)
    return cache[key]
```

### ✅ Database or Redis Cache
```python
# PostgreSQL with TTL
class Cache(Base):
    __tablename__ = 'cache'
    key = Column(String, primary_key=True)
    value = Column(JSON)
    expires_at = Column(DateTime)

def get_data(key):
    cached = Cache.query.filter_by(key=key).filter(
        Cache.expires_at > datetime.utcnow()
    ).first()
    
    if not cached:
        value = expensive_query(key)
        cached = Cache(
            key=key, 
            value=value,
            expires_at=datetime.utcnow() + timedelta(hours=1)
        )
        db.session.merge(cached)
        db.session.commit()
    
    return cached.value
```

---

## Database Connections

### ❌ No Connection Pooling
```python
def query_db():
    conn = psycopg2.connect(DATABASE_URL)  # New connection each time
    result = conn.execute(query)
    conn.close()
    return result
```

### ✅ Connection Pooling
```python
from sqlalchemy import create_engine

engine = create_engine(
    DATABASE_URL,
    pool_size=5,           # Max 5 concurrent
    max_overflow=10,       # Allow 15 total during bursts
    pool_pre_ping=True,    # Health check before use
    pool_recycle=3600      # Recycle after 1 hour
)

def query_db():
    with engine.connect() as conn:
        return conn.execute(query).fetchall()
```

---

## Environment Configuration

### ❌ Hardcoded Config
```python
SNOWFLAKE = {
    "account": "ttb18570.us-west-2",
    "user": "akirby@zendesk.com",
    "password": "hardcoded_password"  # ❌ Security risk
}

API_KEY = "zdai_abc123"  # ❌ Exposed in code
```

### ✅ Environment Variables
```python
SNOWFLAKE = {
    "account": os.environ["SNOWFLAKE_ACCOUNT"],
    "user": os.environ["SNOWFLAKE_USER"],
    "private_key": os.environ["SNOWFLAKE_PRIVATE_KEY"]
}

API_KEY = os.environ["API_KEY"]

# Set in App Foundry portal UI or catalog-info.yaml
```

---

## Pomerium Authentication

### ❌ Custom Auth Implementation
```python
@app.before_request
def check_auth():
    token = request.cookies.get('auth_token')
    if not verify_token(token):
        return redirect('/login')
```

### ✅ Use Pomerium Headers
```python
def get_user():
    email = request.headers.get('X-Pomerium-Claim-Email')
    name = request.headers.get('X-Pomerium-Claim-Name')
    groups = request.headers.get('X-Pomerium-Claim-Groups', '').split(',')
    
    if not email:
        abort(403, "Not authenticated")
    
    return {"email": email, "name": name, "groups": groups}

@app.route('/admin')
def admin():
    user = get_user()
    if 'admins' not in user['groups']:
        abort(403, "Admin access required")
    # ...
```

---

## Cold Start Optimization

### ❌ Heavy Initialization
```python
# Load large ML model on startup
model = load_model('large_model.pkl')  # 2GB, takes 30 seconds

@app.route('/predict')
def predict():
    return model.predict(request.json)
```

### ✅ Lazy Loading
```python
model = None

def get_model():
    global model
    if model is None:
        model = load_model('large_model.pkl')
    return model

@app.route('/predict')
def predict():
    # Only load on first prediction request
    m = get_model()
    return m.predict(request.json)

# Or: Keep-alive endpoint to warm containers
@app.route('/_health')
def health():
    return jsonify({"status": "ok"})
```

---

## Temporary Files

### ❌ Assuming Persistence
```python
# Generate report
with open('report.pdf', 'wb') as f:
    f.write(generate_pdf())

# Later request
with open('report.pdf', 'rb') as f:  # ❌ File may not exist
    return send_file(f)
```

### ✅ Use /tmp and Cleanup
```python
import tempfile
import os

# Generate report
with tempfile.NamedTemporaryFile(delete=False, suffix='.pdf') as f:
    f.write(generate_pdf())
    temp_path = f.name

try:
    # Use immediately in same request
    return send_file(temp_path, as_attachment=True)
finally:
    # Clean up
    os.unlink(temp_path)

# Or: Store in database/Cloud Storage for later access
```

---

## Quick Diagnosis Guide

**Error: "Could not open browser"**
→ Browser-based auth (externalbrowser, OAuth) - use service account

**Error: "No such file or directory"**
→ File writes outside /tmp - use database or Cloud Storage

**App works first request, fails later**
→ In-memory state (sessions, cache) - use database

**Background job not running**
→ Scheduler/daemon/cron - use Cloud Scheduler + HTTP endpoint

**Database connection errors**
→ No connection pooling - add SQLAlchemy pooling

**Slow cold starts**
→ Heavy initialization - lazy load or keep-alive endpoint

**WebSocket disconnects**
→ Container restarts - use SSE with reconnection

**"Context expired" errors**
→ In-memory context - store in database with TTL

---

## Stack-Specific Patterns

### Python + Flask
```python
# requirements.txt
flask==3.0.0
gunicorn==21.2.0
sqlalchemy==2.0.23
psycopg2-binary==2.9.9

# Dockerfile or Procfile
web: gunicorn app:app --workers 4 --worker-class gevent --bind 0.0.0.0:$PORT
```

### Node.js + Express
```javascript
// package.json
{
  "scripts": {
    "start": "node server.js"
  },
  "dependencies": {
    "express": "^4.18.0",
    "pg": "^8.11.0"
  }
}

// Connection pooling
const { Pool } = require('pg');
const pool = new Pool({
  connectionString: process.env.DATABASE_URL,
  max: 5,
  idleTimeoutMillis: 30000
});
```

### Next.js
```javascript
// next.config.js
module.exports = {
  output: 'standalone',  // Required for Cloud Run
}

// package.json
{
  "scripts": {
    "build": "next build",
    "start": "next start -p $PORT"
  }
}
```

---

## Health Check Pattern

```python
@app.route('/_health')
def health():
    # Basic health check
    return jsonify({"status": "ok"}), 200

@app.route('/_health/ready')
def ready():
    # Check dependencies
    try:
        # Test database
        db.session.execute('SELECT 1')
        
        # Test external service
        requests.get(EXTERNAL_API, timeout=2)
        
        return jsonify({"status": "ready"}), 200
    except Exception as e:
        return jsonify({"status": "not ready", "error": str(e)}), 503
```

---

## When to Say "Not Suitable"

These patterns are extremely difficult to adapt for Cloud Run:

- Real-time multiplayer games (persistent WebSocket state)
- Hardware access (USB devices, GPIO pins)
- Root access requirements
- Kernel module dependencies
- Apps requiring >60 minute request timeout (even max is 60min)
- Apps with strict <50ms latency SLAs (cold starts impact)

For these, recommend: Compute Engine VM, GKE, or dedicated infrastructure.

---

**Quick tip**: When in doubt, ask "Would this work if the container restarted mid-request?" If no, it needs fixing.
