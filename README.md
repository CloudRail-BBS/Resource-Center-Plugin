# Resource-Center-Plugin

一个 Discourse 插件：在论坛内展示**联机房实时列表**，数据直接来自中继服务器接口。

> 默认数据源：`http://101.43.41.22:46784/relay/rooms`（CNKD 中继节点）

## 功能

- **独立页面 `/relay-rooms`** — 房间卡片列表，显示房间号、房主、地图、在线人数、状态、已开始时长。
- **双导航入口** — 同时注册到侧边栏 Community 区块与顶部导航栏，兼容 `navigation_menu` 的两种取值。
- **自动轮询 + 手动刷新** — 默认 30 秒（可配置，最小 5 秒）；标签页切到后台时自动暂停轮询以降低服务器压力。
- **状态筛选** — 全部 / 等待中 / 游戏中。
- **复制房间地址** — 一键复制 `www.cnkd.fun/RKCxxx`。
- **发帖工具栏按钮** — 一键把当前房间列表以 Markdown 表格插入帖子正文。
- **管理端状态页** — `/admin/plugins/Resource-Center-Plugin`，可查看连接状态、节点名称、房间数、数据更新时间，并测试连通性。
- **服务端缓存** — 默认缓存 10 秒，避免每个访客都打到中继服务器；请求带超时。
- **中英双语** — `zh_CN` 与 `en` 两份完整语言包。
- **明暗主题适配** — 全部使用 Discourse 核心色彩变量，跟随配色方案。
- **无第三方依赖** — 图标为内联 SVG，不依赖 `d-icon` 的版本化路径。

## 命名：仓库名 = 插件名 = 安装目录名

| | 值 |
| --- | --- |
| Git 仓库名 | `Resource-Center-Plugin` |
| 插件名（`# name:`） | `Resource-Center-Plugin` |
| 安装目录名 | `Resource-Center-Plugin` |

**三者完全一致**，所以 `git clone` 不带目标目录参数就能得到正确的目录名，不会再出现名字漂移。

Discourse 要求安装目录名与 `# name:` 一致，否则会打印：

```
Plugin name is 'X', but plugin directory is named 'Y'
```

更关键的是，核心对**两个不同的值**分别做了索引：

| 用途 | 取值 |
| --- | --- |
| `AdminPluginSerializer#id`（管理端插件列表、`api.setAdminPluginIcon`、`api.addAdminPluginConfigurationNav`） | **目录名**（`directory_name`） |
| `Discourse.plugins_by_name[...]`（`add_admin_route` 的 location 查表） | 插件名，并额外把目录名作为别名登记 |

也就是说：管理端导航是按**目录名**注册的，而 `add_admin_route` 是按**插件名**查表的。两者不一致时，很容易把管理导航注册到一个名字下、页面却去另一个名字里找。三者统一后这个问题从根上消失了。

## 安装

```bash
cd /var/discourse
./launcher enter app
cd /var/www/discourse/plugins
git clone https://github.com/CloudRail-BBS/Resource-Center-Plugin.git
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
          - git clone https://github.com/CloudRail-BBS/Resource-Center-Plugin.git
```

### 若目录名曾经不匹配

历史版本叫 `discourse-relay-rooms`。如果服务器上已经装过，改名为仓库名即可：

```bash
mv /var/discourse/plugins/discourse-relay-rooms \
   /var/discourse/plugins/Resource-Center-Plugin
```

`app.yml` 里 `after_code` 的 `git clone` 目标目录也要一并去掉（或改成新名字），否则下次重建会克隆出第二个目录。

改名后可以先本地确认一遍三者一致：

```bash
# 在本仓库根目录执行；会检查 # name: 与所在目录名是否相同
python scripts/validate.py
```

### 更新插件

`./launcher rebuild app` **不会拉取新代码** —— `after_code` 里执行的是 `git clone`，目录已存在时克隆直接失败，于是重新编译的仍是旧代码。先 `git pull` 再 rebuild：

```bash
cd /var/discourse/plugins/Resource-Center-Plugin && git pull
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
python scripts/validate.py  # 19 项静态检查
bash scripts/selftest.sh    # 证明上述检查确实会失败（23 个注入用例）
ruby scripts/test_parsing.rb  # 加载真实实现 + 真实数据验证解析逻辑
```

`validate.py` 覆盖的都是**静默失败**场景 —— 插件能加载、日志无报错、功能就是不工作：

- 插件目录名 ≠ `# name:`
- **`PLUGIN_NAME` 被使用但未定义** —— 核心不提供该常量，见下方「启动失败的两个陷阱」
- **`lib/` 下的文件继承 Zeitwerk 加载的 app 类**（`ApplicationSerializer` 等）
- **序列化器不在 `app/serializers/` 下**
- **Engine 缺少 `engine_name`**；`lib/` 文件名与所定义常量不匹配
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

## 启动失败的三个陷阱

这三个坑都**不会**在开发环境暴露，只在生产 `./launcher rebuild` 时炸，而且报错信息指向错误的方向。

### 1. `PLUGIN_NAME` 不是核心提供的常量

`Plugin::Instance#activate!` 执行的是 `instance_eval File.read(path), path`，核心**没有**定义 `PLUGIN_NAME`（在 `lib/plugin/instance.rb` 里 grep 零命中）。官方骨架自己定义它：

```ruby
module ::RelayRooms
  PLUGIN_NAME = "Resource-Center-Plugin"
end

require_relative "lib/relay_rooms/engine"
```

顺带一个容易踩的细节：`plugin.rb` 是**字符串求值**的，顶层 cref 是 `Object`。所以在 `plugin.rb` 里裸写 `PLUGIN_NAME` 会去找 `::PLUGIN_NAME` 而不是 `RelayRooms::PLUGIN_NAME`——要写 `::RelayRooms::PLUGIN_NAME`。在 `module ::RelayRooms` 内部（如控制器、engine）裸写才是对的。

漏掉会怎样：`requires_plugin PLUGIN_NAME` 抛 `NameError`。而 `plugin.rb` 是在 `config/application.rb` 里被求值的 —— **早于 `Rails.application.initialize!`** —— 于是这个异常被 `Plugin.initialization_guard` 捕获，打印

```
You are unable to start Discourse due to errors in the plugin at
/var/www/discourse/plugins/<目录名>
```

然后 **`exit 1`**。这个 `exit 1` 又会让紧接着的 `rake db:migrate` 失败，报成：

```
Pups::ExecError: cd /var/www/discourse && su discourse -c 'bundle exec rake db:migrate' failed
```

**两条报错是同一个事件**，不要去查迁移文件。

注意 `engine.rb` 里的 `engine_name PLUGIN_NAME` 是在**类体求值**时解析的，所以定义必须放在 `require_relative` **之前**。

### 2. 继承 app 类的文件不能放在 `lib/`

`lib/` 里的文件由 `plugin.rb` 用 `require_relative` 加载，也就是**在 Zeitwerk 建立之前**。所以：

```ruby
# lib/relay_rooms/room_serializer.rb —— 会炸
class RoomSerializer < ::ApplicationSerializer
# NameError: uninitialized constant ApplicationSerializer
```

结论：**序列化器放 `app/serializers/<命名空间>/`**，交给 Zeitwerk 在启动后加载。核心插件都是这么做的（`discourse-solved`、`discourse-data-explorer`）。同理，任何继承 `ApplicationController`、`ActiveRecord::Base` 的文件都必须放 `app/`。

### 3. `plugin.rb` 不能出现裸 `#` 行

这条最阴：报错完全指向核心，不指向你。

`lib/plugin/metadata.rb` 的 `parse_line` **没有 nil 保护**：

```ruby
def parse_line(line)
  line = line.strip
  unless line.empty?
    return false unless line[0] == "#"
    attribute, *value = line[1..-1].split(":")
    value = value.join(":")
    attribute = attribute.strip.gsub(/ /, "_").to_sym   # ← 就是这行
  end
  true
end
```

当某行去掉空白后**正好是 `#`** 时：

| 步骤 | 结果 |
| --- | --- |
| `"#"[1..-1]` | `""` |
| `"".split(":")` | `[]`（Ruby 会丢掉尾部空字段） |
| `attribute, *value = []` | `attribute = nil` |
| `nil.strip` | **`NoMethodError`** |

后果是 `rake db:migrate` 直接中止：

```
NoMethodError: undefined method 'strip' for nil (NoMethodError)
      attribute = attribute.strip.gsub(/ /, "_").to_sym
/var/www/discourse/lib/plugin/metadata.rb:50:in 'Plugin::Metadata#parse_line'
/var/www/discourse/lib/plugin/instance.rb:111:in 'Plugin::Instance.parse_from_source'
/var/www/discourse/lib/plugin/instance.rb:102:in 'block in Plugin::Instance.find_all'
...
```

**为什么特别难查**：`Plugin::Metadata.parse` 是在 `Plugin::Instance.find_all` 里调用的，**早于任何插件的激活**。所以堆栈里全是 `lib/plugin/` 和 `config/application.rb`，**一个插件名都没有**，看起来像核心自己的 bug。

几个要点：

- **只有 `plugin.rb` 会被这样解析**（`parse_from_source` 里 `File.read` 的是 `plugins/*/plugin.rb`）。其他 `.rb` 文件里的裸 `#` 是正常 Ruby 注释，无害。
- **不只是 `#`**：`#:`、`#::` 同样会炸（`":".split(":")` 也是 `[]`）。所以用「grep 裸 `#`」来检查是不够的。
- **空行是安全的**：`parse_line` 对空行返回 `true`，会继续往下读。
- **带内容的注释是安全的**：`# ---`、`# (continued)` 都行，因为 `---` 不是已知字段。
- 三个官方插件（`discourse-solved`、`discourse-data-explorer`、`docker_manager`）里裸 `#` 行数都是 **0**，这就是应当遵循的惯例。

`scripts/validate.py` 里第 19 项检查会**复刻 `parse_line` 的逻辑**（而不是 grep）逐行验证 `plugin.rb`，`scripts/selftest.sh` 也用 `#` 和 `#:` 两种注入证明它确实会失败。

**给其他插件做体检**：

```bash
grep -rn '^#[[:space:]]*$' /var/discourse/plugins/*/plugin.rb
```

## 目录结构

```
Resource-Center-Plugin/
├── plugin.rb                        # PLUGIN_NAME 定义、元数据、站点设置、资源注册、管理路由
├── config/
│   ├── settings.yml
│   ├── routes.rb                    # 引擎用 draw 挂载（不能放 after_initialize）
│   └── locales/                     # server / client，各含 zh_CN 与 en
├── lib/relay_rooms/                 # 不被 Zeitwerk 接管，必须 require_relative
│   ├── version.rb                   # 文件名必须匹配常量 Version
│   ├── api_client.rb                # HTTP + 超时 + JSON 解析
│   ├── room_presenter.rb            # RoomPresenter：地图名/状态/加入链接归一化
│   ├── room_list.rb                 # 过滤、排序、缓存
│   └── engine.rb                    # engine_name PLUGIN_NAME + isolate_namespace
├── app/                             # Zeitwerk 在启动后加载 —— 可安全继承 app 类
│   ├── controllers/relay_rooms/     # pages（HTML 外壳）+ rooms（JSON 接口）
│   ├── serializers/relay_rooms/     # room_serializer.rb（继承 ApplicationSerializer）
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
