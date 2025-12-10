使用：

```bash
sudo sh -c '(DIR=/opt/ip-sync; mkdir -p "$DIR" && curl -fsSL -o "$DIR/xboard-nya-sync.sh" https://raw.githubusercontent.com/My-Search/xboard-nya-sync/refs/heads/master/xboard-nya-sync.sh && curl -fsSL -o "$DIR/config.conf" https://raw.githubusercontent.com/My-Search/xboard-nya-sync/refs/heads/master/config.conf && chmod +x "$DIR/xboard-nya-sync.sh" && "$DIR/xboard-nya-sync.sh")'
```
<img width="839" height="364" alt="image" src="https://github.com/user-attachments/assets/6ad4fb13-6940-4ab7-a23c-368d062a5c3d" />

先配置再安装服务。

安装后可全局使用`ip-sync`, 如`ip-sync logs`
