# 配置文件说明

本文档详细说明了 `config.conf` 文件中各个配置项的含义和用法。

## 配置文件位置

- **默认位置**: `/opt/ip-sync/config.conf`
- **开发测试**: `{脚本目录}/config.conf`

## 配置项说明

### 基础配置

#### `Check_Interval` (检查间隔)

- **类型**: 整数
- **单位**: 秒
- **默认值**: `60`
- **说明**: 脚本执行一次同步检查的间隔时间。即每隔多少秒检查一次转发服务与机场配置是否需要同步。
- **示例**:
  ```bash
  Check_Interval=60      # 每 60 秒检查一次
  Check_Interval=3600    # 每 1 小时检查一次
  ```

#### `CF_Token` (Cloudflare API Token)

- **类型**: 字符串
- **默认值**: 空（可选）
- **说明**: Cloudflare API Token，用于自动创建和更新 DNS 记录。如果不配置，脚本将在需要更新域名解析时回退到本地 `ping` 命令解析。
- **重要性**: 强烈推荐配置，以支持域名模式下的自动 DNS 更新
- **获取方式**: 详见 [CF_Token获取指南](../CF_Token如何获取？.md)
- **示例**:
  ```bash
  CF_Token="v1.0d1e2e3f4g5h6i7j8k9l0m1n2o3p4q5r6s"
  ```

---

### 日志配置

#### `Log_File` (日志文件路径)

- **类型**: 字符串
- **默认值**: `$BASE_DIR/ip-sync.log`（脚本所在目录）
- **说明**: 日志文件的存储路径。建议使用绝对路径。如需将日志保存到系统日志目录，请确保有写权限。
- **示例**:
  ```bash
  Log_File="/var/log/ip-sync.log"        # 系统日志目录
  Log_File="/opt/ip-sync/ip-sync.log"   # 脚本目录
  Log_File="/home/user/logs/ip-sync.log" # 用户目录
  ```

#### `Log_Max_Lines` (日志最大行数)

- **类型**: 整数
- **默认值**: `5000`
- **说明**: 日志文件的最大保留行数。当日志超过此行数时，脚本会自动删除最早的日志，保留最近 N 行。设置为 `0` 表示不进行日志清理。
- **示例**:
  ```bash
  Log_Max_Lines=5000    # 保留最近 5000 行
  Log_Max_Lines=10000   # 保留最近 10000 行
  Log_Max_Lines=0       # 不清理日志
  ```

---

### 机场 (X-board) 配置

#### `Airport_Url` (机场 API 地址)

- **类型**: 字符串（URL）
- **默认值**: 无
- **说明**: 机场(X-board)的 API 地址，通常是 `https://your-airport-domain.com` 的形式。
- **示例**:
  ```bash
  Airport_Url="https://airport.example.com"
  Airport_Url="https://my-panel.com"
  ```

#### `Airport_Email` (机场登录邮箱)

- **类型**: 字符串（Email）
- **默认值**: 无
- **说明**: 用于登录机场后台的管理员账户邮箱。脚本使用此邮箱获取 auth token。
- **示例**:
  ```bash
  Airport_Email="admin@example.com"
  Airport_Email="panel-admin@mysite.com"
  ```

#### `Airport_Pass` (机场登录密码)

- **类型**: 字符串
- **默认值**: 无
- **说明**: 用于登录机场后台的管理员账户密码。
- **安全提示**: 
  - 脚本已对日志进行脱敏处理，不会打印密码
  - 建议为配置文件设置权限 `chmod 600 /opt/ip-sync/config.conf`
- **示例**:
  ```bash
  Airport_Pass="your_secure_password_123"
  ```

---

### 转发 (Nya) 服务配置

#### `Forward_Url` (转发服务 API 地址)

- **类型**: 字符串（URL）
- **默认值**: 无
- **说明**: 转发服务(Nya)的 API 地址，通常是 `https://your-forward-domain.com` 的形式。
- **示例**:
  ```bash
  Forward_Url="https://forward.example.com"
  Forward_Url="https://relay.myservice.com"
  ```

#### `Forward_User` (转发服务用户名)

- **类型**: 字符串
- **默认值**: 无
- **说明**: 用于登录转发服务的用户名或账户 ID。脚本使用此账户获取转发规则和入口 IP。
- **示例**:
  ```bash
  Forward_User="relay_admin"
  Forward_User="forward_account_001"
  ```

#### `Forward_Pass` (转发服务密码)

- **类型**: 字符串
- **默认值**: 无
- **说明**: 用于登录转发服务的密码。
- **安全提示**: 同上（脚本已脱敏处理）
- **示例**:
  ```bash
  Forward_Pass="forward_password_xyz"
  ```

---

## 完整配置示例

```bash
# ========================
# 基础配置
# ========================
# 检查间隔时间（秒）
Check_Interval=60

# Cloudflare API Token（可选，但强烈推荐配置）
CF_Token="your_cloudflare_api_token_here"

# ========================
# 日志配置
# ========================
Log_File="/var/log/ip-sync.log"
Log_Max_Lines=5000

# ========================
# 机场 (X-board) 配置
# ========================
Airport_Url="https://airport.example.com"
Airport_Email="admin@airport.example.com"
Airport_Pass="airport_password_123"

# ========================
# 转发 (Nya) 服务配置
# ========================
Forward_Url="https://forward.example.com"
Forward_User="forward_username"
Forward_Pass="forward_password_456"
```

---

## 配置最佳实践

### 1. 安全性

```bash
# 设置配置文件权限，仅所有者可读写
chmod 600 /opt/ip-sync/config.conf

# 避免在配置中使用弱密码或简单密码
# 使用强密码（至少 12 个字符，包含大小写、数字和特殊字符）
```

### 2. 日志管理

```bash
# 根据服务器存储空间调整日志保留行数
# 日志行数 = 日志大小（约 200 bytes/行）
Log_Max_Lines=5000    # 约 1 MB

# 如果需要长期保存日志，可配置日志轮转
# 系统日志通常会通过 logrotate 自动管理
```

### 3. 检查间隔

```bash
# 根据场景选择合适的检查间隔

# 场景 1: 频繁变更
Check_Interval=30      # 30 秒检查一次

# 场景 2: 正常使用（推荐）
Check_Interval=60      # 60 秒检查一次

# 场景 3: 低频变更
Check_Interval=300     # 5 分钟检查一次

# 场景 4: 生产环境（稳定）
Check_Interval=3600    # 1 小时检查一次
```

### 4. Cloudflare 配置

```bash
# Token 的权限应最小化，仅包含必要的权限：
# - Zone > DNS > Edit (编辑 DNS 记录)
# - Zone > Zone > Read (读取 Zone 信息)

# 如果不配置 CF_Token，脚本将：
# - 使用本地 ping 命令解析域名 IP
# - 无法自动创建新的 DNS 记录
# - 只能更新已存在的记录（通过修改主机名+端口）
```

---

## 配置验证

在修改配置后，可以通过以下方式验证配置是否正确：

### 1. 查看日志

```bash
ip-sync logs
```

日志中应该包含登录成功的提示：
```
[2024-01-15 14:30:45] 机场登录成功
[2024-01-15 14:30:46] 转发服务登录成功
```

### 2. 手动运行一次同步

```bash
# 先停止后台服务
ip-sync stop

# 手动运行脚本进行一次同步
./xboard-nya-sync.sh run_loop

# 观察输出中的错误信息
```

### 3. 检查 API 连接

```bash
# 测试机场 API 连接
curl -s -X POST "https://your-airport.com/api/v1/passport/auth/login" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  --data-urlencode "email=your@email.com" \
  --data-urlencode "password=yourpassword"

# 测试转发服务 API 连接
curl -s -X POST "https://your-forward.com/api/v1/auth/login" \
  -H "Content-Type: text/plain;charset=UTF-8" \
  --data '{"username":"your_user","password":"your_pass"}'
```

---

## 常见问题

### Q: 修改配置后需要重启服务吗？

**A**: 脚本会在每次检查时重新加载配置文件，所以修改配置后无需重启。但建议使用 `ip-sync reload` 命令重新加载，以确保新配置立即生效。

### Q: Cloudflare Token 丢失了怎么办？

**A**: CF Token 仅显示一次，无法恢复。需要在 Cloudflare Dashboard 中删除旧 Token，重新创建新的 Token。

### Q: 日志文件不存在怎么办？

**A**: 脚本会自动创建日志文件。如果在指定的 `Log_File` 路径无法创建，请检查：
- 目录是否存在
- 目录权限是否允许写入（通常需要 `drwxr-xr-x` 或以上权限）

### Q: 配置文件格式有要求吗？

**A**: 配置文件采用 bash source 格式，每行一个配置项，格式为 `KEY=value`。脚本通过 `source "$CONFIG_FILE"` 加载配置，所以配置必须符合 bash 变量定义规范。

---

## 敏感信息处理

脚本已实现以下安全措施来保护配置中的敏感信息：

1. **日志脱敏**: 日志中不会打印密码和 Token
2. **权限建议**: 建议将配置文件权限设置为 `600`，仅所有者可读写
3. **内存安全**: 敏感信息仅在内存中保留，不会被意外保存到临时文件

```bash
# 推荐设置
chmod 600 /opt/ip-sync/config.conf
```

---

## 配置重加载

脚本支持配置文件动态重加载，修改配置后无需重启服务：

```bash
# 重新加载配置并重启服务
ip-sync reload

# 或者只编辑配置
ip-sync config
```

配置会在下一个检查周期（`Check_Interval` 秒后）自动生效。
