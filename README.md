# 飞牛番组管家
飞牛番组管家 - 自动同步飞牛影视观看记录至 Bangumi

[![License: GPL v3](https://img.shields.io/badge/License-GPLv3-blue.svg)](https://www.gnu.org/licenses/gpl-3.0)
[![Docker Pulls](https://img.shields.io/docker/pulls/leclerca/fn-bangumi-sync)](https://hub.docker.com/r/leclerca/fn-bangumi-sync)

---

## 🎯 核心特性

打通本地媒体库与云端追番记录的隔阂，实现飞牛观看、云端秒刷。

* 🧬 **智能跨季识别**：解决飞牛长篇连载合并与 Bangumi 多季拆分的冲突。系统自动抓取续集图谱并换算。
* 🌗 **现代化UI**：自适应网格布局，支持日/夜间模式无缝切换。内置一键重置记忆库功能，并提供实时后台日志数据流。
* 🔐 **绝对数据安全**：全架构基于 `mode=ro` 挂载底层 SQLite 数据库。仅做数据检索，零写入操作，确保 NAS 核心数据不受影响。

---

## 🚢 Docker Compose 部署

使用 Docker Compose 方式可快速、优雅地启动服务。

### 📌 部署准备
* 拥有 SSH 权限的飞牛 NAS 系统。
* 获取 Bangumi 的 [个人 Access Token](https://bgm.tv/dev/app)。

### 💡 快速开始

**1. 创建挂载目录与空文件**
建立配置文件夹并初始化存储文件（防止 Docker 误认其为目录）：
```bash
mkdir -p /vol1/docker/fn-bangumi-sync
cd /vol1/docker/fn-bangumi-sync
touch config.json synced.json
```

**2. 编写部署文件**
新建 `docker-compose.yml`，并填入以下参数：
```yaml
services:
  fn-bangumi-sync:
    container_name: fn-bangumi-sync
    image: leclerca/fn-bangumi-sync:latest
    ports:
      - "5000:5000"
    volumes:
      # 只读挂载飞牛底层数据库
      - /usr/local/apps/@appdata/trim.media/database:/db:ro
      # 映射本地配置与记忆库
      - ./config.json:/app/config.json
      - ./synced.json:/app/synced.json
    environment:
      - TZ=Asia/Shanghai
      - DB_PATH=/db/trimmedia.db
    restart: unless-stopped
```

**3. 启动并访问**
```bash
docker-compose up -d
```
服务启动后，通过浏览器访问 `http://NAS的IP地址:5000` 进入管理终端。

---

## 🧭 操作指南

1. **授权绑定**：在系统配置栏填入 Bangumi Access Token。
2. **阈值设定**：自定义判定“已看完”的最低播放百分比（默认 80%）。
3. **精准筛选**：支持按特定飞牛账号或时间范围过滤观看记录。
4. **后台静默**：开启自动同步并设定间隔（1分钟~1小时），系统将接管所有同步任务。

---

## 🖥️ 数据可视化

* **状态看板**：实时输出数据库状态、待同步积压量及上次执行时间。
* **记录矩阵**：自动格式化剧集名称与集数，直观呈现精确到小数点的播放进度。
* **终端回显**：集成 EventSource 推送技术，同步全过程的 API 请求与匹配结果清晰可见。

---

## 💻 技术实现

* **轻量容器**：基于 `Python 3.11-alpine` 极简镜像构建，无冗余依赖。
* **高效驱动**：`Flask` 提供核心路由处理，`APScheduler` 掌控非阻塞定时任务。
* **纯粹前端**：抛弃繁重框架，采用原生 HTML5/ES6 结合 Jinja2 模板直出。

---

## 💝 鸣谢

本项目的挂载思路与安全策略，深受以下开源项目的启发，特此致谢：
* [fntv-record-view](https://github.com/QiaoKes/fntv-record-view) - 优秀的飞牛影视历史管理系统

---

## ⚖️ 许可与免责

本项目基于 [GPL-3.0 License](LICENSE) 协议开源。

本程序仅作为自动化 API 联结工具。核心机制采用纯只读模式，不具备篡改本地媒体文件的能力。用户应自行评估自动化脚本对第三方平台的请求频率风险。开发者不对意外的数据丢失或账号管控限制承担连带责任。
