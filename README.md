# 飞牛番组管家
自动同步飞牛影视观看记录至 Bangumi

[![License: GPL v3](https://img.shields.io/badge/License-GPLv3-blue.svg)](https://www.gnu.org/licenses/gpl-3.0)
[![Docker Pulls](https://img.shields.io/docker/pulls/leclerca/fn-bangumi-sync)](https://hub.docker.com/r/leclerca/fn-bangumi-sync)
---
<img width="2520" height="1344" alt="73180712849576c5a1913fd418e7805a" src="https://github.com/user-attachments/assets/5172549b-8ea3-4321-99fa-9a40687ee27f" />


## 🎯 核心特性

将飞牛影视的观看记录自动同步至 Bangumi追番，以解决飞牛影视缺乏Webhook主动推送功能。

* 🧬 **智能跨季识别**：解决飞牛长篇连载合并与 Bangumi 多季拆分的冲突。
* 🌗 **现代化UI**：自适应网格布局，支持日/夜间模式无缝切换，并提供实时后台日志数据流。
* 🔐 **数据安全**：程序仅读取数据库，零写入操作。

---

## 🚢 Docker Compose 部署

使用 Docker Compose 方式可快速、优雅地启动服务。

### 📌 部署准备
* 拥有 SSH 权限的飞牛 NAS 系统。
* 获取 Bangumi 的 [个人 Access Token](https://next.bgm.tv/demo/access-token)。

### 💡 快速开始

**1. 创建挂载目录与空文件**
首先创建 `config.json` 和 `synced.json`空文件
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
2. **进度设定**：自定义判定“已看完”的最低播放百分比。
3. **精准筛选**：支持按特定飞牛账号或时间范围过同步观看记录。
4. **自动同步**：开启自动同步并设定间隔（1分钟~1小时），系统将接管所有同步任务。

---

## 🖥️ 详细信息显示

* **状态面板**：实时输出数据库状态、待同步积压量及上次执行时间。
* **播放进度**：自动格式化剧集名称与集数，直观呈现精确到小数点的播放进度。
* **终端显示**：集成 EventSource 推送，同步全过程的 API 请求与匹配结果清晰可见。

---

## 💻 技术实现

* **轻量容器**：基于 `Python 3.11-alpine` 极简镜像构建，无冗余依赖。
* **高效驱动**：`Flask` 提供核心路由处理，`APScheduler` 掌控非阻塞定时任务。
* **干净前端**：抛弃繁重框架，采用原生 HTML5/ES6 结合 Jinja2 模板直出。

---

## 💝 鸣谢

本项目的挂载思路深受以下开源项目的启发，特此致谢：
* [fntv-record-view](https://github.com/QiaoKes/fntv-record-view) - 飞牛影视历史管理系统

---

## ⚖️ 许可与免责

本项目基于 [GPL-3.0 License](LICENSE) 协议开源。

本程序仅作为自动化 API 联结工具。采用纯只读模式，不具备篡改本地媒体文件的能力。用户应自行评估自动化脚本对第三方平台的请求频率风险。开发者不对意外的数据丢失或账号管控限制承担连带责任。
