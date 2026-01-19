---
name: rds-alert-investigation
description: This skill should be used when the user asks to "investigate RDS alert", "debug database issues", "check RDS performance", "analyze MySQL/PostgreSQL problems", mentions database connection issues, slow queries, replication lag, or receives alerts about AWS RDS instances including connection exhaustion, query performance, storage, or CPU spikes.
allowed-tools: Read, Grep, Glob, Bash, WebFetch, WebSearch, mcp__grafana__*, mcp__grafana-lucky__*, mcp__cloudwatch-server__*, mcp__prometheus__*, mcp__mcp-db-gateway__mysql_query, mcp__mcp-db-gateway__postgres_query
---

# RDS/Database Alert Investigation

You are investigating an RDS or database alert. Follow this systematic investigation protocol.

## Phase 1: Parse Alert Context

Extract from the alert or user message:
- **Instance/Cluster name**: RDS instance identifier or Aurora cluster name
- **Database engine**: MySQL, PostgreSQL, Aurora MySQL, Aurora PostgreSQL
- **Alert type**: Connection, CPU, storage, replication, restart/failover
- **Time window**: When the alert fired

## Phase 2: Instance Health Check

### 2.1 CloudWatch RDS Metrics

```promql
# CPU utilization
aws_rds_cpuutilization_average{dbinstance_identifier="$instance"}

# Database connections
aws_rds_database_connections_average{dbinstance_identifier="$instance"}

# Free storage space
aws_rds_free_storage_space_average{dbinstance_identifier="$instance"}

# Free memory
aws_rds_freeable_memory_average{dbinstance_identifier="$instance"}

# Read/Write IOPS
aws_rds_read_iops_average{dbinstance_identifier="$instance"}
aws_rds_write_iops_average{dbinstance_identifier="$instance"}

# Read/Write latency
aws_rds_read_latency_average{dbinstance_identifier="$instance"}
aws_rds_write_latency_average{dbinstance_identifier="$instance"}
```

### 2.2 Restart/Failover Detection

```promql
# MySQL/MariaDB uptime (drops indicate restart)
mysql_global_status_uptime{instance=~"$instance.*"}

# Connection drops (sudden drop indicates restart)
aws_rds_database_connections_average
```

### 2.3 Replication Metrics

```promql
# Aurora replica lag
aws_rds_aurora_replica_lag_average{dbinstance_identifier="$instance"}

# MySQL replica lag
aws_rds_replica_lag_average{dbinstance_identifier="$instance"}

# Binary log position
aws_rds_bin_log_disk_usage_average{dbinstance_identifier="$instance"}
```

## Phase 3: Connection Analysis

### 3.1 Connection Thresholds

| Instance Class | Max Connections (approx) |
|----------------|--------------------------|
| db.t3.micro | 66 |
| db.t3.small | 150 |
| db.t3.medium | 312 |
| db.r5.large | 1000 |
| db.r5.xlarge | 2000 |
| db.r5.2xlarge | 4000 |

### 3.2 Connection Health Indicators

| Metric | Warning | Critical |
|--------|---------|----------|
| Connection Usage % | > 70% | > 90% |
| Connection Rate | spike > 2x normal | spike > 5x normal |
| Aborted Connections | > 1% | > 5% |

### 3.3 MySQL Connection Queries

```sql
-- Active connections by user
SELECT user, host, COUNT(*) as connections
FROM information_schema.processlist
GROUP BY user, host
ORDER BY connections DESC;

-- Connection states
SELECT command, COUNT(*) as count
FROM information_schema.processlist
GROUP BY command;

-- Long-running queries
SELECT id, user, host, db, command, time, state, info
FROM information_schema.processlist
WHERE command != 'Sleep' AND time > 30
ORDER BY time DESC;
```

### 3.4 PostgreSQL Connection Queries

```sql
-- Active connections by user
SELECT usename, client_addr, count(*)
FROM pg_stat_activity
WHERE state != 'idle'
GROUP BY usename, client_addr
ORDER BY count DESC;

-- Connection states
SELECT state, count(*)
FROM pg_stat_activity
GROUP BY state;

-- Long-running queries
SELECT pid, usename, client_addr, query_start, state, query
FROM pg_stat_activity
WHERE state != 'idle'
  AND query_start < now() - interval '30 seconds'
ORDER BY query_start;
```

## Phase 4: Query Performance Analysis

### 4.1 MySQL Slow Query Analysis

```sql
-- Enable slow query log check
SHOW VARIABLES LIKE 'slow_query_log%';
SHOW VARIABLES LIKE 'long_query_time';

-- Table lock contention
SHOW STATUS LIKE 'Table_locks%';

-- InnoDB status
SHOW ENGINE INNODB STATUS;

-- Index usage
SELECT * FROM sys.schema_unused_indexes;
SELECT * FROM sys.schema_redundant_indexes;
```

### 4.2 PostgreSQL Query Analysis

```sql
-- Top queries by time
SELECT query, calls, total_time, mean_time, rows
FROM pg_stat_statements
ORDER BY total_time DESC
LIMIT 20;

-- Index usage
SELECT schemaname, tablename, indexname, idx_scan, idx_tup_read
FROM pg_stat_user_indexes
ORDER BY idx_scan ASC;

-- Table bloat
SELECT schemaname, tablename, n_dead_tup, n_live_tup,
       round(n_dead_tup::numeric / nullif(n_live_tup, 0) * 100, 2) as dead_ratio
FROM pg_stat_user_tables
WHERE n_dead_tup > 1000
ORDER BY dead_ratio DESC;
```

## Phase 5: Storage and I/O Analysis

### 5.1 Storage Thresholds

| Metric | Warning | Critical |
|--------|---------|----------|
| Free Storage % | < 25% | < 10% |
| Storage Growth Rate | > 1GB/day | > 5GB/day |
| IOPS Usage | > 70% provisioned | > 90% provisioned |
| I/O Latency | > 10ms | > 50ms |

### 5.2 Storage Investigation

```promql
# Storage usage trend
aws_rds_free_storage_space_average

# IOPS utilization
aws_rds_read_iops_average + aws_rds_write_iops_average

# I/O throughput
aws_rds_read_throughput_average
aws_rds_write_throughput_average
```

## Phase 6: Root Cause Determination

### Decision Tree

```
Restart/Failover Alert?
├── Planned maintenance → Check AWS maintenance schedule
├── Multi-AZ failover → Check for primary failure indicators
│   ├── High CPU/memory → Resource exhaustion triggered failover
│   ├── Storage full → Storage triggered failover
│   └── Network issue → AWS infrastructure issue
└── Unexpected restart → Check for crash indicators
    ├── OOM killer → Increase instance size
    ├── Long query → Optimize or kill query
    └── AWS issue → Check AWS status

High CPU?
├── Inefficient queries → Optimize queries, add indexes
├── Lock contention → Check for deadlocks
├── Connection storm → Check application connection pooling
└── Backup/maintenance → Schedule during low traffic

Connection Issues?
├── Max connections reached → Increase max_connections or scale
├── Connection leaks → Fix application connection pooling
├── Authentication failures → Check credentials, SSL
└── Network issues → Check security groups, VPC

High Latency?
├── I/O bound → Upgrade storage IOPS, use gp3/io1
├── CPU bound → Scale up instance
├── Lock waits → Optimize transactions
└── Replication lag → Check replica performance

Storage Issues?
├── Transaction logs → Archive/purge old logs
├── Table bloat → VACUUM (PostgreSQL), OPTIMIZE (MySQL)
├── Binary logs → Adjust retention
└── Temp tables → Optimize queries with temp tables
```

## Phase 7: Generate Report

```markdown
## RDS Investigation Report

### Instance Information
- Instance: <instance_identifier>
- Engine: <mysql/postgresql> <version>
- Instance Class: <db.r5.large>
- Multi-AZ: <yes/no>
- Alert: <alert_name>
- Time: <timestamp>

### Health Metrics
| Metric | Current | Threshold | Status |
|--------|---------|-----------|--------|
| CPU Utilization | X% | 80% | OK/WARN/CRIT |
| Connections | X/Y | max_conn | OK/WARN/CRIT |
| Free Storage | X GB | 20% | OK/WARN/CRIT |
| Free Memory | X MB | 10% | OK/WARN/CRIT |
| Read Latency | Xms | 10ms | OK/WARN/CRIT |
| Write Latency | Xms | 10ms | OK/WARN/CRIT |

### Replication Status (if applicable)
| Replica | Lag | Status |
|---------|-----|--------|
| replica-1 | Xs | OK/WARN |

### Root Cause
<description>

### Impact
- Affected applications: <list>
- Duration: <time>
- Data impact: <none/partial/full>

### Recommendations
1. Immediate: <action>
2. Short-term: <action>
3. Long-term: <action>
```

## Quick Reference: Common Issues

| Symptom | Likely Cause | Quick Fix |
|---------|--------------|-----------|
| Sudden connection drop | Restart/Failover | Check event logs, improve HA |
| Gradual connection rise | Connection leak | Fix app connection pooling |
| CPU spike | Bad query | Find and optimize query |
| Storage growing fast | Logs/bloat | Purge logs, vacuum tables |
| High replica lag | Write heavy | Scale replica, optimize writes |

## Remediation Quick Reference

| Issue | Immediate Action |
|-------|-----------------|
| High CPU | Kill long queries, add indexes |
| Connection exhaustion | Increase max_connections, kill idle |
| Storage full | Delete old backups, purge logs |
| High latency | Scale up IOPS, optimize queries |
| Replication lag | Pause non-critical writes, scale replica |
| Restart/failover | Enable Multi-AZ, review maintenance windows |
