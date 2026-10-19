---
name: frontend-permission-config
description: >-
  通用「前端页面/功能权限配置模块」生成范式。适用于 Vue3 + <script setup> + Tailwind
  的后台管理系统：基于一份声明式权限树（单一事实来源）自动派生权限数据矩阵、级联三态勾选、
  角色预设裁剪，并渲染可复用的权限配置弹窗。可直接移植到其他项目，只需替换权限树与操作字典。
version: 1.0.0
tags: [vue3, permission, rbac, 权限配置, 级联勾选, 角色管理]
---

# 前端页面权限配置模块 · 通用生成范式

> 本 skill 提炼自 SOC 安管平台 `front/src/pages/system/UserManagementPage.vue` 的「用户权限 /
> 角色管理」实现。它把"页面权限配置"的**生成原理**沉淀为一套可跨项目复用的模式，让你在任意
> Vue3 后台项目中，用最小改动产出一个结构一致、行为一致的权限配置模块。

## 1. 适用场景

- 后台系统需要"角色管理"：为角色勾选"模块 / 子模块 / 具体操作"的访问与操作权限。
- 需要三态（全选 / 半选 / 未选）级联勾选树。
- 需要内置角色预设（如超管、审计员、普通用户）。
- 希望权限 UI 与权限数据由**同一份声明式树**驱动，避免散落硬编码。

不适用：纯前端路由级菜单显隐（见第 7 节"路由派生变体"）。

## 2. 核心原理（五步生成链）

```
声明式权限树 ALL_PERMISSION_TREE  ──(生成器)──▶  PermissionMap 权限矩阵
        │                                          │
        └────(同一份树驱动 UI 渲染)────────────────┘
                    │
            三态级联勾选函数(isModuleIndeterminate…)
                    │
            角色预设 createRolePreset(白/黑名单裁剪)
                    │
            弹窗模板 v-for 渲染模块→子模块→操作
```

关键设计原则：

1. **单一事实来源（SSOT）**：`ALL_PERMISSION_TREE` 是唯一权威定义。新增模块/页面只改树，
   UI 与数据自动跟随，零散点修改。
2. **数据形态与展示形态解耦**：展示用分层树；存储用扁平布尔矩阵 `PermissionMap`
   （`{ 子模块id: { 操作key: boolean } }`），与层级无关，便于序列化、比对、落库。
3. **选中态是"派生"而非"冗余存储"**：父级（模块/子模块）的勾选/半选状态由子级聚合计算，
   **不**单独存字段，从根本上保证级联一致性。
4. **级联 setter 统一改树**：批量开关模块，调用 `setModulePermissions`，直接遍历树改写矩阵，
   不手写逐条逻辑。
5. **角色差异用 key 白/黑名单表达**：预设不逐条枚举，而是"开模块 + 过滤操作 key 集合"，
   扩展新角色低成本。

## 3. 数据模型（TypeScript）

```ts
// 操作：权限的最小单元（查看/新增/编辑/删除/导出…）
interface OperationDef { key: string; label: string }

// 子模块（对应一个页面或一组功能）
interface SubModuleDef {
  id: string            // 全局唯一，作为 PermissionMap 的一级 key
  name: string
  operations: OperationDef[]
}

// 模块（侧边栏一级，仅用于分组展示）
interface ModuleDef {
  id: string
  name: string
  icon?: any            // 可选：lucide / svg 组件
  subModules: SubModuleDef[]
}

// 权限矩阵：运行态与落库形态。子模块 id → 操作 key → 是否授权
type PermissionMap = Record<string, Record<string, boolean>>
```

## 4. 生成器函数（从树派生数据 + 三态判定）

> 把下面整段直接复制到 `<script setup>` 即可用。函数全部以 `ALL_PERMISSION_TREE` 为唯一输入。

```ts
/* ============ 1) 骨架生成：全 false / 全 true ============ */
const createEmptyPermissions = (): PermissionMap => {
  const map: PermissionMap = {}
  ALL_PERMISSION_TREE.forEach(mod => {
    mod.subModules.forEach(sub => {
      map[sub.id] = {}
      sub.operations.forEach(op => { map[sub.id][op.key] = false })
    })
  })
  return map
}
const createAllPermissions = (): PermissionMap => {
  const map = createEmptyPermissions()
  Object.values(map).forEach(ops => Object.keys(ops).forEach(k => (ops[k] = true)))
  return map
}

/* ============ 2) 级联 setter：按模块统一开关其下全部子模块+操作 ============ */
const setModulePermissions = (map: PermissionMap, moduleId: string, value: boolean) => {
  const mod = ALL_PERMISSION_TREE.find(m => m.id === moduleId)
  if (!mod) return
  mod.subModules.forEach(sub => {
    if (!map[sub.id]) map[sub.id] = {}
    sub.operations.forEach(op => { map[sub.id][op.key] = value })
  })
}

/* ============ 3) 三态判定：父级状态由子级聚合 ============ */
const isSubModuleAllChecked = (perms: PermissionMap, sub: SubModuleDef): boolean =>
  !!perms[sub.id] && sub.operations.every(op => perms[sub.id][op.key] === true)

const isSubModuleIndeterminate = (perms: PermissionMap, sub: SubModuleDef): boolean => {
  const sp = perms[sub.id]; if (!sp) return false
  const n = sub.operations.filter(op => sp[op.key]).length
  return n > 0 && n < sub.operations.length
}
const isModuleAllChecked = (perms: PermissionMap, mod: ModuleDef): boolean =>
  mod.subModules.every(sub => isSubModuleAllChecked(perms, sub))
const isModuleIndeterminate = (perms: PermissionMap, mod: ModuleDef): boolean => {
  const any = mod.subModules.some(sub => {
    const sp = perms[sub.id]; return sp && Object.values(sp).some(Boolean)
  })
  return any && !isModuleAllChecked(perms, mod)
}

/* ============ 4) 统计 / 展示辅助 ============ */
const countTotalPermissions = (perms: PermissionMap): number => {
  let n = 0
  Object.values(perms).forEach(ops => Object.values(ops).forEach(v => { if (v) n++ }))
  return n
}
const countActiveModules = (perms: PermissionMap): number => {
  let c = 0
  ALL_PERMISSION_TREE.forEach(mod => {
    const has = mod.subModules.some(sub => {
      const sp = perms[sub.id]; return sp && Object.values(sp).some(Boolean)
    })
    if (has) c++
  })
  return c
}
const getSubModuleName = (id: string): string => {
  for (const mod of ALL_PERMISSION_TREE) {
    const s = mod.subModules.find(x => x.id === id); if (s) return s.name
  }
  return id
}
```

> ⚠️ **关键陷阱**：原生 `<input type="checkbox">` 的 `indeterminate`（半选）**不是 HTML 属性**，
> 不能用 `:indeterminate` 以外的绑定直接由框架属性设置。Vue 中通过 `:indeterminate="fn(...)"`
> 绑定计算值即可（Vue 会把它当 DOM property 设置）；若用其他框架/原生 JS，必须用
> `el.indeterminate = bool` 显式赋值，单纯改 attribute 无效。

## 5. 角色预设（白/黑名单裁剪模板）

```ts
const createRolePreset = (preset: string): PermissionMap => {
  const perms = createEmptyPermissions()
  if (preset === 'super_admin') return createAllPermissions()

  if (preset === 'security_admin') {
    // 开整模块，再用白名单保留允许的"操作类型"
    ;['dashboard','assets','security','vulnerability','emergency'].forEach(m =>
      setModulePermissions(perms, m, true))
    const allow = ['view','export','config','scan','handle','ignore','fix','check',
                   'deploy','start','stop','execute','analyze','arbitrate','approve','assign']
    for (const sub of Object.keys(perms))
      for (const k of Object.keys(perms[sub]))
        if (!allow.includes(k)) perms[sub][k] = false
    return perms
  }

  if (preset === 'auditor') {
    // 只读：仅保留 view/export
    ALL_PERMISSION_TREE.forEach(mod => mod.subModules.forEach(sub =>
      sub.operations.forEach(op => { if (['view','export'].includes(op.key)) perms[sub.id][op.key] = true })))
    return perms
  }

  if (preset === 'user') {
    // 基础：仅 dashboard/assets 的 view
    ALL_PERMISSION_TREE.forEach(mod => mod.subModules.forEach(sub =>
      sub.operations.forEach(op => { if (op.key === 'view' && ['dashboard','assets'].includes(mod.id)) perms[sub.id][op.key] = true })))
    return perms
  }
  return perms
}
```

新增自定义角色时，`permissions` 用 `createEmptyPermissions()` 起手，由用户在弹窗内勾选；
克隆角色用 `JSON.parse(JSON.stringify(role.permissions))`。

## 6. UI 渲染模板（三态复选框树弹窗）

`<script setup>` 中的状态与交互函数：

```ts
const expandedModules = ref<Set<string>>(new Set(ALL_PERMISSION_TREE.map(m => m.id)))
const expandedSubModules = ref<Set<string>>(new Set())
const selectedRole = ref<{ permissions: PermissionMap } | null>(null)  // 来自角色列表
const isPermissionDisabled = ref(false)  // 如超级管理员不可编辑

const toggleModuleAll = (mod: ModuleDef, value: boolean) => {
  if (isPermissionDisabled.value) return
  setModulePermissions(selectedRole.value!.permissions, mod.id, value)
}
const toggleSubModuleAll = (sub: SubModuleDef, value: boolean) => {
  if (isPermissionDisabled.value) return
  const sp = selectedRole.value!.permissions[sub.id]
  if (sp) sub.operations.forEach(op => (sp[op.key] = value))
}
const toggleOperation = (subId: string, opKey: string) => {
  if (isPermissionDisabled.value) return
  const sp = selectedRole.value!.permissions[subId]
  if (sp) sp[opKey] = !sp[opKey]
}
```

模板核心（Tailwind，三层 v-for）：

```vue
<div class="flex-1 overflow-y-auto p-3 space-y-2">
  <div v-for="mod in ALL_PERMISSION_TREE" :key="mod.id">
    <div class="border border-gray-200 rounded-lg overflow-hidden">
      <!-- 模块头 + 模块级全选（三态） -->
      <div class="flex items-center justify-between px-3 py-2 bg-gray-50">
        <span class="font-medium text-gray-800 text-sm">{{ mod.name }}</span>
        <label class="flex items-center space-x-1 cursor-pointer">
          <input type="checkbox" class="w-3.5 h-3.5"
            :checked="isModuleAllChecked(selectedRole.permissions, mod)"
            :indeterminate="isModuleIndeterminate(selectedRole.permissions, mod)"
            :disabled="isPermissionDisabled"
            @change="toggleModuleAll(mod, isModuleAllChecked(selectedRole.permissions, mod) ? false : true)" />
          <span class="text-xs text-gray-600">全选</span>
        </label>
      </div>

      <!-- 子模块 + 子模块级全选（三态） -->
      <div class="divide-y divide-gray-100">
        <div v-for="sub in mod.subModules" :key="sub.id" class="px-3 py-1.5">
          <div class="flex items-center justify-between">
            <span class="text-sm text-gray-700">{{ sub.name }}</span>
            <label class="flex items-center space-x-1 cursor-pointer">
              <input type="checkbox" class="w-3 h-3"
                :checked="isSubModuleAllChecked(selectedRole.permissions, sub)"
                :indeterminate="isSubModuleIndeterminate(selectedRole.permissions, sub)"
                :disabled="isPermissionDisabled"
                @change="toggleSubModuleAll(sub, isSubModuleAllChecked(selectedRole.permissions, sub) ? false : true)" />
              <span class="text-xs text-gray-500">全选</span>
            </label>
          </div>

          <!-- 操作叶子 -->
          <div class="mt-1.5 pl-5 border-l-2 border-gray-100 ml-1">
            <label v-for="op in sub.operations" :key="op.key" class="flex items-center space-x-1 cursor-pointer">
              <input type="checkbox" class="w-3 h-3"
                :checked="selectedRole.permissions[sub.id]?.[op.key] ?? false"
                :disabled="isPermissionDisabled"
                @change="toggleOperation(sub.id, op.key)" />
              <span class="text-xs text-gray-600">{{ op.label }}</span>
            </label>
          </div>
        </div>
      </div>
    </div>
  </div>
</div>
```

搜索过滤（在树上做关键词匹配，模块/子模块/操作 label 任一命中即显示）：

```ts
const permSearchKeyword = ref('')
const isModuleVisible = (mod: ModuleDef): boolean => {
  if (!permSearchKeyword.value) return true
  const kw = permSearchKeyword.value.toLowerCase()
  if (mod.name.toLowerCase().includes(kw)) return true
  return mod.subModules.some(sub =>
    sub.name.toLowerCase().includes(kw) ||
    sub.operations.some(op => op.label.toLowerCase().includes(kw)))
}
```

## 7. 移植到其他项目的适配清单

1. **替换权限树**：把 `ALL_PERMISSION_TREE` 改为你项目的真实模块/子模块/操作。
   建议 `id` 用稳定英文短串（如 `asset_mgmt`、`strategy_list`），`operations` 用统一操作字典
   `view/add/edit/delete/export/import/...`，保持跨角色语义一致。
2. **接入真实账户体系**：`Role.permissions`、`userAccounts[].role` 改为后端返回；
   保存时把 `PermissionMap` 序列化提交（结构已是纯 JSON 可直传）。
3. **落库与比对**：`PermissionMap` 扁平结构天然适合 diff（如 `countTotalPermissions` 前后对比
   写操作日志）、深拷贝（`JSON.parse(JSON.stringify(...))`）、合并。
4. **权限生效（可选）**：本范式只管"配置"。实际页面/按钮级拦截建议另写
   `usePermission()` 组合式：在目标页面 `v-if="can(opKey)"` 或路由守卫里读当前角色
   的 `PermissionMap` 做判断，与配置模块解耦。
5. **路由派生变体（页面级菜单权限）**：若权限树应直接等于侧边栏菜单，可把
   `ALL_PERMISSION_TREE` 改为由 `router.getRoutes()` 扫描 `meta.menu` 自动生成，
   再用 `meta.hidden` / `meta.permission` 过滤；渲染逻辑与上面完全一致。本项目采取
   "权限树与路由解耦"的方案（功能权限 ≠ 菜单路由），二者选一即可。

## 8. 常见坑位速查

| 现象 | 根因 | 修复 |
|---|---|---|
| 父级勾选框不显示"半选" | `indeterminate` 非 HTML 属性，单纯 attribute 无效 | 用 `:indeterminate="计算函数"` 绑定（Vue 当作 DOM property 处理） |
| 复制角色后改一个、另一个跟着变 | 直接引用同一对象 | 用 `JSON.parse(JSON.stringify(perms))` 深拷贝 |
| 新增模块后老角色权限缺失 | 预设基于旧树骨架 | 预设一律 `createEmptyPermissions()` 起手再裁剪，不缓存旧矩阵 |
| 模块全选点了却只改了部分子项 | setter 没遍历 `sub.operations` | 用 `setModulePermissions` 统一改树，勿手写 |
| 半选后全选再取消逻辑错乱 | 父级状态被当成独立存储 | 父级状态永不由点击直接写，只由子级聚合派生 |

## 9. 最小交付检查项

- [ ] `ALL_PERMISSION_TREE` 声明完整（模块→子模块→操作三层，id/key 稳定唯一）
- [ ] `createEmptyPermissions` / `createAllPermissions` / `setModulePermissions` 就位
- [ ] 三态判定 `isModule/SubModule{AllChecked,Indeterminate}` 就位且被模板绑定
- [ ] 至少 1 个 `createRolePreset` 预设（建议含超管 + 只读审计员）
- [ ] 弹窗模板三层 `v-for` + 搜索过滤渲染通过
- [ ] 保存路径：深拷贝 → 序列化 → 提交；不做冗余选中态存储
