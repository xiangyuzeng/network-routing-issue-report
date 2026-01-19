---
name: elasticsearch-alert-investigation
description: This skill should be used when the user asks to "investigate Elasticsearch alert", "debug ES cluster", "check OpenSearch health", "analyze search performance", mentions Elasticsearch/OpenSearch issues, cluster health red/yellow, shard allocation problems, JVM memory pressure, or receives alerts about search clusters including index issues, query latency, or storage problems.
allowed-tools: Read, Grep, Glob, Bash, WebFetch, WebSearch, mcp__grafana__*, mcp__grafana-lucky__*, mcp__cloudwatch-server__*, mcp__prometheus__*
---

# Elasticsearch/OpenSearch Alert Investigation

You are investigating an Elasticsearch or AWS OpenSearch alert. Follow this systematic investigation protocol.

## Phase 1: Parse Alert Context

Extract from the alert or user message:
- **Cluster name**: ES/OpenSearch cluster identifier
- **Domain name**: AWS OpenSearch domain (if applicable)
- **Alert type**: Cluster health, JVM, storage, query latency, indexing
- **Time window**: When the alert fired

## Phase 2: Cluster Health Check

### 2.1 Cluster Status Meaning

| Status | Meaning | Urgency |
|--------|---------|---------|
| **GREEN** | All primary and replica shards allocated | Normal |
| **YELLOW** | All primaries OK, some replicas unassigned | Monitor |
| **RED** | Some primary shards unassigned | Critical - data at risk |

### 2.2 AWS OpenSearch/ES CloudWatch Metrics

```promql
# Cluster status (1=RED, value indicates status)
aws_es_cluster_status_red_maximum{domain_name="$domain"}
aws_es_cluster_status_yellow_maximum{domain_name="$domain"}
aws_es_cluster_status_green_maximum{domain_name="$domain"}

# Node count
aws_es_nodes_average{domain_name="$domain"}

# CPU utilization
aws_es_cpuutilization_average{domain_name="$domain"}

# JVM memory pressure
aws_es_jvmmemory_pressure_average{domain_name="$domain"}

# Free storage
aws_es_free_storage_space_average{domain_name="$domain"}

# Cluster used space
aws_es_cluster_used_space_average{domain_name="$domain"}
```

### 2.3 Elasticsearch Exporter Metrics (if available)

```promql
# Cluster health
elasticsearch_cluster_health_status{cluster="$cluster"}
elasticsearch_cluster_health_number_of_nodes{cluster="$cluster"}
elasticsearch_cluster_health_number_of_data_nodes{cluster="$cluster"}

# Shard status
elasticsearch_cluster_health_active_shards{cluster="$cluster"}
elasticsearch_cluster_health_unassigned_shards{cluster="$cluster"}
elasticsearch_cluster_health_relocating_shards{cluster="$cluster"}
elasticsearch_cluster_health_initializing_shards{cluster="$cluster"}

# JVM metrics
elasticsearch_jvm_memory_used_bytes{cluster="$cluster"}
elasticsearch_jvm_memory_max_bytes{cluster="$cluster"}
elasticsearch_jvm_gc_collection_seconds_sum{cluster="$cluster"}
```

## Phase 3: JVM and Memory Analysis

### 3.1 JVM Health Thresholds

| Metric | Warning | Critical |
|--------|---------|----------|
| JVM Memory Pressure | > 75% | > 85% |
| GC Time % | > 5% | > 10% |
| Old Gen Usage | > 75% | > 90% |

### 3.2 JVM Metrics

```promql
# JVM heap usage
elasticsearch_jvm_memory_used_bytes{area="heap"} / elasticsearch_jvm_memory_max_bytes{area="heap"}

# GC collections
rate(elasticsearch_jvm_gc_collection_seconds_count[5m])
rate(elasticsearch_jvm_gc_collection_seconds_sum[5m])

# Thread pools
elasticsearch_thread_pool_threads{cluster="$cluster"}
elasticsearch_thread_pool_queue{cluster="$cluster"}
elasticsearch_thread_pool_rejected{cluster="$cluster"}
```

### 3.3 Memory Pressure Causes

| Symptom | Cause | Solution |
|---------|-------|----------|
| High heap usage | Large aggregations | Limit bucket sizes, use filters |
| Frequent GC | Memory pressure | Increase heap, reduce load |
| Circuit breaker trips | Query too large | Optimize query, increase breaker |

## Phase 4: Shard Analysis

### 4.1 Shard Health Indicators

```promql
# Shard counts
elasticsearch_cluster_health_active_primary_shards
elasticsearch_cluster_health_active_shards
elasticsearch_cluster_health_unassigned_shards
elasticsearch_cluster_health_delayed_unassigned_shards
```

### 4.2 Common Shard Issues

| Issue | Symptoms | Resolution |
|-------|----------|------------|
| Unassigned shards | YELLOW/RED status | Check disk space, node capacity |
| Too many shards | Slow cluster, high memory | Reduce shard count, use ILM |
| Large shards | Slow recovery, queries | Target 10-50GB per shard |
| Hot spots | Uneven load | Improve routing, add nodes |

### 4.3 Shard Allocation Decision Tree

```
Unassigned Shards?
├── Disk watermark exceeded
│   └── Free up space or add nodes
├── Node capacity reached
│   └── Add data nodes
├── Allocation rules
│   └── Check index settings, awareness attributes
├── Recovery throttled
│   └── Increase recovery settings temporarily
└── Corrupt shard
    └── Restore from replica or snapshot
```

## Phase 5: Performance Analysis

### 5.1 Query Performance Metrics

```promql
# Search rate
rate(elasticsearch_indices_search_query_total[5m])

# Search latency
elasticsearch_indices_search_query_time_seconds / elasticsearch_indices_search_query_total

# Indexing rate
rate(elasticsearch_indices_indexing_index_total[5m])

# Indexing latency
elasticsearch_indices_indexing_index_time_seconds / elasticsearch_indices_indexing_index_total
```

### 5.2 Performance Thresholds

| Metric | Good | Acceptable | Poor |
|--------|------|------------|------|
| Search Latency | < 100ms | 100-500ms | > 500ms |
| Index Latency | < 50ms | 50-200ms | > 200ms |
| Refresh Time | < 1s | 1-5s | > 5s |

### 5.3 Thread Pool Analysis

```promql
# Rejections (indicates overload)
rate(elasticsearch_thread_pool_rejected_count{type="search"}[5m])
rate(elasticsearch_thread_pool_rejected_count{type="write"}[5m])

# Queue depth
elasticsearch_thread_pool_queue_count{type="search"}
elasticsearch_thread_pool_queue_count{type="write"}
```

## Phase 6: Storage Analysis

### 6.1 Storage Metrics

```promql
# Disk usage
elasticsearch_filesystem_data_size_bytes
elasticsearch_filesystem_data_free_bytes

# Index size
elasticsearch_indices_store_size_bytes
```

### 6.2 Storage Thresholds

| Threshold | Default | Effect |
|-----------|---------|--------|
| Low watermark | 85% | No new shards allocated |
| High watermark | 90% | Shards relocated away |
| Flood stage | 95% | Index becomes read-only |

### 6.3 Storage Management

- Enable Index Lifecycle Management (ILM)
- Use rollover for time-series data
- Delete old indices
- Consider snapshot and delete

## Phase 7: Root Cause Determination

### Decision Tree

```
Cluster RED?
├── Primary shards unassigned
│   ├── Disk full → Free space, add nodes
│   ├── Node down → Restart node, check logs
│   ├── Corruption → Restore from snapshot
│   └── Split brain → Check master election
└── Multiple nodes failed
    └── Check infrastructure, AWS status

Cluster YELLOW?
├── Replica shards unassigned
│   ├── Not enough nodes → Add nodes for replicas
│   ├── Disk watermark → Free space
│   └── Allocation filtered → Check settings
└── Recovery in progress
    └── Wait for recovery, check progress

High JVM Pressure?
├── Large aggregations → Limit buckets, use filters
├── Too many shards → Consolidate indices
├── Field data → Use doc values, limit field data
└── Memory leak → Restart, upgrade version

High Latency?
├── Search latency
│   ├── Complex queries → Optimize queries
│   ├── Large result sets → Use pagination
│   └── Cold data → Warm up, use SSD
└── Index latency
    ├── Bulk size too small → Increase bulk size
    ├── Refresh too frequent → Increase refresh interval
    └── Merge throttling → Adjust merge settings
```

## Phase 8: Generate Report

```markdown
## Elasticsearch Investigation Report

### Cluster Information
- Cluster/Domain: <cluster_name>
- Version: <version>
- Node Count: <count>
- Alert: <alert_name>
- Time: <timestamp>

### Cluster Health
| Metric | Current | Status |
|--------|---------|--------|
| Cluster Status | RED/YELLOW/GREEN | CRIT/WARN/OK |
| Active Nodes | X/Y | OK/WARN |
| Active Shards | X | OK |
| Unassigned Shards | X | OK/WARN/CRIT |
| Relocating Shards | X | OK |

### Resource Utilization
| Node | CPU | JVM Heap | Disk | Status |
|------|-----|----------|------|--------|
| node-1 | X% | Y% | Z% | OK/WARN/CRIT |
| node-2 | X% | Y% | Z% | OK/WARN/CRIT |

### Performance Metrics
| Metric | Current | Baseline | Status |
|--------|---------|----------|--------|
| Search Rate | X/s | Y/s | OK |
| Search Latency | Xms | Yms | OK/WARN |
| Index Rate | X/s | Y/s | OK |
| Index Latency | Xms | Yms | OK/WARN |

### Root Cause
<description>

### Impact
- Affected indices: <list>
- Affected services: <list>
- Data availability: <full/partial/degraded>

### Recommendations
1. Immediate: <action>
2. Short-term: <action>
3. Long-term: <action>
```

## Quick Reference: Common Issues

| Symptom | Likely Cause | Quick Fix |
|---------|--------------|-----------|
| RED status | Primary shard lost | Restore from replica/snapshot |
| YELLOW status | Missing replicas | Add nodes, fix allocation |
| High JVM pressure | Memory issues | Reduce load, increase heap |
| Slow queries | Poor query design | Optimize queries, add filters |
| Slow indexing | Bottleneck | Increase bulk size, reduce replicas |
| Circuit breaker | Query too large | Break up query, increase limit |

## Remediation Quick Reference

| Issue | Immediate Action |
|-------|-----------------|
| Cluster RED | Identify unassigned primaries, restore |
| Cluster YELLOW | Check disk space, node count |
| High JVM | Reduce query load, restart if needed |
| Disk full | Delete old indices, expand storage |
| Slow performance | Identify hot indices, optimize |
| Node failure | Replace node, let cluster recover |
