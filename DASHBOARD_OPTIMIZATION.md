# Dashboard 优化方案

## 优化内容

根据您的需求，已对 Dashboard 进行以下优化：

### 1. 变量配置优化 ✅

**变更前：**
- Instance 变量支持多选
- 包含 "All" 选项

**变更后：**
- Instance 变量改为**单选**（`multi: false`）
- 移除 "All" 选项（`includeAll: false`）
- 一次只能查看一个数据库实例的详细数据

### 2. Panel 布局重新设计 ✅

新的 Dashboard 包含 4 个面板：

#### Panel 1: 数据库大小变化趋势（时间序列图）
- **位置**: 顶部，全宽
- **功能**: 显示所选实例的数据库大小变化趋势（90天）
- **依赖**: 使用 `${instance}` 变量过滤
- **特点**:
  - 每个数据库显示为独立曲线
  - Legend 显示最新值、最大值、最小值
  - 平滑曲线显示

#### Panel 2: 增长最快的数据库实例（表格）
- **位置**: 中部，全宽
- **功能**: 显示所有实例中增长最快的 Top 10 数据库
- **依赖**: **不依赖** Instance 变量，显示全局数据
- **显示字段**:
  - `instance` - 实例名称
  - `database_name` - 数据库名称
  - `current_size` - 当前大小
  - `size_30_days_ago` - 30天前大小
  - `growth_amount` - 增长量
  - `growth_rate_percent` - 增长率（百分比）
- **排序**: 按增长率降序
- **计算逻辑**:
  ```sql
  增长量 = 当前大小 - 30天前大小
  增长率 = (增长量 / 30天前大小) × 100%
  ```

#### Panel 3: 剩余空间最少的实例（表格）
- **位置**: 中下部，全宽
- **功能**: 显示所有实例中剩余存储空间最少的 Top 10
- **依赖**: **不依赖** Instance 变量，显示全局数据
- **数据来源**: `t_dba_collect_rds_instances` 表
- **显示字段**:
  - `instance` - 实例名称
  - `database_name` - 数据库名称
  - `allocated_storage` - 已分配存储（GB）
  - `max_allocated_storage` - 最大存储限制（GB）
  - `remaining_storage_gb` - 剩余存储空间（GB）
  - `remaining_percent` - 剩余空间百分比
- **排序**: 按剩余空间升序（最少的在前）
- **颜色标识**:
  - 绿色: > 50% 剩余
  - 黄色: 20% - 50% 剩余
  - 红色: < 20% 剩余（需要关注）
- **计算逻辑**:
  ```sql
  剩余空间 = max_allocated_storage - allocated_storage
  剩余百分比 = (剩余空间 / max_allocated_storage) × 100%
  ```

#### Panel 4: 数据库大小详细数据（表格）
- **位置**: 底部，全宽
- **功能**: 显示所选实例的最近 500 条数据记录
- **依赖**: 使用 `${instance}` 变量过滤
- **显示字段**:
  - `database_name` - 数据库名称（无需显示 instance，因为已经通过变量选择）
  - `data_date` - 数据日期
  - `data_length` - 数据库大小
- **特点**: 移除了 instance 列，因为只显示单个实例的数据

### 3. SQL 查询优化

#### 增长速度计算查询
```sql
SELECT
  t1.instance,
  t1.database_name,
  t1.data_length as current_size,
  t2.data_length as size_30_days_ago,
  (t1.data_length - t2.data_length) as growth_amount,
  ROUND((t1.data_length - t2.data_length) / t2.data_length * 100, 2) as growth_rate_percent
FROM (
  SELECT instance, database_name, MAX(data_date) as max_date
  FROM luckyus_db_collection.t_dba_collect_database_info
  WHERE data_date >= DATE_SUB(NOW(), INTERVAL 30 DAY)
  GROUP BY instance, database_name
) latest
JOIN luckyus_db_collection.t_dba_collect_database_info t1
  ON t1.instance = latest.instance
  AND t1.database_name = latest.database_name
  AND t1.data_date = latest.max_date
JOIN luckyus_db_collection.t_dba_collect_database_info t2
  ON t2.instance = t1.instance
  AND t2.database_name = t1.database_name
  AND t2.data_date = DATE_SUB(latest.max_date, INTERVAL 30 DAY)
WHERE t2.data_length > 0
ORDER BY growth_rate_percent DESC
LIMIT 10
```

**关键点**:
- 只考虑 30 天内的数据
- 使用两个时间点（当前 vs 30天前）计算增长
- 过滤掉 30 天前大小为 0 的数据（避免除零错误）
- 按增长率降序排序

#### 剩余空间计算查询
```sql
SELECT
  r.instance_id as instance,
  d.database_name,
  r.allocated_storage,
  r.max_allocated_storage,
  (r.max_allocated_storage - r.allocated_storage) as remaining_storage_gb,
  ROUND((r.max_allocated_storage - r.allocated_storage) / r.max_allocated_storage * 100, 2) as remaining_percent
FROM (
  SELECT instance_id, MAX(data_date) as max_date
  FROM luckyus_db_collection.t_dba_collect_rds_instances
  GROUP BY instance_id
) latest_rds
JOIN luckyus_db_collection.t_dba_collect_rds_instances r
  ON r.instance_id = latest_rds.instance_id
  AND r.data_date = latest_rds.max_date
LEFT JOIN (
  SELECT instance, database_name, MAX(data_date) as max_date
  FROM luckyus_db_collection.t_dba_collect_database_info
  GROUP BY instance, database_name
) latest_db
  ON latest_db.instance = r.instance_id
LEFT JOIN luckyus_db_collection.t_dba_collect_database_info d
  ON d.instance = latest_db.instance
  AND d.database_name = latest_db.database_name
  AND d.data_date = latest_db.max_date
WHERE r.max_allocated_storage > 0
ORDER BY remaining_storage_gb ASC
LIMIT 10
```

**关键点**:
- 从 `t_dba_collect_rds_instances` 表获取存储信息
- 使用 LEFT JOIN 关联数据库名称（可能某些实例没有对应的数据库记录）
- 计算剩余空间和百分比
- 按剩余空间升序排序（最少的在前）
- 过滤掉 max_allocated_storage = 0 的记录

---

## 导入步骤

### 方法 1: 覆盖现有 Dashboard（推荐）

1. **导入新版本**
   - Grafana 左侧菜单 → `+` → `Import dashboard`
   - Upload JSON file → 选择 `database_monitoring_OPTIMIZED.json`
   - 由于 `overwrite: true`，会自动覆盖同名 dashboard
   - 点击 `Import`

2. **选择实例**
   - Dashboard 顶部会显示 **Instance** 下拉框
   - 选择一个实例（例如：`aws-luckyus-icyberdata-rw`）
   - Panel 1 和 Panel 4 会自动过滤显示该实例的数据
   - Panel 2 和 Panel 3 显示全局数据，不受变量影响

### 方法 2: 删除后重新导入

1. **删除旧 Dashboard**
   - 进入 Dashboard (UID: A6m2sGIDk)
   - Settings (右上角) → Delete dashboard

2. **导入新版本**
   - 同方法 1

---

## 使用说明

### Instance 变量

- **类型**: 单选下拉框
- **功能**: 选择要查看的数据库实例
- **影响范围**:
  - Panel 1: 数据库大小变化趋势 ✅
  - Panel 2: 增长最快的实例 ❌（全局数据）
  - Panel 3: 剩余空间最少的实例 ❌（全局数据）
  - Panel 4: 详细数据表格 ✅

### 典型使用场景

#### 场景 1: 查看某个实例的详细趋势
1. 从 Instance 下拉框选择实例
2. 查看 Panel 1（趋势图）和 Panel 4（详细数据）
3. 了解该实例数据库大小的历史变化

#### 场景 2: 识别快速增长的数据库
1. 查看 Panel 2（增长最快的实例）
2. 找出增长率最高的数据库
3. 从 Instance 下拉框选择对应实例
4. 在 Panel 1 查看详细趋势，确认是否需要扩容

#### 场景 3: 监控存储空间告警
1. 查看 Panel 3（剩余空间最少的实例）
2. 关注红色标记的实例（剩余 < 20%）
3. 从 Instance 下拉框选择对应实例
4. 在 Panel 1 查看增长趋势，评估扩容时间

---

## 技术细节

### 数据表依赖

1. **luckyus_db_collection.t_dba_collect_database_info**
   - 字段: instance, database_name, data_date, data_length
   - 用途: 数据库大小历史数据

2. **luckyus_db_collection.t_dba_collect_rds_instances**
   - 字段: instance_id, data_date, allocated_storage, max_allocated_storage
   - 用途: RDS 实例存储容量信息

### 单位说明

- **数据库大小**: decbytes (十进制字节) - 1 KB = 1000 bytes
- **存储空间**: deckbytes (十进制千字节) - 用于显示 GB 级别的存储
- **增长率**: percent (百分比)

### 性能考虑

- Panel 2 的 30 天增长计算可能较慢（需要 JOIN 两次）
- Panel 3 的 RDS 存储查询相对较快
- 建议设置适当的 refresh 间隔（如 5 分钟）

---

## 文件清单

- ✅ **database_monitoring_OPTIMIZED.json** - 优化后的版本（推荐使用）
- database_monitoring_FINAL_FIX.json - 之前的版本
- database_monitoring_WORKING.json - 工作中的版本
- database_monitoring_ULTRA_SIMPLE.json - 超简化版本

---

## 常见问题

### Q1: 为什么 Panel 2 和 Panel 3 不受 Instance 变量影响？

A: 根据需求，这两个面板需要显示**所有实例**的全局数据，以便：
- 识别哪些实例增长最快（可能需要关注）
- 识别哪些实例空间不足（可能需要扩容）

如果这些数据也受变量过滤，就无法看到全局情况。

### Q2: 如果 Panel 2 显示的增长率为负数怎么办？

A: 负数表示数据库大小在减少。可能原因：
- 数据清理/归档
- 表被删除
- 数据迁移

这是正常情况，按降序排序时负增长会排在最后。

### Q3: Panel 3 中某些实例的 database_name 为空？

A: 可能原因：
- RDS 实例存在，但 `t_dba_collect_database_info` 表中没有对应记录
- 使用了 LEFT JOIN，允许 database_name 为 NULL
- 建议检查数据采集程序是否正常运行

### Q4: 如何调整 Top 10 的数量？

A: 修改 SQL 查询中的 `LIMIT 10` 为其他数值，例如 `LIMIT 20`。

---

## 后续优化建议

1. **添加告警**
   - 对剩余空间 < 20% 的实例设置告警
   - 对增长率 > 某阈值的数据库设置告警

2. **趋势预测**
   - 基于 30 天增长率，预测何时需要扩容
   - 添加预测曲线到 Panel 1

3. **自动化响应**
   - 集成 Grafana Alerting
   - 触发自动扩容流程

4. **历史对比**
   - 添加月度/季度增长对比
   - 显示同比/环比数据
