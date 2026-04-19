# 🔐 private/ ——「真实凭据」存放区（本目录默认被 gitignore 忽略）

此目录下的内容**不会提交到 Git**（除了本 README 和 `*.example` 模板）。

## 目录约定

| 文件 | 说明 |
|------|------|
| `env.sh` | 真实环境变量（VPS IP / token / 面板账号）。从 `env.sh.example` 复制后改 |
| `credentials.txt` | 从 VPS `/root/ace-vpn-credentials.txt` 下载的完整凭据（包含 UUID、pbk） |
| `subscription-urls.md` | 各设备的订阅 URL、Stash/Shadowrocket 用的 URL |
| `vps-inventory.md` | 当前/备用 VPS 的登录信息、到期时间、备份文件位置 |
| `家人-设备清单.md` | 谁用哪个 Client、Email、SubId |

## 首次使用

```bash
cp private/env.sh.example private/env.sh
$EDITOR private/env.sh   # 填真实值
chmod 600 private/env.sh
```

以后在 shell 里：

```bash
source private/env.sh
# 之后 $VPS_IP、$SUB_URL 就能用
```

## 同步 VPS 上的凭据到本地

```bash
scp root@${VPS_IP}:/root/ace-vpn-credentials.txt private/credentials.txt
chmod 600 private/credentials.txt
```

## 更改 VPS 后

当你从 Vultr 换到 Oracle 等新 VPS，只要：

1. 更新 `env.sh` 里的 `VPS_IP`、`SUB_TOKEN`、`PANEL_*`
2. 其他脚本、客户端订阅 URL 引用的都是 `$VPS_IP:${SUB_PORT}/clash/${SUB_TOKEN}`，重拉一遍即可

## 安全守则

- **绝对**不要把本目录内容复制/粘贴到任何公开聊天、截图前先马赛克 IP 段
- `chmod 600` 所有敏感文件
- 定期滚动 SubToken（`docs/06-client-setup.md` 有脚本）
- 如怀疑泄露：3x-ui 面板里把对应 Client 禁用，重新生成 UUID，全员更新订阅

## 备份建议

- 每月把 `private/` 整体打包丢到 1Password / Keeper 附件
- 或者 tar + gpg 加密后放到公有云（iCloud / Google Drive）
  ```bash
  tar czf - private/ | gpg -c > private-$(date +%Y%m%d).tar.gz.gpg
  ```
