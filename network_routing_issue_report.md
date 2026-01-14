# 网络路由问题报告

## 问题概述

从 VPN 网络无法访问 EC2 实例上的 Grafana 服务，连接超时。

---

## 环境信息

| 项目 | 值 |
|------|-----|
| **用户 VPN IP** | 10.200.3.233 |
| **目标 EC2 实例** | i-062d7f19b074225fa |
| **目标 EC2 私网 IP** | 10.238.3.43 |
| **目标服务** | Grafana (端口 3000) |
| **VPC ID** | vpc-0dce7ca7770422d33 |
| **子网 ID** | subnet-0828db1b483e7e580 |
| **安全组** | sg-0deaa7cf7437e39c7 (sg_public_prod) |
| **AWS 账户** | 257394478466 |
| **区域** | us-east-1 |

---

## 问题现象

1. 用户从 VPN (10.200.3.233) 访问 http://10.238.3.43:3000 时连接超时 (ERR_CONNECTION_TIMED_OUT)
2. 从同网段的跳板机 (10.238.3.67) 访问 http://10.238.3.43:3000 正常
3. Grafana 服务本身运行正常

---

## 排查结果

### 1. 安全组配置 - 已正确配置 ✅

安全组 sg-0deaa7cf7437e39c7 的入站规则已允许 VPN 网段访问：

- **规则**: 允许所有协议 (IpProtocol: -1)
- **来源**: VPN Prefix List (pl-0aebebeca1874725b)
- **Prefix List 包含**: 10.200.2.0/23 (覆盖用户 IP 10.200.3.233)

### 2. 路由表配置 - 发现问题 ❌

EC2 所在子网 (subnet-0828db1b483e7e580) 的路由表显示：

| 目标网段 | 下一跳 | 说明 |
|---------|--------|------|
| 10.238.0.0/16 | local | VPC 本地路由 |
| **10.200.2.0/23** | **i-01e0ee9e752caac31** | ⚠️ 指向 SSL VPN 实例 |
| 10.200.96.0/20 | i-0f8d8fa6277335edf | 指向特定实例 |
| 10.0.0.0/8 | tgw-0f7f370e8a1866f8e | Transit Gateway |
| 0.0.0.0/0 | nat-03c52cf4018461ab7 | NAT Gateway |

### 3. 问题路由指向的实例详情

| 项目 | 值 |
|------|-----|
| **实例 ID** | i-01e0ee9e752caac31 |
| **实例名称** | luckysslvpn01-prod-usa-aws |
| **用途** | SSL VPN 网关 |
| **实例类型** | m4.xlarge |
| **私网 IP** | 10.238.3.180 |
| **SourceDestCheck** | false (已关闭，确认为网络转发设备) |
| **状态** | running |
| **启动时间** | 2025-02-10 |
| **安全组** | sg_public_prod, sg_lfe_prod |

---

## 问题分析 - 非对称路由

### 流量路径分析

**去程路径** (正常):
```
用户 (10.200.3.233) 
    ↓
用户 VPN 客户端
    ↓
Transit Gateway (tgw-0f7f370e8a1866f8e)
    ↓
EC2 (10.238.3.43) ✅ 请求到达
```

**回程路径** (异常):
```
EC2 (10.238.3.43)
    ↓
路由表匹配: 10.200.2.0/23 → i-01e0ee9e752caac31
    ↓
SSL VPN 网关 (luckysslvpn01-prod-usa-aws, 10.238.3.180)
    ↓
??? ❌ 响应无法返回用户
```

### 根本原因

1. **回程流量被路由到错误的 VPN 网关**
   - 用户 IP 10.200.3.233 属于 10.200.2.0/23 网段
   - 路由表将该网段的流量指向 SSL VPN 实例 (luckysslvpn01)
   - 但用户可能使用的是另一套 VPN 系统，不是这台 SSL VPN

2. **SSL VPN 网关转发问题**
   - 即使用户使用的是同一套 VPN，该 SSL VPN 可能没有正确配置回程转发

---

## 建议解决方案

### 方案 A: 检查 SSL VPN 转发配置 (推荐)

1. 登录 luckysslvpn01-prod-usa-aws (10.238.3.180)
2. 检查 VPN 转发规则，确认是否正确转发到 10.200.2.0/23 网段
3. 检查 iptables/路由表配置

```bash
# 在 luckysslvpn01 上检查
ip route
iptables -t nat -L -n -v
```

### 方案 B: 修改 VPC 路由表

如果用户 VPN 流量不应该经过 luckysslvpn01：

1. 移除路由: 10.200.2.0/23 → i-01e0ee9e752caac31
2. 让流量统一走 Transit Gateway (10.0.0.0/8 → tgw-0f7f370e8a1866f8e)

### 方案 C: 确认 VPN 架构

确认以下问题：
1. 用户连接的 VPN 是哪个系统？
2. luckysslvpn01 是否是该 VPN 系统的一部分？
3. 10.200.2.0/23 的路由是否应该指向 luckysslvpn01？

---

## 验证测试

修复后请执行以下测试：

**从 VPN 客户端测试:**
```bash
ping 10.238.3.43
curl -I http://10.238.3.43:3000
```

**预期结果:**
- ping 应有响应
- curl 应返回 HTTP 302 重定向到 /login

---

## 附录：相关资源 ID

### 目标 EC2 实例
- **实例 ID**: i-062d7f19b074225fa
- **私网 IP**: 10.238.3.43
- **服务**: Grafana (端口 3000)

### 网络资源
- **VPC**: vpc-0dce7ca7770422d33
- **子网**: subnet-0828db1b483e7e580
- **安全组**: sg-0deaa7cf7437e39c7 (sg_public_prod)
- **Transit Gateway**: tgw-0f7f370e8a1866f8e
- **NAT Gateway**: nat-03c52cf4018461ab7
- **VPN Prefix List**: pl-0aebebeca1874725b

### 问题相关实例
- **SSL VPN 实例 ID**: i-01e0ee9e752caac31
- **SSL VPN 名称**: luckysslvpn01-prod-usa-aws
- **SSL VPN 私网 IP**: 10.238.3.180

---

**报告生成时间**: 2026-01-14  
**报告人**: [您的姓名]
