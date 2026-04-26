# Cursor / VPS 稳定性测试报告

## 背景

这次测试的目标是解释两个问题：

1. HostHatch（HH）和 Vultr 哪个更适合作为日常默认 VPS；
2. 实际使用 Cursor 时，HH 曾出现过任务中断，是否能从 VPS 到 Cursor 的基础链路中测出异常。

测试分成两类：

- **综合 VPS 出站测试**：`vps-watch-urls.sh`，覆盖 99 个海外常用 URL，每 30 分钟从 HH / Vultr 两台 VPS 各测一轮；
- **Cursor 专项稳定性探针**：`cursor-stability-probe.sh`，只测 Cursor 公开端点，低频 `HEAD` 请求，不带账号态，不消耗 Cursor token。

## 测试时间

### 综合 VPS 出站测试

- 日志：`~/Library/Logs/ace-vpn/vps-watch.log`
- 汇总窗口：最近 30 天
- 本次报告取样范围：`2026-04-26 01:04:02` 至 `2026-04-27 00:39:07`
- URL 数：99
- 记录数：6930

### Cursor 专项稳定性探针

- 日志：`~/Library/Logs/ace-vpn/cursor-stability-probe.log`
- 正式长测开始：`2026-04-26 12:22:03 +0800`
- 正式长测结束：`2026-04-26 16:50:19 +0800`
- 轮数：120
- 间隔：约 120 秒一轮
- URL 数：4
- 记录数：960

测试端点：

- `https://cursor.com/`
- `https://api2.cursor.sh/`
- `https://api3.cursor.sh/`
- `https://repo42.cursor.sh/`

## 测试方法

### 综合 VPS 出站测试

`vps-watch-urls.sh` 从本地 Mac 定时触发，通过 SSH 分别到 HH / Vultr，在 VPS 上用 `curl` 请求同一批海外服务 URL。记录：

- HTTP 状态码；
- 总耗时 `time_total`；
- TCP 建连耗时；
- TLS 握手耗时；
- 远端 IP；
- 超时和慢请求。

`vps-watch-summary.py` 汇总以下指标：

- `ok_rate` / `timeouts` / `timeout_rate`
- `avg` / `median` / `p90` / `p95` / `p99`
- `slow_ge_2s`
- `pain_rate`：超时 + 2 秒以上慢请求占比
- `win_loss`：按 URL median 对比谁更快
- `node_latency_distribution`：耗时分布

### Cursor 专项稳定性探针

`cursor-stability-probe.sh` 专门用于验证“VPS 到 Cursor 公开入口”是否存在基础链路不稳定。

它默认使用 `HEAD` 请求，只取响应头，不下载正文，不带 Cookie、不带 API Key、不登录、不发模型请求，因此：

- 不消耗 Cursor token；
- 不触发真实模型调用；
- 不模拟完整 Agent 任务；
- 适合低频长时间观察 DNS / TCP / TLS / HTTP 层面的失败、超时、连接重置和尾延迟。

记录字段包括：

- `curl_exit`
- HTTP 状态码
- 总耗时
- TCP 建连耗时
- TLS 握手耗时
- TTFB
- 远端 IP
- 下载大小

汇总重点看：

- `fail_rate`
- `slow_rate`
- `median` / `p95` / `p99` / `worst`
- `max_consecutive_failures`
- `exit_codes`

## 综合 VPS 出站测试结果

```text
node       records  ok_rate  timeouts  timeout_rate  slow_ge_2s  pain_rate  avg    median  p90    p95    p99    p99/median  best  worst   win_loss
hosthatch  3465     94.9%    176       5.1%          35          6.1%       375ms  211ms   804ms  1.16s  2.06s  9.7x        41ms  15.48s  77:17
vultr      3465     94.9%    177       5.1%          39          6.2%       389ms  212ms   817ms  1.14s  2.50s  11.8x       71ms  9.92s   17:77
```

耗时分布：

```text
node       ok    timeouts  <100ms       100-300ms     300-800ms     800ms-2s     >=2s
hosthatch  3289  176       963 (29.3%)  1035 (31.5%)  959 (29.2%)   297 (9.0%)   35 (1.1%)
vultr      3288  177       739 (22.5%)  1309 (39.8%)  897 (27.3%)   304 (9.2%)   39 (1.2%)
```

综合判断：

- HH 和 Vultr 的 `ok_rate`、`timeout_rate` 非常接近；
- 两者 `median` 几乎一样，日常体感差距不大；
- HH 在 99 个 URL 中赢了 77 个，Vultr 赢了 17 个，另有 5 个无有效赢家；
- HH 的 `<100ms` 请求占比更高；
- Vultr 的 `p99` 和 `p99/median` 更高，说明尾延迟放大略明显；
- HH 出现过一次更极端的 `worst=15.48s`，但整体分位数仍优于 Vultr。

结论：**综合海外服务覆盖面看，HH 更适合作为默认节点，Vultr 适合作为 fallback。**

## Cursor 专项稳定性结果

节点级结果：

```text
node       records  fail_rate  slow_rate  avg    median  p95    p99    worst  max_consecutive_failures  exit_codes
hosthatch  480      0.0%       0.0%       320ms  374ms   494ms  517ms  561ms  0                         0:480
vultr      480      0.0%       0.0%       380ms  425ms   593ms  623ms  641ms  0                         0:480
```

端点级结果：

```text
node       url                         records  failures  slow  median  p95    worst  exit_codes
hosthatch  https://api2.cursor.sh/      120      0         0     474ms   490ms  529ms  0:120
hosthatch  https://api3.cursor.sh/      120      0         0     226ms   246ms  283ms  0:120
hosthatch  https://cursor.com/          120      0         0     87ms    156ms  221ms  0:120
hosthatch  https://repo42.cursor.sh/    120      0         0     476ms   514ms  561ms  0:120
vultr      https://api2.cursor.sh/      120      0         0     566ms   600ms  613ms  0:120
vultr      https://api3.cursor.sh/      120      0         0     249ms   275ms  332ms  0:120
vultr      https://cursor.com/          120      0         0     114ms   184ms  325ms  0:120
vultr      https://repo42.cursor.sh/    120      0         0     570ms   615ms  641ms  0:120
```

Cursor 专项判断：

- 两台 VPS 在 120 轮测试中都没有失败；
- `max_consecutive_failures=0`，没有测到连续失败；
- `slow_rate=0.0%`，没有超过慢请求阈值；
- HH 在四个 Cursor 端点上全部比 Vultr 更快；
- HH 的 `median`、`p95`、`p99`、`worst` 均低于 Vultr。

结论：**VPS 到 Cursor 公开入口的基础网络链路没有测出 HH 的中断问题；从公开端点的短连接稳定性看，HH 反而优于 Vultr。**

## 对 Cursor 任务中断的解释

这次 Cursor 专项探针只能证明：

- VPS 到 Cursor 公开端点的 DNS / TCP / TLS / HTTP HEAD 请求稳定；
- 没有发现超时、连接失败、curl reset 或连续失败；
- HH 在这些公开端点上的基础延迟比 Vultr 更低。

它不能完全覆盖 Cursor Agent 的真实任务链路，因为真实任务可能包含：

- Cursor IDE 到后端的账号态会话；
- WebSocket / gRPC / 长连接；
- 模型流式响应；
- 上下文上传；
- 工具调用；
- 长时间任务的服务端调度。

因此，如果以后仍然出现“HH 上 Cursor 任务中断，而 Vultr 不容易中断”，更可能是：

- 本地 Mac 到 HH 代理链路的长连接稳定性问题；
- Cursor Agent 的长连接 / 流式链路问题；
- Cursor 服务端任务调度或模型链路问题；
- 客户端会话状态、IDE 日志或账号态链路问题；
- 非 `HEAD` 短请求能覆盖的更上层问题。

## 最终结论

1. **默认节点建议继续用 HostHatch。**
   HH 在综合 99 个海外服务 URL 中赢面明显更大，在 Cursor 公开端点上也全面更快。

2. **Vultr 继续保留为 fallback。**
   Vultr 稳定性并不差，成功率和 HH 基本相同，只是整体赢面、低延迟占比、Cursor 专项表现弱于 HH。

3. **当前证据不支持“HH 到 Cursor 公开入口不稳定”。**
   长测没有测到 HH 的失败或连续失败。

4. **如果 Cursor 任务再次中断，应结合 Cursor IDE 日志一起看。**
   若当时 `cursor-stability-probe.log` 没有失败，而 Cursor IDE 任务中断，基本可以排除 VPS 到 Cursor 公开入口的短连接问题，转向排查长连接、流式响应、IDE 会话或 Cursor 服务端任务链路。

