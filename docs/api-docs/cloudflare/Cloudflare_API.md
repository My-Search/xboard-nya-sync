# Cloudflare API 文档

本文档详细说明了 `xboard-nya-sync` 脚本中使用的 Cloudflare API 接口及其工作原理。

## 概述

脚本通过 Cloudflare API 实现以下功能：
- 获取域名所属的 Zone ID
- 查询 DNS A 记录的当前值
- 创建新的 DNS A 记录
- 更新现有的 DNS A 记录

所有 API 调用均使用 **Bearer Token 认证** 方式。

---

## 1. 获取 Zone ID

### 功能说明

递归查找域名所属的 Zone ID。当脚本不知道完整的zone名称时，会从最长的域名开始逐级缩短进行查询，直到找到对应的 Zone。

**例如**: 查询 `node.subnet.example.com` 时，会依次尝试：
- `node.subnet.example.com`
- `subnet.example.com`
- `example.com` （找到！）

### API 端点

```
GET https://api.cloudflare.com/client/v4/zones?name={domain}
```

### 请求头

```
Authorization: Bearer {CF_Token}
Content-Type: application/json
```

### 请求参数

| 参数 | 类型 | 说明 |
|------|------|------|
| `name` | String | 要查询的域名 |

### 请求示例

```bash
curl -s -X GET "https://api.cloudflare.com/client/v4/zones?name=example.com" \
  -H "Authorization: Bearer your_token_here" \
  -H "Content-Type: application/json"
```

### 响应示例

```json
{
  "success": true,
  "errors": [],
  "messages": [],
  "result": [
    {
      "id": "023e105f4ecef8ad9ca31a8372d0c353",
      "name": "example.com",
      "status": "active",
      "paused": false,
      "type": "full",
      "plan": {
        "id": "free",
        "name": "Free",
        "price": 0,
        "currency": "USD",
        "frequency": "monthly",
        "legacy_id": "free",
        "legacy_name": "Free",
        "can_subscribe": true,
        "can_upgrade": true,
        "can_downgrade": true,
        "is_subscribed": true,
        "is_primary": true
      }
    }
  ],
  "result_info": {
    "page": 1,
    "per_page": 20,
    "total_pages": 1,
    "count": 1,
    "total_count": 1
  }
}
```

### 关键字段说明

| 字段 | 说明 |
|------|------|
| `success` | 请求是否成功 |
| `result[0].id` | Zone ID，用于后续操作 |
| `result[0].name` | 该 Zone 对应的域名 |

### 脚本中的使用

```bash
get_cf_zone_id() {
    local domain=$1
    local token=$2
    local current_domain=$domain
    
    while [[ "$current_domain" == *"."* ]]; do
        local response=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones?name=$current_domain" \
              -H "Authorization: Bearer $token" \
              -H "Content-Type: application/json")
        
        local zone_id=$(echo "$response" | jq -r '.result[0].id // empty')
        
        if [ -n "$zone_id" ]; then
            echo "$zone_id"
            return 0
        fi
        
        # 去掉最左边的一段，继续尝试
        current_domain=${current_domain#*.}
    done
    
    return 1
}
```

---

## 2. 获取 DNS 记录

### 功能说明

通过 Zone ID 和域名查询该域名的 A 记录（IPv4 地址记录）。

### API 端点

```
GET https://api.cloudflare.com/client/v4/zones/{zone_id}/dns_records?name={domain}&type=A
```

### 请求头

```
Authorization: Bearer {CF_Token}
Content-Type: application/json
```

### 路径参数

| 参数 | 说明 |
|------|------|
| `zone_id` | 从 Zone ID 查询接口获取 |

### 查询参数

| 参数 | 说明 |
|------|------|
| `name` | 要查询的完整域名 |
| `type` | DNS 记录类型，这里固定为 `A` |

### 请求示例

```bash
curl -s -X GET "https://api.cloudflare.com/client/v4/zones/023e105f4ecef8ad9ca31a8372d0c353/dns_records?name=node.example.com&type=A" \
  -H "Authorization: Bearer your_token_here" \
  -H "Content-Type: application/json"
```

### 响应示例

```json
{
  "success": true,
  "errors": [],
  "messages": [],
  "result": [
    {
      "id": "372e67954025e0ba6aaa6d586b9e0b59",
      "zone_id": "023e105f4ecef8ad9ca31a8372d0c353",
      "zone_name": "example.com",
      "name": "node.example.com",
      "type": "A",
      "content": "192.168.1.100",
      "proxied": true,
      "ttl": 1,
      "created_on": "2024-01-01T00:00:00Z",
      "modified_on": "2024-01-15T14:30:45Z",
      "data": {}
    }
  ],
  "result_info": {
    "page": 1,
    "per_page": 20,
    "total_pages": 1,
    "count": 1,
    "total_count": 1
  }
}
```

### 关键字段说明

| 字段 | 说明 |
|------|------|
| `success` | 请求是否成功 |
| `result[0].id` | DNS 记录 ID，用于更新或删除操作 |
| `result[0].content` | DNS 记录的内容，即 A 记录指向的 IP 地址 |
| `result[0].proxied` | 是否通过 Cloudflare 代理（false = DNS Only, true = Proxied） |
| `result[0].ttl` | 生存时间（Time To Live），1 表示自动 |

### 脚本中的使用

```bash
get_cf_record_ip() {
    local domain=$1
    local token=$2

    if [ -z "$token" ]; then
        return 1
    fi

    # 1. 获取 Zone ID
    local zone_id=$(get_cf_zone_id "$domain" "$token")
    if [ -z "$zone_id" ]; then
        return 1
    fi

    # 2. 获取 A 记录的 Content (IP)
    local record_res=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones/$zone_id/dns_records?name=$domain&type=A" \
        -H "Authorization: Bearer $token" \
        -H "Content-Type: application/json")
    
    local ip=$(echo "$record_res" | jq -r '.result[0].content // empty')
    
    echo "$ip"
}
```

---

## 3. 创建 DNS 记录

### 功能说明

当 DNS 记录不存在时，创建新的 A 记录。脚本在检测到转发入口 IP 不存在或与当前记录不一致且记录不存在时触发此操作。

### API 端点

```
POST https://api.cloudflare.com/client/v4/zones/{zone_id}/dns_records
```

### 请求头

```
Authorization: Bearer {CF_Token}
Content-Type: application/json
```

### 路径参数

| 参数 | 说明 |
|------|------|
| `zone_id` | 从 Zone ID 查询接口获取 |

### 请求体

```json
{
  "type": "A",
  "name": "node.example.com",
  "content": "192.168.1.200",
  "ttl": 1,
  "proxied": false
}
```

### 请求参数说明

| 参数 | 类型 | 说明 | 默认值 |
|------|------|------|--------|
| `type` | String | DNS 记录类型 | `A` |
| `name` | String | 完整的域名 | 必须 |
| `content` | String | IPv4 地址 | 必须 |
| `ttl` | Integer | 生存时间（秒）。1 表示自动 | `1` |
| `proxied` | Boolean | 是否通过 Cloudflare 代理。脚本固定为 `false`（DNS Only） | `false` |

### 请求示例

```bash
curl -s -X POST "https://api.cloudflare.com/client/v4/zones/023e105f4ecef8ad9ca31a8372d0c353/dns_records" \
  -H "Authorization: Bearer your_token_here" \
  -H "Content-Type: application/json" \
  --data '{
    "type": "A",
    "name": "node.example.com",
    "content": "192.168.1.200",
    "ttl": 1,
    "proxied": false
  }'
```

### 响应示例

```json
{
  "success": true,
  "errors": [],
  "messages": [],
  "result": {
    "id": "372e67954025e0ba6aaa6d586b9e0b59",
    "zone_id": "023e105f4ecef8ad9ca31a8372d0c353",
    "zone_name": "example.com",
    "name": "node.example.com",
    "type": "A",
    "content": "192.168.1.200",
    "proxied": false,
    "ttl": 1,
    "created_on": "2024-01-15T14:30:46Z",
    "modified_on": "2024-01-15T14:30:46Z",
    "data": {}
  }
}
```

### 脚本中的使用

```bash
# 新建记录强制不走代理 (proxied: false)
local create_res=$(curl -s -X POST "https://api.cloudflare.com/client/v4/zones/$zone_id/dns_records" \
    -H "Authorization: Bearer $CF_Token" \
    -H "Content-Type: application/json" \
    --data "{\"type\":\"A\",\"name\":\"$domain\",\"content\":\"$new_ip\",\"ttl\":1,\"proxied\":false}")

if [[ $(echo "$create_res" | jq -r '.success') == "true" ]]; then
    log "Success: Cloudflare 记录 [$domain] 创建成功 -> $new_ip"
else
    log "Fail: Cloudflare 创建失败 - $(echo "$create_res" | jq -r '.errors[0].message')"
fi
```

---

## 4. 更新 DNS 记录

### 功能说明

当 DNS 记录存在且 IP 地址需要更新时，使用 PUT 方法更新现有记录。脚本会保留原有的 `proxied` 状态，确保不影响用户的代理设置。

### API 端点

```
PUT https://api.cloudflare.com/client/v4/zones/{zone_id}/dns_records/{record_id}
```

### 请求头

```
Authorization: Bearer {CF_Token}
Content-Type: application/json
```

### 路径参数

| 参数 | 说明 |
|------|------|
| `zone_id` | 从 Zone ID 查询接口获取 |
| `record_id` | 从 DNS 记录查询接口获取 |

### 请求体

```json
{
  "type": "A",
  "name": "node.example.com",
  "content": "192.168.1.200",
  "ttl": 1,
  "proxied": true
}
```

### 请求参数说明

| 参数 | 类型 | 说明 |
|------|------|------|
| `type` | String | DNS 记录类型，固定为 `A` |
| `name` | String | 完整的域名 |
| `content` | String | 新的 IPv4 地址 |
| `ttl` | Integer | 生存时间（秒），1 表示自动 |
| `proxied` | Boolean | 是否代理，保留原有值 |

### 请求示例

```bash
curl -s -X PUT "https://api.cloudflare.com/client/v4/zones/023e105f4ecef8ad9ca31a8372d0c353/dns_records/372e67954025e0ba6aaa6d586b9e0b59" \
  -H "Authorization: Bearer your_token_here" \
  -H "Content-Type: application/json" \
  --data '{
    "type": "A",
    "name": "node.example.com",
    "content": "192.168.1.200",
    "ttl": 1,
    "proxied": true
  }'
```

### 响应示例

```json
{
  "success": true,
  "errors": [],
  "messages": [],
  "result": {
    "id": "372e67954025e0ba6aaa6d586b9e0b59",
    "zone_id": "023e105f4ecef8ad9ca31a8372d0c353",
    "zone_name": "example.com",
    "name": "node.example.com",
    "type": "A",
    "content": "192.168.1.200",
    "proxied": true,
    "ttl": 1,
    "created_on": "2024-01-01T00:00:00Z",
    "modified_on": "2024-01-15T14:30:46Z",
    "data": {}
  }
}
```

### 脚本中的使用

```bash
local update_res=$(curl -s -X PUT "https://api.cloudflare.com/client/v4/zones/$zone_id/dns_records/$record_id" \
    -H "Authorization: Bearer $CF_Token" \
    -H "Content-Type: application/json" \
    --data "{\"type\":\"A\",\"name\":\"$domain\",\"content\":\"$new_ip\",\"ttl\":1,\"proxied\":$current_proxied}")
    
if [[ $(echo "$update_res" | jq -r '.success') == "true" ]]; then
    log "Success: Cloudflare 记录 [$domain] 更新成功 -> $new_ip (Zone: $zone_id)"
else
    log "Fail: Cloudflare 更新失败 - $(echo "$update_res" | jq -r '.errors[0].message')"
fi
```

---

## 5. 认证方式

### Bearer Token 认证

所有请求均使用 Bearer Token 方式认证：

```bash
Authorization: Bearer {CF_Token}
```

其中 `CF_Token` 是从 Cloudflare Dashboard 获取的 API Token。

#### 获取 Token 的步骤

详见 [CF_Token获取指南](../CF_Token如何获取？.md)

**关键权限要求：**
- `Zone` → `DNS` → `Edit` (编辑 DNS 记录)
- `Zone` → `Zone` → `Read` (读取 Zone 信息)

---

## 6. 错误处理

### 常见错误响应

#### 示例 1：Token 无效或过期

```json
{
  "success": false,
  "errors": [
    {
      "code": 10000,
      "message": "Authentication error"
    }
  ],
  "messages": [],
  "result": null
}
```

**解决方法：** 检查 Token 是否过期或权限不足，重新创建 Token。

#### 示例 2：域名不在该 CF 账户下

```json
{
  "success": false,
  "errors": [
    {
      "code": 9000,
      "message": "Nameserver error"
    }
  ],
  "messages": [],
  "result": null
}
```

**解决方法：** 确保域名已添加到 Cloudflare 账户，或检查权限配置。

#### 示例 3：权限不足

```json
{
  "success": false,
  "errors": [
    {
      "code": 10013,
      "message": "Insufficient permissions to complete operation."
    }
  ],
  "messages": [],
  "result": null
}
```

**解决方法：** 创建新 Token 时应包含 `Zone.DNS.Edit` 权限。

### 脚本的错误处理

脚本在调用 CF API 失败时采取以下策略：

1. **获取 Zone ID 失败** → 返回错误，日志记录
2. **获取 DNS 记录失败** → 尝试创建新记录
3. **创建或更新记录失败** → 记录错误日志，继续处理下一个节点

```bash
if [[ $(echo "$response" | jq -r '.success') == "true" ]]; then
    log "Success: ..."
else
    log "Fail: Cloudflare 更新失败 - $(echo "$response" | jq -r '.errors[0].message')"
fi
```

---

## 7. 速率限制

Cloudflare API 对免费版账户有速率限制：

- **免费版**: 1200 次请求 / 小时
- **专业版及以上**: 请参考官方文档

**脚本的设计**: 默认检查间隔为 60 秒，每次检查最多触发几个 CF API 调用，通常不会触及速率限制。

---

## 8. 完整工作流示例

以下展示一个完整的 DNS 记录更新流程：

```bash
# 1. 获取 Zone ID
zone_id=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones?name=example.com" \
  -H "Authorization: Bearer your_token" \
  -H "Content-Type: application/json" | jq -r '.result[0].id')

# 输出: 023e105f4ecef8ad9ca31a8372d0c353

# 2. 查询现有 DNS 记录
record=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones/$zone_id/dns_records?name=node.example.com&type=A" \
  -H "Authorization: Bearer your_token" \
  -H "Content-Type: application/json")

record_id=$(echo "$record" | jq -r '.result[0].id')
current_ip=$(echo "$record" | jq -r '.result[0].content')
proxied=$(echo "$record" | jq -r '.result[0].proxied')

# 3. 如果 IP 需要更新
if [ "$current_ip" != "192.168.1.200" ]; then
  curl -s -X PUT "https://api.cloudflare.com/client/v4/zones/$zone_id/dns_records/$record_id" \
    -H "Authorization: Bearer your_token" \
    -H "Content-Type: application/json" \
    --data "{\"type\":\"A\",\"name\":\"node.example.com\",\"content\":\"192.168.1.200\",\"ttl\":1,\"proxied\":$proxied}"
fi
```

---

## 参考资源

- [Cloudflare API 官方文档](https://developers.cloudflare.com/api/)
- [DNS Records API](https://developers.cloudflare.com/api/operations/dns-records-list-dns-records)
- [Zones API](https://developers.cloudflare.com/api/operations/zones-list-zones)
- [认证方式](https://developers.cloudflare.com/api/tokens/create/providers/)
