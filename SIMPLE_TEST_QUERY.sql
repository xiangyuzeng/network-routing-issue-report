-- 最简单的测试查询
-- 请在 Grafana Explore 中运行以下查询来诊断问题

-- ========================================
-- 步骤 1: 测试数据源连接
-- ========================================
SELECT 1 as test;
-- 预期结果: 返回一行，值为 1
-- 如果这个都失败，说明数据源连接有问题

-- ========================================
-- 步骤 2: 测试表是否存在
-- ========================================
SHOW TABLES FROM luckyus_db_collection;
-- 预期结果: 应该看到 t_dba_collect_database_info 表

-- ========================================
-- 步骤 3: 测试表结构
-- ========================================
DESCRIBE luckyus_db_collection.t_dba_collect_database_info;
-- 预期结果: 显示表的字段列表（database_name, data_date, data_length, instance 等）

-- ========================================
-- 步骤 4: 测试是否有数据
-- ========================================
SELECT COUNT(*) as total_records
FROM luckyus_db_collection.t_dba_collect_database_info;
-- 预期结果: 返回记录总数
-- 如果是 0，说明表是空的

-- ========================================
-- 步骤 5: 查看最近的数据
-- ========================================
SELECT *
FROM luckyus_db_collection.t_dba_collect_database_info
ORDER BY data_date DESC
LIMIT 5;
-- 预期结果: 显示最近的 5 条记录
-- 查看 data_date 的格式和值

-- ========================================
-- 步骤 6: 查看数据时间范围
-- ========================================
SELECT
  MIN(data_date) as earliest_date,
  MAX(data_date) as latest_date,
  COUNT(*) as record_count,
  COUNT(DISTINCT instance) as instance_count,
  COUNT(DISTINCT database_name) as database_count
FROM luckyus_db_collection.t_dba_collect_database_info;
-- 预期结果: 显示数据的时间范围和统计信息

-- ========================================
-- 步骤 7: 测试时间序列格式（TABLE 格式）
-- ========================================
SELECT
  data_date,
  database_name,
  data_length
FROM luckyus_db_collection.t_dba_collect_database_info
ORDER BY data_date DESC
LIMIT 10;
-- 在 Grafana Explore 中：
-- 1. Format 选择: Table
-- 2. 应该能看到数据

-- ========================================
-- 步骤 8: 测试时间序列格式（TIME SERIES 格式）
-- ========================================
SELECT
  data_date as time,
  database_name as metric,
  data_length as value
FROM luckyus_db_collection.t_dba_collect_database_info
ORDER BY data_date DESC
LIMIT 10;
-- 在 Grafana Explore 中：
-- 1. Format 选择: Time series
-- 2. 应该能看到图表

-- ========================================
-- 诊断说明
-- ========================================
-- 请按顺序运行以上查询，并记录每一步的结果
-- 如果某一步失败，就停在那里，告诉我具体的错误信息
