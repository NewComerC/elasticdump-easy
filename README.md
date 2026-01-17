# Elasticdump Easy

[![License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![Platform](https://img.shields.io/badge/platform-Linux-lightgrey.svg)](https://www.linux.org/)

> 让 Elasticsearch 数据迁移变得简单 - 基于 [elasticdump](https://github.com/elasticsearch-dump/elasticsearch-dump) 的一站式解决方案

## 📖 项目简介

Elasticdump Easy 是一个面向初中阶 Elasticsearch 用户的数据迁移工具，旨在解决使用 elasticdump 过程中遇到的各种痛点问题，让数据 dump 操作**开箱即用、简单高效**。

### 🎯 为什么选择 Elasticdump Easy？

如果你在使用 elasticdump 时遇到过以下问题：

- ❌ Session 过期导致长时间运行的任务失败
- ❌ 每次都要手动拼接复杂的命令行参数
- ❌ 大索引导出经常超时失败
- ❌ 不知道如何选择最佳参数
- ❌ 任务失败后需要从头开始
- ❌ 缺少进度反馈，不知道任务是否正常

那么 Elasticdump Easy 就是为你准备的！

### ✨ 核心特性

#### 1. **零配置快速启动**
```bash
# 最简单的用法 - 一行命令完成迁移
elasticdump-easy dump my_index \
  --from http://source:9200 \
  --to http://target:9200
```

无需创建配置文件，直接在命令行指定源和目标即可开始。

#### 2. **智能参数选择**

工具会自动检测索引大小和文档数量，智能选择最佳参数：

| 索引规模 | 文档数量 | 自动选择 |
|---------|---------|---------|
| 小索引 | < 10万 | scroll 模式, limit=2000 |
| 中等索引 | 10万-100万 | scroll 模式, limit=1000 |
| 大索引 | 100万-1000万 | search_after 模式, limit=1000 |
| 超大索引 | > 1000万 | search_after 模式, limit=500, 建议分片 |

#### 3. **友好的用户体验**

**实时进度显示：**
```
正在导出索引: my_index
模式: Scroll API
进度: [████████████████░░░░] 78% (78,234/100,000 docs)
速度: 1,234 docs/s
已用时间: 00:01:23
预估剩余: 00:00:18
```

**清晰的错误提示：**
```
✗ 错误: 无法连接到源 ES
  地址: http://source:9200
  原因: Connection refused

💡 解决方案:
  1. 检查 ES 服务是否运行
  2. 检查网络连接和防火墙
  3. 验证 URL 和端口是否正确

🔧 测试连接: elasticdump-easy test --from http://source:9200
```

#### 4. **后台执行 + 日志追踪**

任务自动在后台运行，不受 session 影响：

```bash
# 启动任务
elasticdump-easy dump my_index

# 查看状态
elasticdump-easy status my_index

# 查看日志
tail -f elasticdump.my_index.log

# 停止任务
elasticdump-easy stop my_index
```

#### 5. **大索引分片导出**

超大索引可以按分片逐个导出，大大提高成功率：

```bash
# 查看分片信息
elasticdump-easy dump large_index --shard 0
elasticdump-easy dump large_index --shard 1
# ...
```

#### 6. **断点续传支持**

任务失败后可以从中断点继续，无需重新开始：

```bash
elasticdump-easy resume my_index
```

## 🚀 快速开始

### 安装

#### 一键安装（推荐）

```bash
# 克隆仓库
git clone https://github.com/NewComerC/elasticdump-easy.git
cd elasticdump-easy

# 运行安装脚本
./install.sh
```

安装脚本会自动：
- 检测并安装 Node.js 和 npm
- 全局安装 elasticdump
- 配置 `elasticdump-easy` 全局命令
- 安装可选依赖（jq, python3, curl）

#### 手动安装

```bash
# 1. 安装 Node.js 和 npm
curl -fsSL https://deb.nodesource.com/setup_lts.x | sudo -E bash -
sudo apt-get install -y nodejs

# 2. 安装 elasticdump
sudo npm install -g elasticdump

# 3. 配置全局命令
sudo ln -s $(pwd)/bin/elasticdump-easy /usr/local/bin/elasticdump-easy
```

### 第一次使用

#### 方式一：直接使用（零配置）

```bash
# 本地到本地
elasticdump-easy dump my_index

# 跨集群迁移
elasticdump-easy dump my_index \
  --from http://user1:pass1@source:9200 \
  --to http://user2:pass2@target:9200

# 重命名索引
elasticdump-easy dump source_index \
  --to http://target:9200/target_index
```

#### 方式二：配置向导（推荐）

```bash
# 运行配置向导
elasticdump-easy init

# 使用保存的配置
elasticdump-easy dump my_index --profile prod
```

## 📚 使用指南

### 基本命令

```bash
# 查看帮助
elasticdump-easy --help

# 导出索引
elasticdump-easy dump <索引名> [选项]

# 查看任务状态
elasticdump-easy status [索引名]

# 停止任务
elasticdump-easy stop <索引名>

# 列出所有任务
elasticdump-easy list

# 测试连接
elasticdump-easy test --from <URL>

# 配置向导
elasticdump-easy init
```

### 常用选项

| 选项 | 说明 | 默认值 |
|-----|------|--------|
| `--from <URL>` | 源 ES 地址 | http://localhost:9200 |
| `--to <URL>` | 目标 ES 地址 | http://localhost:9200 |
| `--output-index <名称>` | 输出索引名 | 与输入索引相同 |
| `--limit <数量>` | 每批文档数 | 自动选择 |
| `--mode <模式>` | dump 模式 (scroll/search_after) | 自动选择 |
| `--shard <ID>` | 仅导出指定分片 | - |
| `--offset <数量>` | 从第 N 个文档开始 | - |
| `--use-source-mapping` | 从源索引获取 mapping | false |
| `--ignore-errors` | 忽略单个文档错误 | true |
| `--quiet` | 静默模式 | false |
| `--debug` | 调试模式 | false |

### 使用场景

#### 场景 1：基本数据迁移

最简单的使用方式：

```bash
elasticdump-easy dump my_index \
  --from http://old-cluster:9200 \
  --to http://new-cluster:9200
```

#### 场景 2：跨集群迁移（带认证）

```bash
elasticdump-easy dump my_index \
  --from http://user1:pass1@source:9200 \
  --to http://user2:pass2@target:9200
```

#### 场景 3：大索引分片导出

```bash
# 导出分片 0
elasticdump-easy dump large_index --shard 0

# 导出分片 1
elasticdump-easy dump large_index --shard 1

# 继续导出其他分片...
```

#### 场景 4：自定义批量大小

如果索引包含大文档，可以减小批量大小：

```bash
elasticdump-easy dump my_index --limit 100
```

#### 场景 5：从源获取 Mapping

自动从源索引获取 mapping 并应用到目标：

```bash
elasticdump-easy dump my_index --use-source-mapping
```

#### 场景 6：重命名索引

```bash
elasticdump-easy dump old_name \
  --to http://target:9200/new_name
```

## 💡 核心痛点解决方案

### 痛点 1：Session 过期导致 dump 失败

**问题：** 长时间运行的 dump 任务可能因 SSH session 断开而失败

**解决方案：**
- ✅ 任务自动在后台运行
- ✅ 使用 nohup 确保不受 session 影响
- ✅ 提供日志文件追踪进度
- ✅ 支持任务状态查询

### 痛点 2：配置管理不便

**问题：** 每次都要手动拼接复杂的 URL 和参数

**解决方案：**
- ✅ 支持命令行直接传参（零配置）
- ✅ 支持配置文件（可选）
- ✅ 支持 profile 管理（多环境）
- ✅ 提供交互式配置向导

### 痛点 3：参数优化不足

**问题：** 不知道如何选择最佳参数，导致任务失败

**解决方案：**
- ✅ 自动检测索引大小
- ✅ 智能选择最佳参数
- ✅ 优化超时和重试设置
- ✅ 默认启用错误容忍

### 痛点 4：分页方式单一

**问题：** 默认 scroll API 在某些场景下效率低

**解决方案：**
- ✅ 支持 Scroll API（稳定）
- ✅ 支持 Search After + PIT（高效）
- ✅ 根据索引大小自动选择
- ✅ 支持手动指定模式

### 痛点 5：大索引 dump 困难

**问题：** 超大索引一次性 dump 成功率低

**解决方案：**
- ✅ 支持分片级别导出
- ✅ 支持断点续传
- ✅ 提供进度追踪
- ✅ 完善的错误处理

### 痛点 6：缺少进度反馈

**问题：** 不知道任务进度和预估完成时间

**解决方案：**
- ✅ 实时进度百分比
- ✅ 显示导出速度
- ✅ 预估剩余时间
- ✅ 支持状态查询

## 🔍 故障排查

### 连接失败

```bash
# 测试连接
elasticdump-easy test --from http://source:9200

# 检查 ES 服务
curl http://source:9200

# 查看详细日志
elasticdump-easy dump my_index --debug
```

### 认证失败

```bash
# 确认 URL 格式
http://username:password@host:9200

# 特殊字符需要 URL 编码
# 例如: password#123 -> password%23123
```

### 任务失败

```bash
# 查看日志
tail -f elasticdump.my_index.log

# 分析错误
elasticdump-easy status my_index

# 使用更小的批量大小重试
elasticdump-easy dump my_index --limit 500
```

### 大索引超时

```bash
# 使用分片导出
elasticdump-easy dump large_index --shard 0

# 或减小批量大小
elasticdump-easy dump large_index --limit 500
```

## 🤝 贡献

欢迎提交 Issue 和 Pull Request！

## 📄 许可证

MIT License

## 🙏 致谢

- [elasticdump](https://github.com/elasticsearch-dump/elasticsearch-dump) - 本项目基于 elasticdump 构建
- 感谢所有贡献者和用户的反馈

## 📞 支持

- GitHub Issues: https://github.com/NewComerC/elasticdump-easy/issues
- 文档: https://github.com/NewComerC/elasticdump-easy#readme

---

**让 ES 数据迁移变得简单！** 🚀
