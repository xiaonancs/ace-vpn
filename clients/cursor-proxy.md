# 💻 Cursor / VS Code 代理配置

> Cursor 基于 VS Code + Electron + Node.js，**默认不完全遵循 macOS 系统代理**。  
> Claude Code 是 Cursor 里的一部分，**同样的坑**。  
> 本文给出三层解决方案，建议 **方案 A + B 同时生效**，最稳。

---

## 方案 A（最优）：Clash Meta 开 TUN 模式

**一次配置，所有命令行 / Electron / Native 程序自动走代理**，不用改任何 App 设置。

### 开启步骤

**Mihomo Party / Clash Verge Rev**：
1. 设置 → TUN 模式 → **开启**
2. 堆栈类型：`Mixed`（兼容性最好）
3. 自动路由：✅
4. 自动检测接口：✅
5. 保存后会弹窗要 **授权**（需要 sudo 密码），授权一次以后不用管

### 验证

```bash
curl https://api.ipify.org
# 应该返回 VPS 的境外 IP，而不是本地 IP
```

### 注意事项

- **必须**在 `mac-clash-meta.yaml` 里配好"公司 CIDR → DIRECT"规则，否则 TUN 会把公司流量也劫走
- 参考 [`mac-clash-meta.yaml`](mac-clash-meta.yaml) 里的 `tun.exclude-interface` 段

---

## 方案 B：Cursor 显式配置代理

即使 TUN 已开，**保险起见** 在 Cursor 里也配一份。

### 打开设置

Cursor → **Cmd+,** 打开设置 → 搜索 `proxy`

或者直接编辑 `~/Library/Application Support/Cursor/User/settings.json`：

```json
{
  "http.proxy": "http://127.0.0.1:7890",
  "http.proxyStrictSSL": false,
  "http.proxySupport": "on",

  "github.copilot.advanced": {
    "debug.overrideProxyUrl": "http://127.0.0.1:7890"
  }
}
```

> **端口按实际客户端改**：Mihomo Party 默认 7890，Clash Verge Rev 默认 7897。

### Cursor 内 AI 请求的特别配置

Cursor 有些请求会绕开 `http.proxy`。如果还是有问题：

```json
{
  "cursor.general.disableHttp2": false,
  "cursor.general.enableLogging": true
}
```

然后在 Cursor → Help → Show Logs 看请求是否被代理。

---

## 方案 C：终端命令行代理（Claude Code 专用）

如果你经常在 Cursor 内置终端里跑 **claude code**、**git push**、**npm install**、**pip install**：

1. 把 [`shell-proxy.sh`](shell-proxy.sh) 拷到 `~/.ace-vpn/`
2. 在 `~/.zshrc` 末尾加：

```bash
source ~/.ace-vpn/shell-proxy.sh
proxy_on   # 默认开启
```

3. 重开终端，运行 `proxy_status` 确认

这样 Cursor 内置终端和外部 iTerm 都会继承代理变量。

---

## 验证清单

打开 Cursor，按顺序测：

- [ ] `curl https://api.ipify.org` → 境外 IP
- [ ] Cursor 底部 AI 对话能正常回复
- [ ] Cursor 里的 Claude Code 可用（`claude` 命令）
- [ ] `gh api /user` 能返回正常 JSON
- [ ] `npm install` 能从 npmjs.org 拉包
- [ ] 访问公司 Git（如 `git.corp.example.com`）**不**走代理（`NO_PROXY` 生效）

---

## 故障排查

### 症状：Cursor 提示 "Failed to connect to Cursor API"
1. 先 `curl https://api.cursor.sh` 看通不通
2. 通 → Cursor 没读到代理，检查 `settings.json`
3. 不通 → 你的客户端规则里没放 Cursor 相关域名，见 `mac-clash-meta.yaml` 里的 `DOMAIN-KEYWORD,cursor` 规则

### 症状：Claude Code 报 timeout
1. `proxy_status` 确认 `HTTPS_PROXY` 有值
2. 直接测 `curl -I https://api.anthropic.com` 看响应
3. 慢 → VPS 线路问题，切换到 Hysteria2 出口

### 症状：公司 git 拉不下来
- 检查 `NO_PROXY` 里是否包含公司 git 域名
- `echo $NO_PROXY` 确认
- 临时 `GIT_SSH_COMMAND='ssh -o ProxyCommand=none' git pull`
