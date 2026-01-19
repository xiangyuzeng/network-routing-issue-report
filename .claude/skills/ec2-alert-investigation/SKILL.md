---
name: ec2-alert-investigation
description: This skill should be used when the user asks to "investigate EC2 alert", "debug EC2 instance", "check EC2 performance", "analyze EC2 CPU/memory/disk", mentions EC2 instance issues, VM performance problems, or receives alerts about AWS EC2 instances including CPU spikes, memory pressure, disk full, I/O bottlenecks, or network issues.
allowed-tools: Read, Grep, Glob, Bash, WebFetch, WebSearch, mcp__grafana__*, mcp__grafana-lucky__*, mcp__cloudwatch-server__*, mcp__prometheus__*, mcp__ccapi-server__*
---

# EC2 Instance Alert Investigation

You are investigating an EC2 instance alert. Follow this systematic investigation protocol.

## Phase 1: Parse Alert Context

Extract from the alert or user message:
- **Instance ID**: EC2 instance identifier (i-xxxxxxxxx)
- **Instance name**: Name tag value
- **Region**: AWS region
- **Alert type**: CPU, memory, disk, network, status check
- **Time window**: When the alert fired

## Phase 2: Instance Health Check

### 2.1 CloudWatch Metrics

Query CloudWatch for EC2 metrics:

```promql
# CPU utilization
aws_ec2_cpuutilization_average{instance_id="$instance_id"}

# Network I/O
aws_ec2_network_in_average{instance_id="$instance_id"}
aws_ec2_network_out_average{instance_id="$instance_id"}

# Disk I/O (EBS)
aws_ec2_disk_read_ops_average{instance_id="$instance_id"}
aws_ec2_disk_write_ops_average{instance_id="$instance_id"}
aws_ec2_disk_read_bytes_average{instance_id="$instance_id"}
aws_ec2_disk_write_bytes_average{instance_id="$instance_id"}

# Status checks
aws_ec2_status_check_failed_instance_average{instance_id="$instance_id"}
aws_ec2_status_check_failed_system_average{instance_id="$instance_id"}
```

### 2.2 Node Exporter Metrics (if available)

```promql
# CPU by mode
node_cpu_seconds_total{instance="$instance"}

# Memory
node_memory_MemTotal_bytes{instance="$instance"}
node_memory_MemAvailable_bytes{instance="$instance"}
node_memory_Buffers_bytes{instance="$instance"}
node_memory_Cached_bytes{instance="$instance"}

# Disk
node_filesystem_size_bytes{instance="$instance"}
node_filesystem_avail_bytes{instance="$instance"}
node_disk_io_time_seconds_total{instance="$instance"}

# Load average
node_load1{instance="$instance"}
node_load5{instance="$instance"}
node_load15{instance="$instance"}
```

## Phase 3: CPU Analysis

### 3.1 CPU Metrics

| Metric | Normal | Warning | Critical |
|--------|--------|---------|----------|
| CPU Utilization | < 70% | 70-85% | > 85% |
| Load Average (1m) | < cores | 1-2x cores | > 2x cores |
| CPU Steal | < 5% | 5-10% | > 10% |
| iowait | < 10% | 10-30% | > 30% |

### 3.2 CPU Investigation

```promql
# CPU breakdown
rate(node_cpu_seconds_total{instance="$instance", mode="user"}[5m])
rate(node_cpu_seconds_total{instance="$instance", mode="system"}[5m])
rate(node_cpu_seconds_total{instance="$instance", mode="iowait"}[5m])
rate(node_cpu_seconds_total{instance="$instance", mode="steal"}[5m])
```

## Phase 4: Memory Analysis

### 4.1 Memory Metrics

| Metric | Normal | Warning | Critical |
|--------|--------|---------|----------|
| Memory Used % | < 80% | 80-90% | > 90% |
| Swap Used | 0 | < 50% | > 50% |
| OOM Events | 0 | any | frequent |

### 4.2 Memory Calculation

```promql
# Memory usage percentage
(1 - (node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes)) * 100

# Swap usage
node_memory_SwapTotal_bytes - node_memory_SwapFree_bytes
```

## Phase 5: Disk Analysis

### 5.1 Disk Space

| Metric | Normal | Warning | Critical |
|--------|--------|---------|----------|
| Disk Used % | < 70% | 70-85% | > 85% |
| Inode Used % | < 70% | 70-85% | > 85% |

### 5.2 Disk I/O

```promql
# Disk I/O utilization
rate(node_disk_io_time_seconds_total{instance="$instance"}[5m])

# Read/Write operations
rate(node_disk_reads_completed_total{instance="$instance"}[5m])
rate(node_disk_writes_completed_total{instance="$instance"}[5m])

# Read/Write throughput
rate(node_disk_read_bytes_total{instance="$instance"}[5m])
rate(node_disk_written_bytes_total{instance="$instance"}[5m])
```

### 5.3 EBS Volume Metrics

```promql
# EBS burst balance (for gp2)
aws_ebs_burst_balance_average{volume_id="$volume_id"}

# EBS IOPS
aws_ebs_volume_read_ops_average{volume_id="$volume_id"}
aws_ebs_volume_write_ops_average{volume_id="$volume_id"}

# EBS throughput
aws_ebs_volume_read_bytes_average{volume_id="$volume_id"}
aws_ebs_volume_write_bytes_average{volume_id="$volume_id"}
```

## Phase 6: Network Analysis

### 6.1 Network Metrics

```promql
# Network throughput
rate(node_network_receive_bytes_total{instance="$instance"}[5m])
rate(node_network_transmit_bytes_total{instance="$instance"}[5m])

# Network errors
rate(node_network_receive_errs_total{instance="$instance"}[5m])
rate(node_network_transmit_errs_total{instance="$instance"}[5m])

# TCP connections
node_netstat_Tcp_CurrEstab{instance="$instance"}
```

### 6.2 Network Bandwidth Limits

EC2 instances have network bandwidth limits based on instance type. Check if hitting limits.

## Phase 7: Root Cause Determination

### Decision Tree

```
High CPU?
├── High user% → Application CPU intensive
│   └── Check: top processes, application profiling
├── High system% → Kernel/OS overhead
│   └── Check: syscall rates, context switches
├── High iowait% → Disk I/O bottleneck
│   └── Check: disk I/O metrics, EBS performance
└── High steal% → Noisy neighbor / throttling
    └── Consider: instance type upgrade, dedicated host

High Memory?
├── High used, low cache → Application memory leak
│   └── Check: process memory usage over time
├── High swap → Insufficient RAM
│   └── Consider: instance type upgrade
└── OOM kills → Critical memory pressure
    └── Check: dmesg, application logs

High Disk?
├── Space full → Storage exhaustion
│   └── Check: large files, log rotation
├── High I/O wait → Disk bottleneck
│   └── Check: IOPS, throughput, burst credits
└── High latency → EBS performance issue
    └── Consider: gp3, io1/io2 volumes

Network issues?
├── High packet loss → Network saturation
│   └── Check: bandwidth usage vs limits
├── High latency → Network path issues
│   └── Check: VPC, security groups, routing
└── Connection failures → Port/firewall issues
    └── Check: security groups, NACLs
```

## Phase 8: Generate Report

```markdown
## EC2 Investigation Report

### Instance Information
- Instance ID: <instance_id>
- Instance Name: <name>
- Instance Type: <type>
- Region/AZ: <region>/<az>
- Alert: <alert_name>
- Time: <timestamp>

### Resource Utilization
| Resource | Current | Threshold | Status |
|----------|---------|-----------|--------|
| CPU | X% | 85% | OK/WARN/CRIT |
| Memory | X% | 90% | OK/WARN/CRIT |
| Disk | X% | 85% | OK/WARN/CRIT |
| Network In | X MB/s | limit | OK/WARN/CRIT |
| Network Out | X MB/s | limit | OK/WARN/CRIT |

### Status Checks
| Check | Status |
|-------|--------|
| Instance Status | Passed/Failed |
| System Status | Passed/Failed |

### Root Cause
<description>

### Recommendations
1. Immediate: <action>
2. Short-term: <action>
3. Long-term: <action>
```

## CloudWatch Logs Investigation

Use CloudWatch Logs Insights to search for errors:

```
fields @timestamp, @message
| filter @message like /error|Error|ERROR|exception|Exception/
| sort @timestamp desc
| limit 50
```

## Remediation Quick Reference

| Issue | Immediate Action |
|-------|-----------------|
| High CPU | Identify process, scale horizontally |
| High Memory | Add swap, increase instance size |
| Disk Full | Clean logs, expand volume |
| I/O Bottleneck | Upgrade to gp3/io1, increase IOPS |
| Network Saturation | Enable enhanced networking, scale |
| Status Check Failed | Stop/start instance, contact AWS |
