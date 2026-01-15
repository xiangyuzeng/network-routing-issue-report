# Grafana Dashboard 导入指南

## 问题诊断

当前遇到的问题：导入 dashboard JSON 后显示空白，看不到任何数据。

可能的原因：
1. ✅ 数据源连接正常（MySQL-Ldas，UID: LJ7ObqYNk）
2. ❓ 导入时未正确覆盖原有配置
3. ❓ 时间范围设置问题
4. ❓ 变量选择问题

## 方案 A：导入新的 Dashboard（推荐）

使用文件：`database_size_monitoring_NEW.json`

### 导入步骤

1. 登录 Grafana UI
2. 点击左侧菜单 `+` → `Import`
3. 选择 `Upload JSON file`
4. 上传文件 `database_size_monitoring_NEW.json`
5. 选择文件夹：`DBA-US`
6. 点击 `Import`

### 优点
- 不会覆盖原有 dashboard
- 可以同时对比新旧版本
- 更安全，可以先测试

---

## 方案 B：覆盖原有 Dashboard

使用文件：`database_size_monitoring_dashboard_v2.json`

### 导入步骤

1. 登录 Grafana UI
2. 点击左侧菜单 `+` → `Import`
3. 选择 `Upload JSON file`
4. 上传文件 `database_size_monitoring_dashboard_v2.json`
5. **重要**：在导入界面，找到 `Options` 部分
6. **勾选** `Import with the same UID` 或类似选项
7. 选择文件夹：`DBA-US`
8. 点击 `Import`

### 如果仍然不成功

可能需要先删除旧的 dashboard：
1. 打开旧的 dashboard (`/grafana/d/2WiWiMIvk/new-dashboard`)
2. 点击右上角设置图标（⚙️）
3. 选择 `Settings`
4. 滑到底部，点击 `Delete Dashboard`
5. 然后再按上述步骤导入

---

## 导入后检查清单

### 1. 检查变量是否正确加载
- 页面顶部应该显示 `Instance` 下拉选择框
- 下拉框应该有值（如：`aws-luckyus-icyberdata-rw`）
- 如果没有值，刷新页面

### 2. 检查时间范围
- 确保右上角时间范围设置为 `Last 30 days` 或包含数据的时间段
- 如果数据只在特定日期，需要手动调整时间范围

### 3. 检查每个面板
逐个检查以下面板是否显示数据：

#### 面板 1：数据库大小变化趋势（时间序列图）
- SQL: `SELECT data_date as time, database_name as metric, data_length as value...`
- 如果空白，点击面板标题 → `Edit` → `Query Inspector` → `Refresh` 查看错误

#### 面板 2-4：统计面板和饼图
- 应该显示数值
- 如果显示 "No data"，检查是否选择了正确的 Instance

#### 面板 5：详细数据表格
- 这个应该最容易显示数据
- 如果这个也没数据，说明 SQL 查询有问题或没有数据

---

## 手动排查步骤

如果导入后仍然空白，请按以下步骤排查：

### 步骤 1：检查数据是否存在

1. 打开任意一个面板
2. 点击面板标题 → `Explore`
3. 在 Query 中输入：
```sql
SELECT *
FROM luckyus_db_collection.t_dba_collect_database_info
LIMIT 10
```
4. 点击 `Run query`
5. 如果有数据显示，说明数据源正常

### 步骤 2：检查 Instance 变量

1. 在 Explore 中运行：
```sql
SELECT DISTINCT instance
FROM luckyus_db_collection.t_dba_collect_database_info
```
2. 确认返回的实例名称
3. 返回 dashboard，确保顶部 Instance 下拉框选择了正确的值

### 步骤 3：检查时间范围

1. 在 Explore 中运行：
```sql
SELECT
  MIN(data_date) as earliest_date,
  MAX(data_date) as latest_date
FROM luckyus_db_collection.t_dba_collect_database_info
```
2. 查看数据的实际时间范围
3. 调整 dashboard 右上角的时间选择器，确保包含这个范围

### 步骤 4：测试时间序列查询

在 Explore 中，切换到 `Code` 模式，运行：
```sql
SELECT
  data_date as time,
  database_name as metric,
  data_length as value
FROM luckyus_db_collection.t_dba_collect_database_info
WHERE instance = 'aws-luckyus-icyberdata-rw'
  AND data_date >= DATE_SUB(NOW(), INTERVAL 30 DAY)
ORDER BY data_date
```

确保：
- Format 选择为 `Time series`
- 有数据返回

---

## 常见问题

### Q: 导入后 dashboard 标题还是 "New dashboard"
**A:** 说明导入没有覆盖，使用方案 A 创建新的 dashboard

### Q: 所有面板都显示 "No data"
**A:**
1. 检查 Instance 变量是否选择
2. 检查时间范围是否包含数据
3. 使用 Explore 验证 SQL 查询

### Q: 时间序列图显示空白，但表格有数据
**A:**
1. 编辑时间序列面板
2. 检查 Format 是否设置为 `Time series`
3. 检查 `data_date` 字段格式是否正确

### Q: 有权限错误
**A:**
1. 确保你有 `dashboards:write` 权限
2. 或联系管理员帮助导入

---

## 需要帮助？

如果以上步骤都无法解决问题，请提供以下信息：
1. 截图显示空白的 dashboard
2. 在 Explore 中运行基础查询的结果截图
3. Instance 变量的值
4. 时间范围设置
5. Browser Console 中的任何错误信息（F12 打开开发者工具）
