---
name: apm-alert-investigation
description: This skill should be used when the user asks to "investigate APM alert", "debug application performance", "check service latency", "analyze error rates", mentions application monitoring issues, JVM problems, response time degradation, error spikes, garbage collection issues, or receives alerts about application performance including HTTP errors, timeout rates, or thread pool exhaustion.
allowed-tools: Read, Grep, Glob, Bash, WebFetch, WebSearch, mcp__grafana__*, mcp__grafana-lucky__*, mcp__cloudwatch-server__*, mcp__prometheus__*
---

# APM (Application Performance Monitoring) Alert Investigation

You are investigating an application performance alert. Follow this systematic investigation protocol.

## Phase 1: Parse Alert Context

Extract from the alert or user message:
- **Service name**: Application or microservice identifier
- **Environment**: Production, staging, development
- **Alert type**: Latency, error rate, throughput, JVM, etc.
- **Endpoint**: Specific API endpoint if applicable
- **Time window**: When the alert fired

## Phase 2: Service Health Overview

### 2.1 RED Metrics (Rate, Errors, Duration)

```promql
# Request rate
rate(http_requests_total{service="$service"}[5m])

# Error rate
rate(http_requests_total{service="$service", status=~"5.."}[5m])
/ rate(http_requests_total{service="$service"}[5m])

# Latency (p50, p95, p99)
histogram_quantile(0.50, rate(http_request_duration_seconds_bucket{service="$service"}[5m]))
histogram_quantile(0.95, rate(http_request_duration_seconds_bucket{service="$service"}[5m]))
histogram_quantile(0.99, rate(http_request_duration_seconds_bucket{service="$service"}[5m]))
```

### 2.2 Alternative Metric Names

```promql
# Spring Boot Actuator
http_server_requests_seconds_count
http_server_requests_seconds_sum
http_server_requests_seconds_bucket

# Custom metrics
request_latency_seconds
api_requests_total
api_errors_total
```

## Phase 3: Latency Analysis

### 3.1 Latency Breakdown

| Percentile | Good | Acceptable | Poor |
|------------|------|------------|------|
| p50 | < 100ms | 100-300ms | > 300ms |
| p95 | < 300ms | 300-1000ms | > 1000ms |
| p99 | < 1000ms | 1-3s | > 3s |

### 3.2 Latency by Endpoint

```promql
histogram_quantile(0.95,
  sum(rate(http_request_duration_seconds_bucket{service="$service"}[5m])) by (uri, le)
)
```

### 3.3 Latency Spikes Investigation

Check for:
- Database query latency
- External API call latency
- Cache miss rates
- Network latency

## Phase 4: Error Analysis

### 4.1 Error Classification

```promql
# By status code
sum(rate(http_requests_total{service="$service", status=~"5.."}[5m])) by (status)

# By endpoint
sum(rate(http_requests_total{service="$service", status=~"5.."}[5m])) by (uri)

# By error type
sum(rate(application_errors_total{service="$service"}[5m])) by (exception)
```

### 4.2 Common Error Patterns

| Status | Meaning | Investigation |
|--------|---------|---------------|
| 400 | Bad Request | Client-side issue, check request format |
| 401/403 | Auth failure | Check authentication, tokens |
| 404 | Not Found | Check routing, endpoint availability |
| 429 | Rate Limited | Check rate limits, scaling |
| 500 | Internal Error | Check application logs, exceptions |
| 502 | Bad Gateway | Check upstream services |
| 503 | Service Unavailable | Check health, resources |
| 504 | Gateway Timeout | Check downstream latency |

## Phase 5: JVM Analysis (Java Applications)

### 5.1 JVM Memory

```promql
# Heap usage
jvm_memory_used_bytes{area="heap"}
jvm_memory_max_bytes{area="heap"}

# Heap usage percentage
jvm_memory_used_bytes{area="heap"} / jvm_memory_max_bytes{area="heap"}

# Non-heap (metaspace)
jvm_memory_used_bytes{area="nonheap"}
```

### 5.2 Garbage Collection

```promql
# GC pause time
rate(jvm_gc_pause_seconds_sum[5m])
rate(jvm_gc_pause_seconds_count[5m])

# GC frequency
rate(jvm_gc_collection_seconds_count[5m])
```

### 5.3 JVM Threads

```promql
# Thread count
jvm_threads_current
jvm_threads_daemon
jvm_threads_peak

# Thread states
jvm_threads_states
```

### 5.4 JVM Health Thresholds

| Metric | Normal | Warning | Critical |
|--------|--------|---------|----------|
| Heap Usage | < 70% | 70-85% | > 85% |
| GC Time % | < 5% | 5-10% | > 10% |
| Thread Count | baseline | +50% | +100% |

## Phase 6: Dependency Analysis

### 6.1 Database Performance

```promql
# Connection pool
hikaricp_connections_active
hikaricp_connections_idle
hikaricp_connections_pending

# Query latency
rate(jdbc_query_seconds_sum[5m]) / rate(jdbc_query_seconds_count[5m])
```

### 6.2 External Service Calls

```promql
# HTTP client latency
histogram_quantile(0.95, rate(http_client_requests_seconds_bucket[5m]))

# HTTP client errors
rate(http_client_requests_total{status=~"5.."}[5m])
```

### 6.3 Cache Performance

```promql
# Cache hit rate
cache_gets_hit / (cache_gets_hit + cache_gets_miss)

# Cache latency
rate(cache_gets_seconds_sum[5m]) / rate(cache_gets_seconds_count[5m])
```

## Phase 7: Root Cause Determination

### Decision Tree

```
High Latency?
├── All endpoints affected
│   ├── JVM GC pressure → Check heap, tune GC
│   ├── Database slow → Check DB metrics, slow queries
│   ├── Resource exhaustion → Check CPU, memory
│   └── Network issues → Check connectivity
└── Specific endpoint
    ├── N+1 queries → Check query patterns
    ├── External API slow → Check downstream
    ├── Large payload → Check request/response size
    └── Lock contention → Check thread dumps

High Error Rate?
├── 5xx errors
│   ├── Null pointer → Check null handling, logs
│   ├── Timeout → Check downstream dependencies
│   ├── OOM → Check memory, heap dumps
│   └── Connection refused → Check connection pools
└── 4xx errors
    ├── 401/403 → Check auth service
    ├── 429 → Check rate limits
    └── 400 → Check client changes

JVM Issues?
├── High heap usage
│   ├── Memory leak → Heap dump analysis
│   ├── Large objects → Check caching
│   └── Insufficient heap → Increase -Xmx
├── Frequent GC
│   ├── Young GC → Check object allocation rate
│   └── Full GC → Check old gen, memory leaks
└── Thread issues
    ├── Thread leak → Check unclosed resources
    ├── Deadlock → Thread dump analysis
    └── Pool exhaustion → Check pool configuration
```

## Phase 8: Generate Report

```markdown
## APM Investigation Report

### Service Information
- Service: <service_name>
- Environment: <environment>
- Alert: <alert_name>
- Time: <timestamp>

### RED Metrics Summary
| Metric | Current | Baseline | Change |
|--------|---------|----------|--------|
| Request Rate | X/s | Y/s | +Z% |
| Error Rate | X% | Y% | +Z% |
| p95 Latency | Xms | Yms | +Z% |
| p99 Latency | Xms | Yms | +Z% |

### JVM Health (if applicable)
| Metric | Current | Threshold | Status |
|--------|---------|-----------|--------|
| Heap Usage | X% | 85% | OK/WARN/CRIT |
| GC Time | X% | 10% | OK/WARN/CRIT |
| Thread Count | X | baseline | OK/WARN/CRIT |

### Dependencies Status
| Dependency | Latency | Error Rate | Status |
|------------|---------|------------|--------|
| Database | Xms | Y% | OK/WARN/CRIT |
| Redis | Xms | Y% | OK/WARN/CRIT |
| External API | Xms | Y% | OK/WARN/CRIT |

### Root Cause
<description>

### Impact
- Affected users: <count>
- Affected endpoints: <list>
- Business impact: <description>

### Recommendations
1. Immediate: <action>
2. Short-term: <action>
3. Long-term: <action>
```

## Quick Reference: Common Issues

| Symptom | Likely Cause | Quick Fix |
|---------|--------------|-----------|
| Latency spike | GC pause | Tune GC, increase heap |
| Error spike | Deployment | Rollback |
| Gradual latency | Memory leak | Restart, fix leak |
| Connection errors | Pool exhausted | Increase pool size |
| Timeout errors | Downstream slow | Add timeout, circuit breaker |

## Remediation Quick Reference

| Issue | Immediate Action |
|-------|-----------------|
| High latency | Scale horizontally, add caching |
| High error rate | Rollback recent deployment |
| JVM memory | Increase heap, restart pods |
| Thread exhaustion | Increase thread pool, check leaks |
| Connection pool | Increase pool size, check for leaks |
| Downstream failure | Enable circuit breaker, add fallback |
