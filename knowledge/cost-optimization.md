# Cost Estimation & Optimization for Cloud Run

## Cost Components

### Cloud Run Pricing
- **CPU**: Charged per vCPU-second while processing requests
- **Memory**: Charged per GB-second while processing requests
- **Requests**: $0.40 per million requests
- **Min instances**: If set >0, charged 24/7 even when idle

### Common Configurations

**Small App (Dashboard, low traffic)**
- 512MB memory, 1 vCPU
- Scale to zero
- 10K requests/month
- **Cost**: ~$5-20/month

**Medium App (API, moderate traffic)**
- 1GB memory, 2 vCPU
- Scale to zero
- 100K requests/month
- **Cost**: ~$50-100/month

**Large App (High traffic, strict latency)**
- 2GB memory, 2 vCPU
- min_instances: 1 (no cold starts)
- 1M requests/month
- **Cost**: ~$200-400/month

### PostgreSQL Costs (App Foundry)
- **Standard tier**: ~$100/month
- **High availability**: ~$300/month
- Connection pooling reduces need for larger tier

### Snowflake Costs
- **Query-based**: $2-4 per compute credit
- **Warehouse size**: X-Small to 4X-Large
- Caching results can reduce costs by 80%+

## Optimization Strategies

### 1. Scale to Zero vs Min Instances

**Scale to Zero** (default)
- ✅ No cost when idle
- ⚠️ Cold start delay (1-3 seconds)
- **Use for**: Dashboards, internal tools, <100 requests/hour

**Min Instances: 1**
- ⚠️ 24/7 billing (~$30-80/month base cost)
- ✅ No cold starts
- **Use for**: APIs with strict latency SLAs, high traffic apps

### 2. Right-Size Memory/CPU

**Start small, scale up if needed:**
```yaml
# Start with defaults
memory: 512Mi
cpu: 1

# Only increase if you see:
# - Memory limit exceeded errors
# - Slow request processing
# - High CPU utilization (>80%)
```

**Memory impact on cost:**
- 512MB → 1GB = 2x cost
- 1GB → 2GB = 2x cost
- 2GB → 4GB = 2x cost

### 3. Connection Pooling Saves Database Costs

**Without pooling:**
- 100 containers × 5 connections each = 500 DB connections
- May need expensive database tier ($500+/month)

**With pooling (pool_size=5, max_overflow=10):**
- 100 containers × max 15 connections = 1,500 peak
- But typical usage: 50-100 active connections
- Standard database tier sufficient ($100/month)

### 4. Snowflake Result Caching

**Without caching:**
```python
# Every dashboard load queries Snowflake
@app.route('/dashboard')
def dashboard():
    results = query_snowflake("SELECT * FROM large_table")  # $0.10 per query
    return render_template('dashboard.html', results=results)

# 10K requests/month × $0.10 = $1,000/month
```

**With caching:**
```python
# Cache results for 1 hour
@app.route('/dashboard')
def dashboard():
    cached = cache.get('dashboard_results')
    if not cached:
        cached = query_snowflake("SELECT * FROM large_table")
        cache.set('dashboard_results', cached, timeout=3600)
    return render_template('dashboard.html', results=cached)

# 10K requests/month, 24 actual queries/day = $72/month
# Savings: $928/month (93% reduction)
```

**Caching strategies:**
- Short TTL (5-15 min): Real-time dashboards
- Medium TTL (1-6 hours): Analytics dashboards
- Long TTL (24 hours): Historical reports
- Event-based: Invalidate cache when data changes

### 5. Request Batching

**Inefficient:**
```python
# 100 separate Snowflake queries
for account_id in account_ids:  # 100 accounts
    data = query_snowflake(f"SELECT * FROM accounts WHERE id = '{account_id}'")

# 100 queries × $0.01 = $1.00 per user request
```

**Efficient:**
```python
# 1 batched query
account_ids_str = ','.join(f"'{id}'" for id in account_ids)
data = query_snowflake(f"SELECT * FROM accounts WHERE id IN ({account_ids_str})")

# 1 query × $0.01 = $0.01 per user request
# Savings: 99%
```

### 6. Lazy Loading Heavy Dependencies

**Expensive startup:**
```python
import pandas as pd
import tensorflow as tf

# Load 2GB model on startup (every cold start)
model = tf.keras.models.load_model('large_model.h5')  # 30 seconds

# Cold starts cost more:
# - Higher CPU/memory usage during startup
# - User waits longer (poor UX)
```

**Lazy loading:**
```python
model = None

def get_model():
    global model
    if model is None:
        import tensorflow as tf
        model = tf.keras.models.load_model('large_model.h5')
    return model

# Only load when first prediction request comes in
# Startup time: <5 seconds (cheaper)
```

## Cost Estimation Formula

**Monthly Cloud Run cost:**
```
= (Request cost) + (CPU cost) + (Memory cost) + (Min instance cost)

Request cost = (requests/month) × $0.40 / 1M
CPU cost = (avg request time in seconds) × (vCPUs) × (requests/month) × $0.00002400
Memory cost = (avg request time in seconds) × (GB memory) × (requests/month) × $0.00000250
Min instance cost = (min_instances) × (GB memory) × (730 hours) × $0.00000250 × (vCPUs) × $0.00002400
```

**Example calculation (medium app):**
```
Requests: 100K/month
Avg request time: 500ms (0.5 seconds)
Memory: 1GB
vCPUs: 2
Min instances: 0 (scale to zero)

Request cost = 100,000 × $0.40 / 1M = $0.04
CPU cost = 0.5 × 2 × 100,000 × $0.00002400 = $2.40
Memory cost = 0.5 × 1 × 100,000 × $0.00000250 = $0.13
Min instance cost = $0 (scale to zero)

Total: ~$2.57/month (just Cloud Run)
Add PostgreSQL: $100/month
Add Snowflake: ~$50-200/month (query-dependent)

**Total monthly cost: ~$150-300/month**
```

## Cost Red Flags

🚩 **"We query Snowflake on every page load"** → Add caching  
🚩 **"We have 500 database connections"** → Add connection pooling  
🚩 **"Min instances set to 10"** → Review if really needed (high 24/7 cost)  
🚩 **"Each request makes 50 API calls"** → Batch requests  
🚩 **"2GB model loads on startup"** → Lazy load  
🚩 **"We use 8GB memory for 10MB responses"** → Right-size memory

## Proficiency-Level Guidance

### Business/Sales
Focus on:
- Total monthly cost estimate
- What drives cost (requests, compute, database)
- Optimization ROI ("Caching saves $900/month")

### Product Manager  
Focus on:
- Cost vs feature trade-offs
- Scale-to-zero vs min-instances decision
- Budget planning

### Operations
Focus on:
- Resource sizing (memory/CPU)
- Monitoring cost metrics
- Alert on unexpected cost spikes

### Developer
Focus on:
- Code-level optimizations (caching, batching)
- Connection pooling implementation
- Lazy loading patterns

### Senior Engineer/Architect
Focus on:
- Cost modeling for different load profiles
- Advanced optimization strategies
- Cost/performance trade-offs
