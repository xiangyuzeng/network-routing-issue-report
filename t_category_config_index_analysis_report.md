# t_category_config 表索引分析报告

**数据库**: luckyus_opshop
**表名**: t_category_config
**分析日期**: 2026-01-26
**分析人**: DBA Team

---

## 一、表基本信息

| 属性 | 值 |
|-----|-----|
| 数据库 | luckyus_opshop |
| 表名 | t_category_config |
| 表注释 | 配置类别 |
| 存储引擎 | InnoDB |
| 字符集 | utf8mb4 |
| 总行数 | 1,818 行 |

### 表结构

```sql
CREATE TABLE `t_category_config` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT COMMENT '主键id',
  `tenant` varchar(4) NOT NULL COMMENT '租户',
  `name` varchar(200) NOT NULL COMMENT '配置项名称',
  `code` varchar(100) NOT NULL COMMENT '配置项编码',
  `parent_code` varchar(100) DEFAULT NULL COMMENT '父类编码',
  `sort` int NOT NULL COMMENT '排序',
  `tag` varchar(100) DEFAULT NULL COMMENT '标签编码',
  `type` int NOT NULL COMMENT '配置类型',
  `show` tinyint DEFAULT '1' COMMENT '是否显示 0：否，1：是',
  `status` tinyint DEFAULT '0' COMMENT '是否有效 0：无效，1：有效',
  `create_by` bigint DEFAULT NULL COMMENT '创建人ID',
  `creator_name` varchar(64) DEFAULT NULL COMMENT '创建人名称',
  `create_time` datetime DEFAULT NULL COMMENT '创建时间',
  `modify_by` bigint DEFAULT NULL COMMENT '修改人ID',
  `modifier_name` varchar(64) DEFAULT NULL COMMENT '修改人名称',
  `modify_time` datetime DEFAULT NULL COMMENT '修改时间',
  `modifier_dept_id` bigint DEFAULT NULL COMMENT '修改人部门id',
  `display_style` varchar(100) DEFAULT '0' COMMENT '展示风格 0:无，1:突出展示',
  PRIMARY KEY (`id`),
  UNIQUE KEY `uniq_code_tenant` (`code`,`tenant`),
  KEY `idx_parent_code` (`parent_code`) USING BTREE,
  KEY `idx_tenant_sort` (`tenant`,`sort`) USING BTREE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci COMMENT='配置类别'
```

---

## 二、现有索引分析

### 2.1 索引概览

| 索引名称 | 索引类型 | 唯一性 | 包含列 | 基数(Cardinality) |
|---------|---------|-------|-------|------------------|
| PRIMARY | BTREE | 唯一 | id | 1,707 |
| uniq_code_tenant | BTREE | 唯一 | (code, tenant) | 268 → 1,707 |
| idx_parent_code | BTREE | 非唯一 | parent_code | 28 |
| idx_tenant_sort | BTREE | 非唯一 | (tenant, sort) | 7 → 247 |

### 2.2 索引详细说明

#### PRIMARY (主键索引)
- **列**: id (bigint unsigned, AUTO_INCREMENT)
- **用途**: 主键唯一标识，支持按 ID 的点查和更新
- **评估**: ✅ 标准设计，无问题

#### uniq_code_tenant (唯一联合索引)
- **列**: (code, tenant)
- **用途**: 保证同一租户下配置项编码唯一
- **选择性**: code 基数 268，联合后 1,707，选择性良好
- **支持查询**:
  - `WHERE code = ?`
  - `WHERE code = ? AND tenant = ?`
- **评估**: ✅ 设计合理

#### idx_parent_code (普通索引)
- **列**: parent_code
- **用途**: 支持按父类编码查询子配置
- **选择性**: 28/1,818 ≈ 1.5%，选择性较低
- **评估**: ⚠️ 可考虑扩展为联合索引

#### idx_tenant_sort (联合索引)
- **列**: (tenant, sort)
- **用途**: 支持按租户筛选并按排序字段排序
- **选择性**: tenant 基数仅 7（7个租户）
- **评估**: ✅ 适合 `WHERE tenant = ? ORDER BY sort` 查询

---

## 三、索引使用统计

### 3.1 索引读写统计

| 索引名称 | 查询读取行数 | 更新行数 | 删除行数 | 使用热度 |
|---------|------------|---------|---------|---------|
| idx_tenant_sort | 7,194,946 | 0 | 0 | 🔥 最热 |
| uniq_code_tenant | 8,112 | 0 | 0 | 正常 |
| PRIMARY | 7,527 | 7,525 | 0 | 正常 |
| idx_parent_code | 2,752 | 34 | 0 | 较少 |

### 3.2 索引利用率评估

- **总体利用率**: 100%（所有 4 个索引均有使用）
- **未使用索引**: 无
- **冗余索引**: 无

---

## 四、查询模式分析

### 4.1 Top 查询统计

| 排名 | 查询模式 | 执行次数 | 扫描行数 | 返回行数 | 平均延迟 | 效率评估 |
|-----|---------|---------|---------|---------|---------|---------|
| 1 | WHERE status=? AND type=? AND tenant=? ORDER BY sort | 26,338 | 7,184,374 | 1,672,492 | 1.34ms | ⚠️ 待优化 |
| 2 | WHERE code=? AND tenant=? | 8,091 | 7,512 | 7,512 | 0.32ms | ✅ 高效 |
| 3 | UPDATE ... WHERE id=? AND tenant=? | 7,527 | 7,527 | - | 7.4ms | ✅ 正常 |
| 4 | WHERE type=? AND parent_code=? AND tenant=? (MAX) | 45 | 1,139 | 45 | 0.43ms | ⚠️ 可优化 |
| 5 | WHERE type=? AND tenant=? ORDER BY sort | 22 | 5,976 | 304 | 1.18ms | ⚠️ 待优化 |

### 4.2 重点查询详细分析

#### Query 1: 最热查询（问题查询）

```sql
SELECT id, tenant, code, name, sort, show, display_style, status,
       parent_code, type, tag, modifier_dept_id, create_by, creator_name,
       create_time, modify_by, modifier_name, modify_time
FROM t_category_config
WHERE (status = ? AND type = ?) AND tenant = ?
ORDER BY sort ASC
```

| 指标 | 值 | 说明 |
|-----|-----|-----|
| 执行次数 | 26,338 | 最频繁的查询 |
| 总扫描行数 | 7,184,374 | 扫描量大 |
| 总返回行数 | 1,672,492 | - |
| 扫描/返回比 | 4.3:1 | ⚠️ 效率不理想 |
| 首次执行 | 2025-10-24 | - |
| 最近执行 | 2026-01-26 | 持续活跃 |

**问题分析**:
- 当前使用 `idx_tenant_sort (tenant, sort)` 索引
- WHERE 条件包含 `status` 和 `type`，但这两列不在索引中
- 导致索引无法完全覆盖过滤条件，需要大量回表过滤

#### Query 2: 高效查询

```sql
SELECT ... FROM t_category_config
WHERE (code = ?) AND tenant = ?
```

| 指标 | 值 |
|-----|-----|
| 扫描/返回比 | 1:1 ✅ |
| 使用索引 | uniq_code_tenant |

**评估**: 完美使用唯一索引，无需优化

---

## 五、优化建议

### 5.1 高优先级：新增复合索引

**问题**: 最热查询扫描效率低（扫描/返回比 4.3:1）

**建议**:
```sql
ALTER TABLE t_category_config
ADD INDEX idx_tenant_type_status_sort (tenant, type, status, sort);
```

**预期收益**:
- 最热查询扫描行数减少约 77%
- 查询延迟预计降低 50%+
- 索引大小增加约 50KB（可忽略）

**风险评估**:
- 表数据量小（1,818行），新增索引维护成本极低
- 写入操作少（主要是 UPDATE），影响可忽略

### 5.2 中优先级：优化 parent_code 索引

**问题**: `idx_parent_code` 单列索引选择性低

**建议**:
```sql
-- 如果存在较多 parent_code + tenant 的联合查询场景
ALTER TABLE t_category_config
DROP INDEX idx_parent_code,
ADD INDEX idx_parent_code_tenant_type (parent_code, tenant, type, sort);
```

**适用场景**: MAX(sort) 查询和按父类编码查询子配置

### 5.3 暂不建议

- **删除现有索引**: 所有索引均有使用，不建议删除
- **分区表**: 数据量太小，无需分区

---

## 六、索引覆盖情况汇总

| 查询模式 | 当前索引 | 覆盖情况 | 优化后 |
|---------|---------|---------|-------|
| WHERE id = ? | PRIMARY | ✅ 完全覆盖 | - |
| WHERE code = ? AND tenant = ? | uniq_code_tenant | ✅ 完全覆盖 | - |
| WHERE code = ? | uniq_code_tenant | ✅ 前缀覆盖 | - |
| WHERE tenant = ? ORDER BY sort | idx_tenant_sort | ✅ 完全覆盖 | - |
| WHERE status = ? AND type = ? AND tenant = ? ORDER BY sort | idx_tenant_sort | ⚠️ 部分覆盖 | ✅ 新索引覆盖 |
| WHERE parent_code = ? | idx_parent_code | ✅ 完全覆盖 | - |
| WHERE parent_code = ? AND tenant = ? | idx_parent_code | ⚠️ 部分覆盖 | ✅ 新索引覆盖 |

---

## 七、执行计划

### 阶段一（立即执行）
1. 添加 `idx_tenant_type_status_sort` 索引
2. 监控最热查询性能变化

### 阶段二（观察后决定）
1. 根据业务查询模式评估是否优化 `idx_parent_code`
2. 持续监控索引使用情况

---

## 八、总结

| 评估维度 | 当前状态 | 建议 |
|---------|---------|-----|
| 索引数量 | 4 个 | 建议增加 1 个 |
| 索引利用率 | 100% | 保持 |
| 冗余索引 | 无 | 保持 |
| 最热查询效率 | 扫描/返回比 4.3:1 | 需优化 |
| 写入影响 | 低 | 可接受新增索引 |

**核心结论**: 建议添加 `idx_tenant_type_status_sort (tenant, type, status, sort)` 复合索引，预计可显著提升最热查询性能，且由于表数据量小，维护成本极低。

---

## 九、索引变更影响分析：uniq_code_tenant 扩展为 (code, tenant, type)

### 9.1 变更说明

| 项目 | 当前 | 修改后 |
|-----|-----|-------|
| 索引名 | uniq_code_tenant | uniq_code_tenant_type |
| 索引列 | (code, tenant) | (code, tenant, type) |
| 唯一约束 | 同一租户下 code 唯一 | 同一租户+同一type下 code 唯一 |

### 9.2 数据兼容性检查

#### 唯一性分析

| 组合 | 去重数量 | 总行数 | 结论 |
|-----|---------|-------|-----|
| code | 284 | 1,818 | 有重复 |
| (code, tenant) | 1,818 | 1,818 | ✅ 完全唯一 |
| (code, tenant, type) | 1,818 | 1,818 | ✅ 完全唯一 |

**结论**:
- ✅ 当前数据中 **(code, tenant, type)** 组合完全唯一
- ✅ **不存在** code+tenant 相同但 type 不同的数据
- ✅ 修改索引**不会导致数据冲突**

#### type 字段分布

| type | 数量 | 占比 |
|-----|-----|-----|
| 2 | 1,642 | 90.3% |
| 1 | 148 | 8.1% |
| 10 | 28 | 1.5% |

#### 各租户数据情况

| 租户 | 记录数 | code数 | type种类 |
|-----|-------|-------|---------|
| LKUS | 273 | 273 | 3 |
| IQA2 | 270 | 270 | 3 |
| LKCN | 251 | 251 | 2 |
| IQA1 | 248 | 248 | 2 |
| LKMY | 243 | 243 | 2 |
| HKTD | 242 | 242 | 2 |
| LKSG | 240 | 240 | 2 |
| LKTW | 51 | 51 | 1 |

### 9.3 业务约束变化 ⚠️

| 场景 | 当前行为 | 修改后行为 |
|-----|---------|----------|
| 同租户插入相同 code | ❌ 拒绝 | ⚠️ **允许**（如果 type 不同） |
| 同租户同type插入相同code | ❌ 拒绝 | ❌ 拒绝 |

**业务影响示例**:
```
# 当前约束：租户 LKCN 下只能有一个 code='ABC' 的记录
# 修改后：租户 LKCN 下可以有多个 code='ABC'，只要 type 不同

# 示例：修改后以下数据可以共存
(code='ABC', tenant='LKCN', type=1)  -- 允许
(code='ABC', tenant='LKCN', type=2)  -- 允许（修改前会冲突）
```

### 9.4 查询影响分析

#### 受影响的查询

| 查询模式 | 执行次数 | 当前索引使用 | 修改后 |
|---------|---------|-------------|-------|
| `WHERE code=? AND tenant=?` | 8,091 | uniq_code_tenant (唯一查找) | ⚠️ 索引前缀扫描 |
| `WHERE code IN(...) AND tenant=?` | 8 | uniq_code_tenant | ⚠️ 索引前缀扫描 |

#### 查询效率变化

**修改前** (`WHERE code=? AND tenant=?`):
- 使用唯一索引，最多返回 1 行
- 执行计划: `const` 或 `eq_ref`

**修改后**:
- 使用普通索引前缀，可能返回多行（如果存在相同code+tenant不同type的数据）
- 执行计划: `ref`
- **当前数据下实际影响很小**（因为没有重复数据）

### 9.5 风险评估

| 风险项 | 级别 | 说明 |
|-------|-----|-----|
| 数据迁移风险 | 🟢 低 | 当前数据完全兼容，无冲突 |
| 查询性能风险 | 🟡 中 | code+tenant 查询从唯一查找变为索引扫描 |
| 业务逻辑风险 | 🔴 高 | **需确认应用是否依赖 code+tenant 唯一性** |
| 并发写入风险 | 🟡 中 | 唯一约束放宽，可能导致意外重复数据 |

### 9.6 变更建议

#### 修改前必须确认

1. **业务确认**: 是否真的需要允许同一 code 在不同 type 下存在？
2. **应用代码检查**: 是否有代码依赖 `code+tenant` 唯一性做查询或判断？
3. **并发场景**: INSERT 时是否用 `ON DUPLICATE KEY UPDATE` 依赖此唯一键？

#### 方案一：直接修改（如确认需要放宽约束）

```sql
-- 1. 删除旧索引
ALTER TABLE luckyus_opshop.t_category_config
DROP INDEX uniq_code_tenant;

-- 2. 创建新索引
ALTER TABLE luckyus_opshop.t_category_config
ADD UNIQUE INDEX uniq_code_tenant_type (code, tenant, type);
```

#### 方案二：保留原索引，新增索引（推荐）

如果业务同时需要两种约束，建议：

```sql
-- 保留原唯一约束
-- 新增包含 type 的普通索引（用于查询优化）
ALTER TABLE luckyus_opshop.t_category_config
ADD INDEX idx_code_tenant_type (code, tenant, type);
```

### 9.7 变更影响总结

| 评估维度 | 结论 |
|---------|-----|
| 数据兼容性 | ✅ 完全兼容，可安全执行 |
| 查询性能 | ⚠️ 轻微下降（code+tenant查询） |
| 业务风险 | ⚠️ **需确认是否允许同code不同type共存** |
| 建议 | 先与业务方确认约束变更的必要性 |

---

*报告生成时间: 2026-01-26*
*报告更新时间: 2026-01-26（新增索引变更影响分析）*
