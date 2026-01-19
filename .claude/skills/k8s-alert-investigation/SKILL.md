---
name: k8s-alert-investigation
description: This skill should be used when the user asks to "investigate Kubernetes alert", "debug K8s pods", "check EKS cluster", "analyze pod crashes", mentions Kubernetes/EKS issues, pod failures, OOMKilled, CrashLoopBackOff, pending pods, node problems, or receives alerts about container orchestration including resource limits, scheduling failures, or deployment issues.
allowed-tools: Read, Grep, Glob, Bash, WebFetch, WebSearch, mcp__grafana__*, mcp__grafana-lucky__*, mcp__cloudwatch-server__*, mcp__prometheus__*, mcp__eks-server__*
---

# Kubernetes/EKS Alert Investigation

You are investigating a Kubernetes or EKS alert. Follow this systematic investigation protocol.

## Phase 1: Parse Alert Context

Extract from the alert or user message:
- **Cluster name**: EKS cluster or K8s cluster identifier
- **Namespace**: Target namespace (default if not specified)
- **Resource type**: Pod, Deployment, Node, Service, etc.
- **Resource name**: Specific resource name
- **Alert type**: CrashLoop, OOM, Pending, Failed, etc.

## Phase 2: Cluster Health Check

### 2.1 Node Status

```promql
# Node availability
kube_node_status_condition{condition="Ready", status="true"}

# Node resource pressure
kube_node_status_condition{condition="MemoryPressure", status="true"}
kube_node_status_condition{condition="DiskPressure", status="true"}
kube_node_status_condition{condition="PIDPressure", status="true"}

# Node capacity
kube_node_status_capacity
kube_node_status_allocatable
```

### 2.2 Pod Status

```promql
# Pod phase
kube_pod_status_phase{namespace="$namespace"}

# Container restarts
kube_pod_container_status_restarts_total{namespace="$namespace"}

# Container states
kube_pod_container_status_waiting_reason{namespace="$namespace"}
kube_pod_container_status_terminated_reason{namespace="$namespace"}
```

## Phase 3: Resource Analysis

### 3.1 CPU and Memory Usage

```promql
# Container CPU usage
container_cpu_usage_seconds_total{namespace="$namespace", pod="$pod"}

# Container memory usage
container_memory_working_set_bytes{namespace="$namespace", pod="$pod"}

# Resource requests vs limits
kube_pod_container_resource_requests{namespace="$namespace"}
kube_pod_container_resource_limits{namespace="$namespace"}
```

### 3.2 Resource Quotas

```promql
# Namespace resource quota usage
kube_resourcequota{namespace="$namespace"}
```

## Phase 4: Pod Investigation

### 4.1 Common Pod Issues

| Status | Meaning | Investigation |
|--------|---------|---------------|
| **Pending** | Cannot be scheduled | Check node resources, affinity, taints |
| **CrashLoopBackOff** | Container crashes repeatedly | Check logs, exit codes |
| **OOMKilled** | Out of memory | Check memory limits vs usage |
| **ImagePullBackOff** | Cannot pull image | Check image name, registry access |
| **CreateContainerError** | Container creation failed | Check container config, volumes |
| **Evicted** | Node resource pressure | Check node conditions |

### 4.2 Get Pod Events

Use the EKS MCP tools:
```
get_k8s_events(cluster_name, kind="Pod", name="<pod-name>", namespace="<namespace>")
```

### 4.3 Get Pod Logs

```
get_pod_logs(cluster_name, namespace, pod_name, tail_lines=100)
```

For previous container (crashed):
```
get_pod_logs(cluster_name, namespace, pod_name, previous=true)
```

## Phase 5: Deployment Analysis

### 5.1 Deployment Status

```promql
# Deployment replicas
kube_deployment_status_replicas{namespace="$namespace"}
kube_deployment_status_replicas_available{namespace="$namespace"}
kube_deployment_status_replicas_unavailable{namespace="$namespace"}

# Deployment conditions
kube_deployment_status_condition{namespace="$namespace"}
```

### 5.2 ReplicaSet Analysis

```promql
kube_replicaset_status_replicas{namespace="$namespace"}
kube_replicaset_status_ready_replicas{namespace="$namespace"}
```

## Phase 6: Network Analysis

### 6.1 Service Status

```promql
# Service endpoints
kube_service_info{namespace="$namespace"}
kube_endpoint_address_available{namespace="$namespace"}
```

### 6.2 Network Policies

Check if network policies are blocking traffic.

## Phase 7: Root Cause Determination

### Decision Tree

```
Pod not running?
├── Pending
│   ├── Insufficient CPU/Memory → Scale nodes or reduce requests
│   ├── No matching nodes → Check node selectors, affinity
│   ├── Taints/Tolerations → Add tolerations or remove taints
│   └── Volume not available → Check PVC status
├── CrashLoopBackOff
│   ├── Exit code 0 → App completing too fast, check command
│   ├── Exit code 1 → App error, check logs
│   ├── Exit code 137 → OOMKilled, increase memory limit
│   └── Exit code 143 → SIGTERM, graceful shutdown issue
├── ImagePullBackOff
│   ├── 401/403 → Authentication issue
│   ├── 404 → Image not found
│   └── Timeout → Registry network issue
└── Evicted
    ├── Memory pressure → Node OOM, check node memory
    └── Disk pressure → Node disk full, check storage
```

## Phase 8: Generate Report

```markdown
## Kubernetes Investigation Report

### Cluster Information
- Cluster: <cluster_name>
- Namespace: <namespace>
- Resource: <resource_type>/<resource_name>
- Alert: <alert_name>
- Time: <timestamp>

### Resource Status
| Resource | Status | Restarts | Age |
|----------|--------|----------|-----|
| pod-1 | Running | 0 | 2d |
| pod-2 | CrashLoopBackOff | 15 | 1h |

### Node Health
| Node | CPU% | Memory% | Status |
|------|------|---------|--------|
| node-1 | 45% | 72% | Ready |
| node-2 | 89% | 95% | MemoryPressure |

### Root Cause
<description>

### Affected Services
- <service_1>
- <service_2>

### Recommendations
1. Immediate: <action>
2. Short-term: <action>
3. Long-term: <action>
```

## Quick Reference Commands

| Task | MCP Tool |
|------|----------|
| List pods | `list_k8s_resources(cluster, "Pod", "v1", namespace)` |
| Get pod details | `manage_k8s_resource("read", cluster, "Pod", "v1", name, namespace)` |
| Get events | `get_k8s_events(cluster, kind, name, namespace)` |
| Get logs | `get_pod_logs(cluster, namespace, pod_name)` |
| List nodes | `list_k8s_resources(cluster, "Node", "v1")` |

## Remediation Quick Reference

| Issue | Immediate Action |
|-------|-----------------|
| OOMKilled | Increase memory limits |
| CrashLoopBackOff | Check logs, fix app error |
| Pending (resources) | Scale cluster or reduce requests |
| ImagePullBackOff | Fix image name or credentials |
| Node NotReady | Drain and investigate node |
| Evicted | Clear disk space, add nodes |
