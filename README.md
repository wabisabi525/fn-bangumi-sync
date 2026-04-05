# 飞牛番组管家
飞牛番组管家 - 自动同步飞牛影视观看记录至 Bangumi

## ✨ 核心特性

打造本地 NAS 通往云端追番记录的“最后一公里”，实现飞牛观看、云端秒刷。

* **🚀 智能多季识别**
  针对飞牛刮削器习惯将长篇连载合并为一季（如25集），而 Bangumi 拆分为多季（如12+13集）的差异，独创图谱穿透算法。跨季时自动抓取 Bangumi “续集”并换算相对集数，最高支持连穿 4 季。
* **🛡️ 防缓存机制**
  采用纯后端 Jinja2 服务端渲染 (SSR) 重构前端控制流。彻底终结浏览器表单状态恢复导致的“下拉框永远卡在5分钟”的世界级 Bug。
* **🎨 现代化 UI 设计**
  支持响应式布局与日/夜间模式无缝切换。沉稳的高级灰“重置同步记忆”按钮，完美适配账号换绑场景；实时终端日志流输出，运行状态一目了然。
* **🔒 绝对只读安全**
  全架构基于 `mode=ro`（只读模式）挂载 SQLite 数据库，仅进行数据查询，绝不写入。保证飞牛 NAS 核心数据的绝对安全。

---

## 🐳 Docker Compose 部署（推荐）

使用 Docker Compose 可以最优雅、快捷地部署本系统。

### 前置条件
* 已安装 Docker 与 Docker Compose 的飞牛 NAS 系统。
* 获取 Bangumi 的 [个人 Access Token](https://bgm.tv/dev/app)。

### 部署步骤

**1. 创建应用文件夹**
在您的 Docker 数据盘中建立专属文件夹：
```bash
mkdir -p /vol1/docker/fn-bangumi-sync
cd /vol1/docker/fn-bangumi-sync
2. 配置文件初始化
必须先创建空的配置文件，防止 Docker 启动时将其误认为文件夹：
code
Bash
touch config.json synced.json
3. 创建 docker-compose.yml
新建 docker-compose.yml 文件，并填入以下内容：
code
Yaml
services:
  fn-bangumi-sync:
    container_name: fn-bangumi-sync
    image: 你的DockerHub用户名/fn-bangumi-sync:latest
    ports:
      - "5000:5000"
    volumes:
      # 挂载飞牛影视底层数据库 (只读模式绝对安全)
      - /usr/local/apps/@appdata/trim.media/database:/db:ro
      # 挂载本地配置文件与同步记忆库
      - ./config.json:/app/config.json
      - ./synced.json:/app/synced.json
    environment:
      - TZ=Asia/Shanghai
      - DB_PATH=/db/trimmedia.db
    restart: unless-stopped
4. 启动服务
code
Bash
docker-compose up -d
启动成功后，打开浏览器访问 http://你的NAS_IP:5000 即可进入管理后台。
⚙️ 使用指南
授权连接：在管理界面的【Bangumi 配置】中填入您的 Access Token。
进度阈值：设置“最低观看百分比”（默认 80%），当播放进度达到该值时，系统会将其判定为“已看完”并推送到云端。
筛选机制：支持按特定飞牛用户、特定时间范围（如最近一周、最近一月）精准抓取播放记录。
自动化同步：开启“自动同步”模式，选择时间间隔（1分钟~1小时），系统将在后台静默守护您的追番进度。
📊 界面展示与功能区
统计看板：实时展示数据库连接状态、待同步番剧数量、当前系统运行状态与上次同步时间。
智能记录列表：自动过滤并展示播放时间、智能格式化后的剧名、集数、精准进度百分比以及同步状态。
日志追踪台：通过 EventSource 技术实现的实时滚动日志，同步过程中的网络请求、穿透换算等细节一览无余。
🔧 技术实现架构
后端基建：基于 Python 3.11-alpine 构建极简轻量级镜像。
Web 框架：使用 Flask 提供 RESTful API 与页面渲染服务。
任务调度：集成 APScheduler 实现精准、无阻塞的后台定时轮询。
前端交互：抛弃沉重的框架，采用原生 HTML5 + CSS3 + ES6 配合 Jinja2 模板引擎，实现极速加载与极致流畅的交互体验。
🙏 致谢
本项目的数据库解析结构与只读挂载思路，深受以下优秀开源项目的启发与帮助，在此表示诚挚的感谢：
*fntv-record-view - 优秀的飞牛影视观看历史管理系统
📜 许可说明
本项目采用GPL-3.0 License 开源协议。
免责声明：
本项目仅作为本地数据库与公共 API 之间的自动化联结工具。应用全程采用只读模式运行，不具备修改、破坏或分发任何本地媒体文件的能力。用户使用本工具产生的一切数据同步行为与账号风险由用户自行承担。开发者不对由此引发的任何意外数据丢失或封号承担连带责任。
