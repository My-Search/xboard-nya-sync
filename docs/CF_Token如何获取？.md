
> 需要获取的是 Cloudflare 的 **API Token**（用户令牌），而不是旧版的 Global API Key。API Token 更安全，可以限制权限。

以下是获取步骤：

### 第一步：进入 API 令牌页面

1.  登录 [Cloudflare Dashboard](https://dash.cloudflare.com/)。
2.  点击右上角的用户头像，选择 **"My Profile" (我的个人资料)**。
3.  在左侧菜单栏点击 **"API Tokens" (API 令牌)**。
4.  点击 **"Create Token" (创建令牌)** 按钮。

### 第二步：创建自定义令牌

为了保证脚本能正常运行（自动获取 ZoneID 和 修改 DNS），建议**不要**直接选模板，而是点击最下方的 **"Create Custom Token" (创建自定义令牌)** 的 **"Get started"** 按钮。

### 第三步：配置权限 (关键步骤)

在创建页面填写以下信息：

1.  **Token name (令牌名称)**: 随便填，例如 `IP-Sync-Script`。
2.  **Permissions (权限)**: 需要添加**两条**权限：
      * **第一条 (用于修改解析):**
          * `Zone` (区域) -\> `DNS` -\> `Edit` (编辑)
      * **第二条 (用于脚本自动查找域名对应的 ID):**
          * 点击右侧 "+ Add more"
          * `Zone` (区域) -\> `Zone` (区域) -\> `Read` (读取)
3.  **Zone Resources (区域资源)**:
      * `Include` -\> `All zones` (所有区域)
      * *或者指定具体的域名，只要包含你要同步的那个域名即可。*

### 第四步：生成并复制

1.  点击底部的 **"Continue to summary"**。
2.  确认权限无误后，点击 **"Create Token"**。
3.  **立即复制显示的 Token 字符串**。
      * ⚠️ **注意**：这个 Token **只显示一次**，如果你刷新页面就再也看不到了（只能重新创建）。

-----

### 第五步：填入脚本配置

拿到 Token 后，在服务器上运行脚本菜单：

1.  运行 `./ip-sync.sh` (或者直接 `ip-sync` 如果你安装了)。
2.  选择 **6. 编辑配置**。
3.  在文件末尾添加一行（如果有旧的记得替换）：
    ```bash
    CF_Token="你刚才复制的一长串Token"
    ```
4.  保存退出（按 `Esc`，输入 `:wq`，回车）。
5.  选择 **3. 重启服务** 使配置生效。

### 验证 Token 是否有效 (可选)

你可以直接在服务器终端运行下面这个命令来测试 Token 是否有效（把 `你的Token` 换成真实的）：

```bash
curl -X GET "https://api.cloudflare.com/client/v4/user/tokens/verify" \
     -H "Authorization: Bearer 你的Token" \
     -H "Content-Type: application/json"
```

如果返回 `"status": "active"`，说明 Token 没问题。