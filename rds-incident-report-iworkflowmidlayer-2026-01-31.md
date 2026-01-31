# RDS 事故调查报告 - aws-luckyus-iworkflowmidlayer-rw

## 📋 执行摘要

**事故时间**: 2026-01-31 21:40:55 UTC (北京时间 2026-02-01 05:40:55)
**影响时长**: 约 1 分钟（Multi-AZ 故障转移）
**根本原因**: **内存不足导致主实例无响应，触发 Multi-AZ 自动故障转移**
**严重程度**: 🔴 高危 - 资源配置严重不足

---

## 🔍 事故时间线

| 时间 (UTC) | 事件 | 说明 |
|-----------|------|------|
| 21:40:55 | Multi-AZ 故障转移启动 | 检测到主实例无响应 |
| 21:41:12 | 数据库实例重启 | 切换到备用实例 |
| 21:41:41 | Multi-AZ 故障转移完成 | 服务恢复正常 |
| 21:41:41 | ⚠️ **根因确认** | **"RDS Multi-AZ primary instance is busy and unresponsive"** |
| 21:45:44 | RDS 自动干预 | **"Database workload causing system to run critically low on memory"**<br>RDS 自动将 innodb_buffer_pool_size 保持在 128MB |

**总中断时长**: ~46 秒（从故障转移开始到完成）

---

## 🎯 根本原因分析

### 1. 实例配置严重不足

```
实例类型: db.t4g.micro
├── vCPU: 2 核
├── 总内存: 1 GiB (1024 MB) ⚠️
├── 存储: 20 GB
├── 引擎: MySQL 8.0.40
└── Multi-AZ: 已启用 ✅
```

**问题**: db.t4g.micro 是 AWS RDS 最小的实例类型，仅 1GB 内存，**不适合生产环境使用**。

### 2. 内存使用情况

#### 故障时刻内存状态
```
时间点          可用内存    使用率     状态
21:24 (故障前)   102 MB     90.0%     ⚠️ 警告
21:39 (触发时)    98 MB     90.4%     🔴 危险
21:42 (重启后)    90 MB     91.2%     🔴 危险
```

#### 一周内存趋势
```
时间段              平均可用内存    内存压力
凌晨 04:00-07:00    106-107 MB     中等
白天 11:00-19:00     94-98 MB      高
晚上 20:00-22:00     90-100 MB     极高
```

**结论**:
- 可用内存长期维持在 90-107 MB（仅 9-10%）
- 内存压力呈现日常规律，业务高峰期（白天和晚上）内存最紧张
- **故障发生在晚上 21:40，正值业务高峰 + 内存最紧张时段**

### 3. CPU 使用情况

```
故障前后 CPU 使用率: 7-12%
```

**结论**: CPU 资源充足，**不是性能瓶颈**。问题完全由内存不足引起。

### 4. 数据库工作负载

```
指标                  故障前值       故障后值
连接数                17-27         10-19 (恢复中)
最大连接数配置        4000          4000
连接使用率            < 1%          < 1%
慢查询累计            44,193        从 19 重新开始
查询总数              5,584,835     从 786 重新开始
InnoDB 行锁等待       645 (累计)    重置为 0
```

**结论**:
- 连接数正常，无连接泄漏
- 慢查询存在但增长缓慢（约 15-30 个/5分钟）
- 行锁竞争很少
- **工作负载正常，但内存配置无法支撑**

---

## 💥 故障机制

```
内存不足的级联效应:

1. 长期内存压力 (90-91% 使用率)
     ↓
2. 业务高峰期进一步消耗内存
     ↓
3. 可用内存降至 90 MB (8.8%)
     ↓
4. 主实例响应变慢/无响应
     ↓
5. Multi-AZ 健康检查失败
     ↓
6. 自动触发故障转移
     ↓
7. 切换到备用实例 (46 秒)
     ↓
8. RDS 检测到内存问题
     ↓
9. RDS 尝试优化配置（但无法解决根本问题）
```

---

## 📊 影响评估

### 业务影响
- ✅ **恢复迅速**: Multi-AZ 自动故障转移仅 46 秒
- ⚠️ **所有连接中断**: 应用需要重新建立数据库连接
- ⚠️ **短暂服务不可用**: 约 1 分钟内数据库无法响应
- ✅ **无数据丢失**: Multi-AZ 确保数据完整性

### 受影响应用
- 所有依赖 `aws-luckyus-iworkflowmidlayer-rw` 的应用
- iworkflowmidlayer 相关服务

---

## 🚨 风险评估

### 当前风险 🔴 极高

| 风险项 | 严重性 | 说明 |
|--------|-------|------|
| 再次故障转移 | 🔴 极高 | 内存压力依然存在，随时可能再次触发 |
| 性能下降 | 🔴 高 | 内存不足导致频繁 I/O，影响查询性能 |
| 业务中断 | 🔴 高 | 下次可能在更关键的时刻故障 |
| 数据库响应慢 | 🟡 中 | 缓存不足，查询依赖磁盘 I/O |

### 为什么会再次发生？

```
当前状态:
- 内存配置: 1 GB (未改变)
- 内存使用: 仍然 90-91% (未改善)
- 工作负载: 持续增长 (压力增加)

结论: 🔴 如不升级实例，故障必然重演！
```

---

## ✅ 解决方案

### 🚀 立即行动（必须！）

#### 方案 1: 升级实例类型（强烈推荐）

```bash
# 升级到 db.t4g.small (2GB 内存)
aws rds modify-db-instance \
  --db-instance-identifier aws-luckyus-iworkflowmidlayer-rw \
  --db-instance-class db.t4g.small \
  --apply-immediately

# 或升级到 db.t4g.medium (4GB 内存) - 更安全
aws rds modify-db-instance \
  --db-instance-identifier aws-luckyus-iworkflowmidlayer-rw \
  --db-instance-class db.t4g.medium \
  --apply-immediately
```

**实例对比**:

| 实例类型 | vCPU | 内存 | 月成本估算 | 推荐度 |
|----------|------|------|-----------|--------|
| db.t4g.micro (当前) | 2 | 1 GB | ~$12 | 🔴 不推荐 |
| db.t4g.small | 2 | 2 GB | ~$24 | ✅ 最小推荐 |
| **db.t4g.medium** | 2 | **4 GB** | **~$48** | ⭐ **强烈推荐** |
| db.r7g.large | 2 | 16 GB | ~$145 | 💰 性能优先 |

**推荐**: **db.t4g.medium (4GB)**
- 成本合理（月增约 $36）
- 内存充足（4倍提升）
- 为业务增长留有余量

#### 方案 2: 优化应用查询（辅助手段）

```sql
-- 1. 检查慢查询
SELECT * FROM mysql.slow_log ORDER BY query_time DESC LIMIT 20;

-- 2. 优化索引使用
SELECT * FROM sys.schema_unused_indexes;
SELECT * FROM sys.schema_redundant_indexes;

-- 3. 分析表大小
SELECT
    table_schema,
    table_name,
    ROUND(((data_length + index_length) / 1024 / 1024), 2) AS `Size (MB)`
FROM information_schema.tables
WHERE table_schema NOT IN ('mysql', 'information_schema', 'performance_schema', 'sys')
ORDER BY (data_length + index_length) DESC
LIMIT 20;
```

**注意**: 优化查询**无法解决内存不足的根本问题**，必须配合升级实例。

---

### 🔧 短期优化（2周内）

1. **监控告警配置**
```bash
# 创建内存告警
aws cloudwatch put-metric-alarm \
  --alarm-name rds-iworkflowmidlayer-low-memory \
  --alarm-description "可用内存低于 200MB" \
  --metric-name FreeableMemory \
  --namespace AWS/RDS \
  --statistic Average \
  --period 300 \
  --threshold 209715200 \
  --comparison-operator LessThanThreshold \
  --evaluation-periods 2 \
  --dimensions Name=DBInstanceIdentifier,Value=aws-luckyus-iworkflowmidlayer-rw
```

2. **连接池优化**
   - 检查应用连接池配置
   - 确保支持自动重连
   - 实施连接超时和重试机制

3. **审查慢查询**
   - 分析 slow_log
   - 添加缺失索引
   - 优化 N+1 查询

---

### 🏗️ 长期改进（1-3个月）

1. **容量规划**
   - 建立内存/CPU 基线
   - 制定扩容阈值（内存 > 70% 即扩容）
   - 定期审查资源使用趋势

2. **高可用性增强**
   - ✅ Multi-AZ 已启用
   - 考虑 Aurora MySQL（自动扩展）
   - 配置只读副本分担查询压力

3. **监控完善**
   - 集成到 Grafana 告警
   - 配置 PagerDuty/SNS 通知
   - 建立故障响应手册

4. **数据库优化**
   - 定期 ANALYZE TABLE
   - 清理历史数据
   - 考虑分库分表

---

## 📈 成本分析

### 升级成本对比

```
当前配置 (db.t4g.micro):
- 月成本: ~$12
- 风险: 🔴 极高（随时再次故障）
- 性能: 🔴 差

推荐配置 (db.t4g.medium):
- 月成本: ~$48
- 增加成本: ~$36/月
- 风险: ✅ 低
- 性能: ✅ 优秀
- 内存提升: 4倍 (1GB → 4GB)

ROI 分析:
- 避免故障中断损失 >> $36/月
- 提升用户体验
- 支撑业务增长
- 减少运维成本

结论: 强烈建议立即升级！
```

---

## 📝 总结

### 关键发现
1. ✅ **Multi-AZ 工作正常** - 自动故障转移仅 46 秒
2. 🔴 **db.t4g.micro 严重不足** - 仅 1GB 内存无法满足生产需求
3. 🔴 **内存压力长期存在** - 一周内一直运行在 90%+ 使用率
4. ⚠️ **故障必然重演** - 如不升级，下次故障不可避免

### 必须行动
🚨 **立即升级到 db.t4g.medium (4GB)** - 这不是建议，是必须！

### 次要行动
- 配置内存告警
- 优化慢查询
- 完善监控体系

---

## 🔗 附录

### 相关日志
- RDS Event Logs: `/aws/rds/instance/aws-luckyus-iworkflowmidlayer-rw/error`
- CloudWatch Metrics: `AWS/RDS` namespace
- 应用日志: 检查 2026-01-31 21:40-21:45 UTC 期间的连接错误

### 参考文档
- [AWS RDS 实例类型](https://aws.amazon.com/rds/instance-types/)
- [RDS Multi-AZ 部署](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/Concepts.MultiAZ.html)
- [MySQL 内存优化](https://dev.mysql.com/doc/refman/8.0/en/memory-use.html)

---

**报告生成时间**: 2026-01-31
**调查人员**: Claude (AI Assistant)
**优先级**: 🔴 P0 - 需立即处理
