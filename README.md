# xboard-nya-sync

一个自动同步转发服务与机场节点配置的工具。通过监控转发规则，自动更新机场(X-board)中对应的节点信息，支持Cloudflare DNS自动更新。

## 🎯 功能特性

- **自动转发同步**: 监控转发服务的配置，自动推送到机场端
- **IP/域名双模式**: 支持IP地址直接更新，也支持域名自动DNS更新
- **Cloudflare集成**: 支持自动创建和更新Cloudflare DNS记录
- **容错机制**: CF API失败时自动回退到本地DNS解析
- **服务化部署**: 支持systemd服务，可全局调用
- **日志管理**: 自动日志轮转，支持自定义日志文件和保留行数
- **灵活配置**: 支持配置文件动态重加载，无需重启即生效

## 📋 环境要求

- Linux系统（支持systemd）
- bash shell
- 必要命令：`jq`, `curl`, `ping`
- 需要root权限（用于安装systemd服务）

## 🚀 快速开始

### 一键安装

```bash
sudo sh -c '(DIR=/opt/ip-sync; mkdir -p "$DIR" && curl -fsSL -o "$DIR/xboard-nya-sync.sh" https://raw.githubusercontent.com/My-Search/xboard-nya-sync/refs/heads/master/xboard-nya-sync.sh && curl -fsSL -o "$DIR/config.conf" https://raw.githubusercontent.com/My-Search/xboard-nya-sync/refs/heads/master/config.conf && chmod +x "$DIR/xboard-nya-sync.sh" && "$DIR/xboard-nya-sync.sh")'
```
> 简要使用流程：在服务器上运行上面命令，选择"安装服务"，然后"编辑配置"，配置`cf token`、`机场的配置`、`nyanpass面板类型的转发平台-套餐用户登录信息配置`。最后请确保转发规则名包含机场的节点名进行关联即可，会自动配置检查配置机场的host与port（如果host是域名，请确保cf已经管理了该域名，会自动修改或创建对应的域名-转发入口ip 映射关系）。

### 安装步骤

1. **先配置后安装**: 使用脚本菜单编辑配置文件，填入必要的API密钥和登录信息
2. **安装服务**: 选择菜单中的安装选项，脚本将自动创建systemd服务
3. **全局调用**: 安装后可直接使用 `ip-sync` 命令（需要重新登录或source shell）

## ⚙️ 配置说明

详见 [配置文件说明](docs/config.md)

### 基础配置示例

```bash
# 检查间隔（秒）
Check_Interval=60

# Cloudflare API Token（可选，但推荐配置）
CF_Token="your_cloudflare_api_token"

# 日志配置
Log_File="/var/log/ip-sync.log"
Log_Max_Lines=5000

# 机场(X-board)配置
Airport_Url="https://xxx.com"
Airport_Email="admin@example.com"
Airport_Pass="password"

# 转发(Nya)服务配置
Forward_Url="https://yyy.com"
Forward_User="username"
Forward_Pass="password"
```

## 📚 详细文档

- [CF_Token获取指南](docs/CF_Token如何获取？.md) - 如何申请和配置Cloudflare API Token
- [Cloudflare API文档](docs/api-docs/cloudflare/Cloudflare_API.md) - 脚本使用的Cloudflare API详解
- [机场与转发接口说明](docs/api-docs/base/机场与转发的接口.md) - 整合的API接口文档

## 🔧 使用命令

安装后可使用以下全局命令：

```bash
# 查看服务状态
ip-sync status

# 启动服务
ip-sync start

# 停止服务
ip-sync stop

# 重启服务
ip-sync restart

# 重新加载配置
ip-sync reload

# 查看日志（实时尾部）
ip-sync logs

# 编辑配置文件
ip-sync config
```

## 🔄 同步逻辑说明

### 核心工作流程

1. **登录认证**
   - 向机场API登录，获取auth_data token
   - 向转发服务API登录，获取用户token

2. **数据采集**
   - 获取转发服务的所有入口组及其IP地址
   - 获取机场的所有Shadowsocks节点配置

3. **规则匹配**
   - 通过节点名称包含关系匹配转发规则
   - 获取转发规则的入口IP和监听端口

4. **变更同步**
   - **IP模式**: 如果节点地址是IP，直接对比更新
   - **域名模式**: 如果节点地址是域名，自动更新DNS解析指向新IP

### 场景说明

#### 场景 A: 机场节点为IP地址

```
机场节点: 192.168.1.100:12345
转发入口: 192.168.1.200:12345

检测到IP不同或端口不同 -> 直接更新机场节点信息
```

#### 场景 B: 机场节点为域名

```
机场节点: node.example.com:12345
转发入口: 192.168.1.200:12345

检测逻辑:
1. 尝试从CF API获取node.example.com的A记录IP
2. 如果CF获取失败，回退到本地ping解析
3. 如果解析失败（记录不存在），自动在CF创建DNS记录
4. 如果IP不匹配，更新CF中的DNS记录
5. 检测端口是否变更，需要时同时更新
```

## 🔐 安全性说明

- **权限隔离**: Cloudflare API Token建议创建自定义Token，仅授予DNS编辑权限
- **日志脱敏**: 避免在日志中打印密码和Token（脚本已处理）
- **Token保护**: API Token仅显示一次，丢失无法恢复，需重新创建
- **配置权限**: `/opt/ip-sync/config.conf` 文件建议设置为 `600` 权限（仅owner可读写）

```bash
chmod 600 /opt/ip-sync/config.conf
```

## 📊 日志说明

### 日志位置

默认: `/var/log/ip-sync.log` （可在配置中修改）

### 日志示例

```
[2024-01-15 14:30:45] 开始同步检查...
[2024-01-15 14:30:46] Success: Cloudflare 记录 [node.example.com] 更新成功 -> 192.168.1.200 (Zone: abc123xyz)
[2024-01-15 14:30:47] Success: 节点 [CN-HK] (ID:1) 已推送到机场 -> Host: 192.168.1.200, Port: 12345
[2024-01-15 14:30:48] 同步检查完成。
```

### 日志清理

脚本自动清理日志，保留最近 `Log_Max_Lines` 行（默认5000行）

## 🐛 故障排查

### 无法连接到API

1. 检查网络连接
2. 确认API地址和认证信息正确
3. 查看日志查找具体错误信息：`ip-sync logs`

### Cloudflare更新失败

1. 验证CF_Token是否有效和权限正确
2. 检查域名是否在该CF账户下
3. 查看日志中的错误消息

### 节点未更新

1. 确认转发规则名称与机场节点名称有包含关系
2. 检查转发服务的入口组配置
3. 查看日志确认规则是否匹配

## 🤝 贡献

欢迎提交Issue和Pull Request

## 📄 许可证

MIT License
