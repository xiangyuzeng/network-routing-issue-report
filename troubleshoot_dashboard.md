# Dashboard 空白问题排查

## 当前状态
✅ Dashboard 已成功导入
- 名称：数据库大小监控
- UID: hz00bGIvk
- URL: `/grafana/d/hz00bGIvk/`

❌ 但是显示空白，没有数据

---

## 排查步骤

### 步骤 1：检查 Instance 变量（最常见原因）

**操作：**
1. 打开 dashboard：`/grafana/d/hz00bGIvk/`
2. 查看页面**顶部**是否有 `Instance` 下拉选择框
3. 检查下拉框状态：

**可能的情况：**

#### 情况 A：下拉框显示 "No data" 或为空
**原因：** 变量查询没有返回数据
**解决：**
- 点击 Dashboard 设置（右上角齿轮图标）
- 进入 `Variables`
- 点击 `Instance_name` 变量
- 查看 `Preview of values` 是否有数据
- 如果没有，手动运行查询：
```sql
SELECT DISTINCT instance
FROM luckyus_db_collection.t_dba_collect_database_info
ORDER BY instance
```

#### 情况 B：下拉框有值，但没选中
**原因：** 变量有值但未自动选择
**解决：**
- 手动在下拉框中选择一个实例（如：`aws-luckyus-icyberdata-rw`）
- 页面应该立即刷新并显示数据

#### 情况 C：下拉框有值且已选中，但仍无数据
**原因：** 可能是时间范围或数据格式问题
**继续下一步排查**

---

### 步骤 2：使用 Explore 验证数据

**操作：**
1. 点击左侧菜单 `Explore`（或放大镜图标）
2. 选择数据源：`MySQL-Ldas`
3. 切换到 `Code` 模式
4. 运行以下查询：

#### 查询 1：检查是否有数据
```sql
SELECT COUNT(*) as total_records
FROM luckyus_db_collection.t_dba_collect_database_info
```

**预期结果：** 应该返回一个数字（如：1000）

#### 查询 2：检查实例列表
```sql
SELECT DISTINCT instance
FROM luckyus_db_collection.t_dba_collect_database_info
LIMIT 10
```

**预期结果：** 应该返回实例名称列表

#### 查询 3：检查数据时间范围
```sql
SELECT
  MIN(data_date) as earliest_date,
  MAX(data_date) as latest_date,
  COUNT(*) as total_records,
  COUNT(DISTINCT database_name) as db_count
FROM luckyus_db_collection.t_dba_collect_database_info
WHERE instance = 'aws-luckyus-icyberdata-rw'
```

**注意：** 将 `'aws-luckyus-icyberdata-rw'` 替换为实际的实例名

**预期结果：**
- earliest_date: 最早数据日期
- latest_date: 最新数据日期
- total_records: 记录总数
- db_count: 数据库数量

---

### 步骤 3：检查 Dashboard 时间范围

**操作：**
1. 返回 dashboard
2. 查看右上角的时间选择器
3. 当前设置是 `Last 30 days`

**根据步骤 2 的结果：**
- 如果 `latest_date` 在 30 天以内 → 时间范围正确
- 如果 `latest_date` 超过 30 天前 → 需要调整时间范围

**调整方法：**
- 点击时间选择器
- 选择 `Absolute time range`
- 设置从 `earliest_date` 到 `latest_date`
- 或者选择更大的相对范围（如：`Last 90 days`）

---

### 步骤 4：测试时间序列查询格式

在 Explore 中测试时间序列图的查询：

```sql
SELECT
  data_date as time,
  database_name as metric,
  data_length as value
FROM luckyus_db_collection.t_dba_collect_database_info
WHERE instance = 'aws-luckyus-icyberdata-rw'
  AND data_date >= DATE_SUB(NOW(), INTERVAL 30 DAY)
ORDER BY data_date
LIMIT 100
```

**重要设置：**
1. 确保 `Format` 选择为 `Time series`（不是 `Table`）
2. 查看是否返回数据
3. 查看数据格式是否正确（time, metric, value 三列）

**可能的问题：**
- 如果返回数据但格式不对 → 检查 `data_date` 字段类型
- 如果没有数据 → 检查 instance 名称和时间范围

---

### 步骤 5：逐个面板检查

如果以上都正常，逐个检查面板：

#### 面板 5（最底部的表格）应该最容易显示数据

1. 点击表格面板标题
2. 选择 `Edit`
3. 查看 Query Inspector
4. 运行查询看是否有结果

**如果表格有数据但时间序列图没有：**
- 问题在于时间序列格式
- 检查 `data_date` 字段类型（应该是 DATETIME 或 TIMESTAMP）

**如果表格也没有数据：**
- 检查 SQL 中的 `$Instance_name` 变量是否正确替换
- 在 Query Inspector 中查看实际执行的 SQL

---

## 快速诊断命令

在 Explore 中依次运行以下命令，并记录结果：

```sql
-- 1. 总记录数
SELECT COUNT(*) FROM luckyus_db_collection.t_dba_collect_database_info;

-- 2. 实例列表
SELECT DISTINCT instance FROM luckyus_db_collection.t_dba_collect_database_info;

-- 3. 数据时间范围
SELECT
  MIN(data_date) as min_date,
  MAX(data_date) as max_date
FROM luckyus_db_collection.t_dba_collect_database_info;

-- 4. 最新的 10 条记录
SELECT *
FROM luckyus_db_collection.t_dba_collect_database_info
ORDER BY data_date DESC
LIMIT 10;

-- 5. data_date 字段类型检查
DESCRIBE luckyus_db_collection.t_dba_collect_database_info;
```

**将结果发给我，我可以帮你进一步诊断！**

---

## 最可能的原因（按概率排序）

1. ⭐⭐⭐⭐⭐ **Instance 变量未选择或无值**
2. ⭐⭐⭐⭐ **时间范围不包含数据**
3. ⭐⭐⭐ **data_date 字段格式问题**
4. ⭐⭐ **Instance 名称不匹配**
5. ⭐ **数据表中确实没有数据**

---

## 下一步

请按照以上步骤操作，并告诉我：
1. Instance 下拉框的状态（有值？选中了吗？）
2. 快速诊断命令的结果
3. 任何错误信息或异常

我会根据你的反馈进一步帮你解决！
