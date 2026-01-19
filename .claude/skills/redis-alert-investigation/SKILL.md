---
name: redis-alert-investigation
description: This skill should be used when the user asks to "investigate Redis alert", "debug cache issues", "check Redis cluster", "analyze Redis performance", mentions Redis/ElastiCache issues, cache memory pressure, high latency, connection exhaustion, evictions, or receives alerts about Redis clusters including CPU spikes, memory usage, slow commands, or replication problems.
allowed-tools: Read, Grep, Glob, Bash, WebFetch, WebSearch, mcp__grafana__*, mcp__grafana-lucky__*, mcp__cloudwatch-server__*, mcp__prometheus__*, mcp__mcp-db-gateway__redis_command
---

# Redis/ElastiCache Alert Investigation

You are investigating a Redis or ElastiCache alert. Follow this systematic investigation protocol.

## Phase 1: Parse Alert Context

Extract from the alert or user message:
- **Cluster/Instance name**: Redis cluster or ElastiCache cluster identifier
- **Alert type**: Memory, CPU, connections, latency, replication, evictions
- **Time window**: When the alert fired
- **Severity**: Critical, warning, or informational

## Phase 2: Health Check

### 2.1 Check Redis Cluster Status

Query Prometheus/Grafana for Redis metrics:

```promql
# Memory usage
redis_memory_used_bytes{instance=~"$instance"}
redis_memory_max_bytes{instance=~"$instance"}

# Connection count
redis_connected_clients{instance=~"$instance"}
redis_blocked_clients{instance=~"$instance"}

# CPU usage
redis_cpu_user_seconds_total{instance=~"$instance"}
redis_cpu_sys_seconds_total{instance=~"$instance"}

# Keyspace info
redis_db_keys{instance=~"$instance"}
redis_db_expires{instance=~"$instance"}
```

### 2.2 Check AWS ElastiCache Metrics (if applicable)

```promql
# ElastiCache CloudWatch metrics
aws_elasticache_cpuutilization_average
aws_elasticache_freeable_memory_average
aws_elasticache_curr_connections_average
aws_elasticache_evictions_average
aws_elasticache_cache_hits_average
aws_elasticache_cache_misses_average
aws_elasticache_replication_lag_average
```

## Phase 3: Memory Analysis

### 3.1 Memory Pressure Indicators

| Metric | Warning | Critical |
|--------|---------|----------|
| Memory Usage % | > 75% | > 90% |
| Evictions/sec | > 0 | > 100 |
| Fragmentation Ratio | > 1.5 | > 2.0 |

### 3.2 Memory Commands (if direct access available)

```redis
INFO memory
MEMORY STATS
MEMORY DOCTOR
DEBUG OBJECT <key>
```

## Phase 4: Performance Analysis

### 4.1 Latency Metrics

```promql
# Command latency
redis_commands_duration_seconds_total
rate(redis_commands_total[5m])

# Slow log count
redis_slowlog_length
```

### 4.2 Connection Analysis

```promql
# Connection metrics
redis_connected_clients
redis_rejected_connections_total
redis_connections_received_total
```

## Phase 5: Replication Status (if cluster/replica)

```promql
# Replication lag
redis_connected_slaves
redis_replication_offset
redis_slave_repl_offset
```

Check for:
- Replication lag between master and replicas
- Disconnected replicas
- Sync status

## Phase 6: Root Cause Determination

### Common Issues and Causes

| Symptom | Likely Cause | Investigation |
|---------|--------------|---------------|
| High memory + evictions | Key explosion, missing TTL | Check keyspace growth, big keys |
| High CPU | Hot keys, expensive commands | Check slowlog, command stats |
| Connection exhaustion | Connection leak, pool misconfiguration | Check client connections |
| High latency | Large keys, blocking commands | Check slowlog, KEYS usage |
| Replication lag | Network issues, high write load | Check network, write IOPS |

### Big Key Detection

```redis
MEMORY USAGE <key>
DEBUG OBJECT <key>
SCAN 0 COUNT 1000 MATCH *
```

## Phase 7: Generate Report

Create a structured report with:

```markdown
## Redis Investigation Report

### Cluster Information
- Cluster/Instance: <name>
- Node Type: <type>
- Alert: <alert_name>
- Time: <timestamp>

### Health Status
| Metric | Current | Threshold | Status |
|--------|---------|-----------|--------|
| Memory Usage | X% | 80% | OK/WARN/CRIT |
| CPU Usage | X% | 70% | OK/WARN/CRIT |
| Connections | X | max | OK/WARN/CRIT |
| Evictions/sec | X | 0 | OK/WARN/CRIT |
| Hit Rate | X% | 90% | OK/WARN/CRIT |

### Root Cause
<description>

### Recommendations
1. Immediate actions
2. Short-term fixes
3. Long-term improvements
```

## Quick Commands Reference

| Issue | Command/Query |
|-------|---------------|
| Memory stats | `INFO memory` |
| Slow commands | `SLOWLOG GET 10` |
| Client list | `CLIENT LIST` |
| Big keys | `redis-cli --bigkeys` |
| Hot keys | `redis-cli --hotkeys` |
| Memory by key | `MEMORY USAGE <key>` |

## Remediation Quick Reference

| Issue | Immediate Action |
|-------|-----------------|
| Memory pressure | Increase maxmemory, add TTL to keys |
| Evictions | Scale cluster, implement LRU policy |
| Connection exhaustion | Check connection pools, increase max connections |
| High latency | Identify slow commands, optimize queries |
| Replication lag | Check network, reduce write load |
