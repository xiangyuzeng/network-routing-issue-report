-- 测试查询：检查数据表中的数据情况

-- 1. 查看有哪些实例
SELECT DISTINCT instance
FROM luckyus_db_collection.t_dba_collect_database_info
LIMIT 10;

-- 2. 查看数据的时间范围
SELECT
  MIN(data_date) as earliest_date,
  MAX(data_date) as latest_date,
  COUNT(*) as total_records
FROM luckyus_db_collection.t_dba_collect_database_info;

-- 3. 查看最近的数据（用于时间序列图）
SELECT
  database_name,
  data_date,
  data_length
FROM luckyus_db_collection.t_dba_collect_database_info
WHERE instance = 'aws-luckyus-icyberdata-rw'
ORDER BY data_date DESC
LIMIT 20;

-- 4. 测试时间序列查询格式
SELECT
  UNIX_TIMESTAMP(data_date) as time_sec,
  data_length as value,
  database_name as metric
FROM luckyus_db_collection.t_dba_collect_database_info
WHERE instance = 'aws-luckyus-icyberdata-rw'
ORDER BY data_date
LIMIT 10;
