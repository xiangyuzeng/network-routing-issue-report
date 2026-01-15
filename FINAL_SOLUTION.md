# Dashboard 导入问题 - 最终解决方案

## 问题分析

经过多次测试发现，导入的 JSON 文件中的 `panels` 数组没有被 Grafana 正确解析。可能的原因：
1. JSON 结构过于复杂
2. 某些配置字段与 Grafana 版本不兼容
3. 导入过程中的解析问题

## 最终方案：使用超简化版本

已创建：`database_monitoring_ULTRA_SIMPLE.json`

### 特点
- ✅ 移除所有复杂配置，只保留最基本字段
- ✅ 4 个核心 panels：
  1. 时间序列图 - 数据库大小趋势
  2. 统计卡片 - 当前总大小
  3. 统计卡片 - 数据库总数
  4. 表格 - 详细数据（最近500条）
- ✅ 无变量依赖，直接显示所有实例
- ✅ 时间范围：Last 90 days（覆盖你的数据：2025-10-09）

### 导入步骤

1. **清理旧 dashboard**
   ```
   删除 UID: Itp3aMIvk 的 dashboard
   ```

2. **导入新文件**
   - Grafana 左侧菜单 → `+` → `Import dashboard`
   - Upload JSON file
   - 选择：`database_monitoring_ULTRA_SIMPLE.json`
   - 点击 `Import`

3. **验证**
   - 应该能看到 4 个 panels
   - 时间序列图应该显示多条线（每个数据库一条）
   - 统计卡片显示数值
   - 表格显示详细数据

## 如果还是空白

### 方法 1：直接复制 JSON 内容
1. 打开 `database_monitoring_ULTRA_SIMPLE.json`
2. 复制全部内容
3. Grafana → Import dashboard → `Import via panel json`
4. 粘贴 JSON
5. 点击 `Load` → `Import`

### 方法 2：手动创建 dashboard
如果导入仍然失败，可以手动创建：

1. **创建新 dashboard**
   - Grafana → `+` → `Dashboard`

2. **添加第一个 panel（时间序列图）**
   - Add panel → Add visualization
   - Data source：选择 `MySQL-Ldas`
   - 切换到 `Code` 模式
   - 输入 SQL：
   ```sql
   SELECT
     data_date as time,
     CONCAT(database_name, ' (', instance, ')') as metric,
     data_length as value
   FROM luckyus_db_collection.t_dba_collect_database_info
   WHERE data_date >= DATE_SUB(NOW(), INTERVAL 90 DAY)
   ORDER BY data_date
   ```
   - Format: `Time series`
   - Panel options → Title: `数据库大小趋势`
   - Unit: `Data (IEC) / bytes(IEC)`
   - Apply

3. **添加统计卡片 - 当前总大小**
   - Add panel → Add visualization
   - Visualization: `Stat`
   - Data source: `MySQL-Ldas`
   - SQL:
   ```sql
   SELECT SUM(data_length) as value
   FROM (
     SELECT database_name, instance, MAX(data_date) as max_date
     FROM luckyus_db_collection.t_dba_collect_database_info
     GROUP BY database_name, instance
   ) latest
   JOIN luckyus_db_collection.t_dba_collect_database_info t
     ON t.database_name = latest.database_name
     AND t.instance = latest.instance
     AND t.data_date = latest.max_date
   ```
   - Format: `Table`
   - Unit: `Data (IEC) / bytes(IEC)`
   - Apply

4. **添加统计卡片 - 数据库总数**
   - Add panel → Add visualization
   - Visualization: `Stat`
   - SQL:
   ```sql
   SELECT COUNT(DISTINCT CONCAT(instance, '-', database_name)) as value
   FROM luckyus_db_collection.t_dba_collect_database_info
   ```
   - Format: `Table`
   - Unit: `Short`
   - Apply

5. **添加表格**
   - Add panel → Add visualization
   - Visualization: `Table`
   - SQL:
   ```sql
   SELECT
     instance,
     database_name,
     data_date,
     data_length
   FROM luckyus_db_collection.t_dba_collect_database_info
   ORDER BY data_date DESC, data_length DESC
   LIMIT 500
   ```
   - Format: `Table`
   - Field overrides → data_length → Unit: `Data (IEC) / bytes(IEC)`
   - Apply

6. **保存 dashboard**
   - 点击右上角 Save
   - Title: `数据库大小监控`
   - Folder: `DBA-US`
   - Save

## 调试信息收集

如果以上所有方法都失败，请提供：

1. **Grafana 版本**
   - 左下角用户菜单 → Help → About Grafana
   - 复制 Version 信息

2. **导入时的错误信息**
   - 浏览器 Console (F12) 中的错误
   - Grafana 页面上显示的任何错误提示

3. **现有的 dashboard JSON**
   - 导入后，进入 dashboard
   - Settings (右上角齿轮) → JSON Model
   - 复制完整的 JSON（尤其是 panels 部分）

这样我可以进一步诊断问题。

## 文件列表

- ✅ **database_monitoring_ULTRA_SIMPLE.json** - 推荐使用（超简化版）
- database_monitoring_CORRECTED.json - 修正了双重嵌套
- database_monitoring_FIXED.json - 包含变量配置
- database_monitoring_NO_VARIABLE.json - 无变量版本
- database_monitoring_MINIMAL.json - 最小测试版

所有文件已提交到 GitHub。
