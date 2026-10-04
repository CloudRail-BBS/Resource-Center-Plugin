# discourse-relay-rooms

一个 Discourse 插件：在论坛内展示**联机房实时列表**，数据直接来自中继服务器接口。

> 默认数据源：`http://101.43.41.22:46784/relay/rooms`（CNKD 中继节点）

## 功能

- **独立页面 `/relay-rooms`** — 房间卡片列表，显示房间号、房主、地图、在线人数、状态、已开始时长。
- **双导航入口** — 同时注册到侧边栏 Community 区块与顶部导航栏，兼容 `navigation_menu` 的两种取值。
- **自动轮询 + 手动刷新** — 默认 30 秒（可配置，最小 5 秒）；标签页切到后台时自动暂停轮询以降低服务器压力。
- **状态筛选** — 全部 / 等待中 / 游戏中。
- **复制房间地址** — 一键复制 `www.cnkd.fun/RKCxxx`。
- **发帖工具栏按钮** — 一键把当前房间列表以 Markdown 表格插入帖子正文。
- **管理端状态页** — `/admin/plugins/discourse-relay-rooms`，可查看连接状态、节点名称、房间数、数据更新时间，并测试连通性。
- **服务端缓存** — 默认缓存 10 秒，避免每个访客都打到中继服务器；请求带超时。
- **中英双语** — `zh_CN` 与 `en` 两份完整语言包。
- **明暗主题适配** — 全部使用 Discourse 核心色彩变量，跟随配色方案。
- **无第三方依赖** — 图标为内联 SVG，不依赖 `d-icon` 的版本化路径。

## ⚠️ 安装前必读：本仓库的仓库名与插件名不同

| | 值 |
| --- | --- |
| Git 仓库名 | `Resource-Center-Plugin` |
| **插件名（`# name:`）** | **`discourse-relay-rooms`** |
| **安装目录必须是** | **`discourse-relay-rooms`** |

Discourse 要求**安装目录名与插件名一致**。按仓库名克隆会触发：

```
Plugin name is 'discourse-relay-rooms', but plugin directory is named 'Resource-Center-Plugin'
```

后果不是只有一条警告——`add_admin_route(..., "discourse-relay-rooms")` 会因此找不到插件，**管理页 404**，且 `Discourse.plugins_by_name` 查不到该插件。

（本平台已有一个同类案例：`discourse-cnkd-login` 被克隆成了 `CloudRail-CNKD-Log-In`，日志里就在报这条警告。）

**所以克隆时一定要显式指定目标目录名** —— 见下方命令里的第二个参数。

## 安装

```bash
cd /var/discourse
./launcher enter app
cd /var/www/discourse/plugins
#                                     ↓↓↓ 这个参数不能省
git clone https://github.com/CloudRail-BBS/Resource-Center-Plugin.git discourse-relay-rooms
exit
./launcher rebuild app
```

或在 `containers/app.yml` 中：

```yaml
hooks:
  after_code:
    - exec:
        cd: $home/plugins
        cmd:
          #                                     ↓↓↓ 目录名必须显式指定
          - git clone https://github.com/CloudRail-BBS/Resource-Center-Plugin.git discourse-relay-rooms
```

### 若目录名已经不匹配

不用重新克隆，改名为插件名即可：

```bash
mv /var/discourse/plugins/Resource-Center-Plugin \
   /var/discourse/plugins/discourse-relay-rooms
```

也可以用 `scripts/diagnose-migrate.sh` 的同类思路本地先查一遍：

```bash
# 在本仓库根目录执行，确认目录名与 # name: 一致
python scripts/validate.py
```

### 更新插件

`./launcher rebuild app` **不会拉取新代码** —— `after_code` 里执行的是 `git clone`，目录已存在时克隆直接失败，于是重新编译的仍是旧代码。先 `git pull` 再 rebuild：

```bash
cd /var/discourse/plugins/discourse-relay-rooms && git pull
cd /var/discourse && ./launcher rebuild app
```

## 启用

1. 进入 `/admin/site_settings/category/plugins`（或 `/admin/plugins` → 联机房 → 设置）。
2. 打开 **relay_rooms_enabled**。
3. 按需调整以下设置。

| 设置 | 默认值 | 说明 |
| --- | --- | --- |
| `relay_rooms_enabled` | `false` | 总开关 |
| `relay_rooms_api_url` | `http://101.43.41.22:46784/relay/rooms` | 中继接口地址 |
| `relay_rooms_refresh_seconds` | `30` | 前端自动刷新间隔（秒，5–600） |
| `relay_rooms_show_ingame` | `true` | 是否显示已开局的房间 |
| `relay_rooms_join_link_scheme` | `raw` | `raw` → `http://`；`cnkd` → `cnkd://`（唤起客户端） |
| `relay_rooms_http_timeout` | `8` | 服务端请求中继的超时（秒） |
| `relay_rooms_request_timeout_ms` | `10000` | 浏览器请求本站接口的超时（毫秒） |
| `relay_rooms_cache_seconds` | `10` | 服务端缓存秒数，`0` 表示不缓存 |

## 接口约定

插件读取上游 `data.rooms[]`，用到的字段：

| 字段 | 用途 |
| --- | --- |
| `roomId` / `displayId` / `lookupId` | 房间标识 |
| `status` | `battleroom`（等待中）/ `ingame`（游戏中）；其他值归为「未知」 |
| `hostName` | 房主 |
| `mapName` | 地图标识，见下方解析规则 |
| `playerSize` / `activeConnectionSize` | 容量 / 在线人数 |
| `roomCreateTime` / `lastActivityTime` | 开始时间戳 / 最后活跃时间戳 |
| `joinLink` | 加入地址，如 `www.cnkd.fun/RKC682` |
| `isMod` / `publicRoom` / `customRoom` | 徽章 |

`data.nodeName`、`data.updateTime`、`data.roomCount` 用于页面头部与管理页。

### 地图名解析

`mapName` 有多种形态，插件统一取出**可读名称**并标记来源：

| 原始值 | 解析结果 | 类型 |
| --- | --- | --- |
| `NEW_PATH\|maps2/14P现代中东战争by和平铁锈.tmx` | `14P现代中东战争by和平铁锈` | 自定义 |
| `MOD\|0B3D28…//maps/官方陆战图.tmx` | `官方陆战图` | 模组 |
| `[z;p10]Crossing Large (10p).tmx` | `[z;p10]Crossing Large (10p)` | 未知 |
| `maps/官方陆战图.tmx` | `官方陆战图` | 未知 |

规则：`MOD`/`其他前缀|` 决定类型 → 去掉 `//` 前的内容哈希 → 去目录 → 去 `.tmx`/`.tmz`/`.map` 扩展名。

## 本地校验

改代码后先跑校验，再推仓库：

```bash
npm install                 # 仅需 content-tag
python scripts/validate.py  # 15 项静态检查
bash scripts/selftest.sh    # 证明上述检查确实会失败
ruby scripts/test_parsing.rb  # 用真实数据验证解析逻辑
```

`validate.py` 覆盖的都是**静默失败**场景 —— 插件能加载、日志无报错、功能就是不工作：

- 插件目录名 ≠ `# name:`
- `require_relative` 指向 `app/` 下的文件（`Zeitwerk::NameError` 导致启动失败）
- 引擎用 `after_initialize` + `append` 挂载（直接访问 404）
- 顶层路由用对象形式导出（路由被静默丢弃）
- 父模板缺少 `{{outlet}}`（页面空白）
- 导航项 `name` 与页面根 CSS 类冲突（整个导航栏被撑开）
- 未注册的样式表（静默不生效）、括号不平衡（规则泄漏到全站）
- 失效的 `discourse/...` 导入路径（**整个插件 bundle 被替换成 `throw`**）
- 序列化器声明了没有 reader 的属性（**所有接口一起 500**）
- 缺失的 i18n key、缺失的站点设置标签
- `request.format.html?` 门禁（路由匹配却 404）
- `.gjs` 解析错误（整个 bundle 失效）

`selftest.sh` 会把插件复制到临时目录并逐一注入上述错误，断言 `validate.py` 对**每一个**都报错 —— 只会通过的检查等于没有检查。

## 目录结构

```
discourse-relay-rooms/
├── plugin.rb                        # 元数据、站点设置、资源注册、管理路由
├── config/
│   ├── settings.yml
│   ├── routes.rb                    # 引擎用 draw 挂载（不能放 after_initialize）
│   └── locales/                     # server / client，各含 zh_CN 与 en
├── lib/relay_rooms/                 # 不被 Zeitwerk 接管，必须 require_relative
│   ├── api_client.rb                # HTTP + 超时 + JSON 解析
│   ├── room_presenter.rb            # 地图名/状态/加入链接归一化
│   ├── room_list.rb                 # 过滤、排序、缓存
│   ├── room_serializer.rb           # 普通对象序列化器
│   └── engine.rb
├── app/
│   ├── controllers/relay_rooms/     # pages（HTML 外壳）+ rooms（JSON 接口）
│   └── views/relay_rooms/pages/     # 无 JS / 爬虫可见的真实内容
├── assets/
│   ├── stylesheets/                 # 需显式 register_asset，且必须限定作用域
│   └── javascripts/discourse/       # 自动打包，禁止 register_asset
│       ├── relay-rooms-route-map.js # 函数形式导出
│       ├── components/              # 页面组件 + 内联 SVG 图标
│       ├── controllers|routes|templates/relay-rooms/
│       ├── initializers/            # 导航、编辑器按钮、管理导航
│       └── lib/relay-rooms.js       # 状态归一化、Markdown 表格生成
├── admin/assets/javascripts/        # 管理端单独一棵前端树
└── scripts/                         # validate.py / selftest.sh / check-gjs.mjs
```

## 接口

| 方法 | 路径 | 说明 |
| --- | --- | --- |
| `GET` | `/relay-rooms` | 页面（HTML 外壳，Ember 接管后为 SPA） |
| `GET` | `/relay-rooms/rooms.json` | 房间列表 + meta |
| `GET` | `/relay-rooms/meta.json` | 仅 meta |

接口为公开只读数据，无需登录；插件未启用时返回 404。上游不可达时返回 502。

## 许可

MIT
