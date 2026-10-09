# Charred Black 中文版：部署说明

Charred Black 是《燃烧之轮 黄金版》（Burning Wheel Gold）的非官方在线角色燃造器。本分支在上游的基础上完成了汉化：

- 网页界面、游戏数据（背景、人生历程、技能、特质、资源）和导出的角色卡都显示中文。
- 角色卡可导出为网页（`.htm`，浏览器打开即可查看、打印）或 Word（`.docx`，可继续编辑）。原版的 PDF 导出已移除。
- 内部数据仍是英文。汉化版导出的 `.char` 能被上游英文版读入，上游的 `.char` 也能被汉化版读入。
- 部署方式：Docker 容器，监听端口 **7878**。

本文分三部分：服务器上的完整部署步骤、如何更新、HTTPS 反向代理示例。最后是常见问题。

---

## 1. 准备

**服务器**

- 任意 64 位 Linux（Debian / Ubuntu / CentOS 等）。
- 1 核 CPU、512 MB 内存即可。
- 建议预留 2 GB 磁盘，用于镜像和构建缓存。

**软件**

- Git。
- Docker 20.10 或更新版本，以及 Docker Compose v2（命令为 `docker compose`）。

还没装 Docker 的话，可以用官方脚本安装：

```bash
curl -fsSL https://get.docker.com | sh
sudo systemctl enable --now docker
# 可选：让当前用户免 sudo 使用 docker（需重新登录）
sudo usermod -aG docker $USER
```

> **国内服务器**：如果拉取镜像或安装 gem 很慢、甚至失败，请先看第 6 节 Q1。

---

## 2. 从 clone 到启动

```bash
# 1) 获取代码（汉化在 feature/zh-localization 分支）
git clone -b feature/zh-localization https://github.com/VolEurr0Se/charred-black.git
cd charred-black

# 2) 构建并在后台启动
docker compose up -d --build

# 3) 查看状态与日志
docker compose ps
docker compose logs -f --tail=50    # 看到 "has taken the stage on 7878" 即启动成功，Ctrl+C 退出日志
```

**验证**

```bash
curl -I http://127.0.0.1:7878/          # 应返回 HTTP/1.1 200 OK
curl -s http://127.0.0.1:7878/i18n.js | head -c 80   # 应看到 window.CHARRED_I18N = {...
```

浏览器打开 `http://服务器IP:7878/`，界面应为中文。确认一切正常后，建议按第 4 节配置域名和 HTTPS。

**不用 Compose 时**

也可以只用 `docker` 命令：

```bash
docker build -t charred-black-zh .
docker run -d --name charred-black-zh -p 7878:7878 --restart unless-stopped charred-black-zh
```

**只允许反向代理访问**

如果只想让本机的反向代理访问 7878，不对公网开放，把 `docker-compose.yml` 里的端口改为：

```yaml
    ports:
      - "127.0.0.1:7878:7878"
```

**防火墙**

- 直接用 7878 访问：需要放行 7878，例如 `sudo ufw allow 7878/tcp`。
- 使用反向代理：只放行 80 和 443。

---

## 3. 更新

**代码更新**

```bash
cd charred-black
git pull                          # 拉取最新代码（含翻译修订）
docker compose up -d --build      # 重新构建并替换容器
docker image prune -f             # 可选：清理旧镜像
```

**只修改了对照表**

如果只改了 `src/data/i18n/zh-CN/` 下的 JSON，同样执行 `docker compose up -d --build`，对照表会在启动时重新载入。

**合并上游**

上游英文版有新内容时，可以这样合并：

```bash
git remote add upstream https://github.com/modality/charred-black.git   # 只需执行一次
git fetch upstream
git merge upstream/master
python3 tools/i18n_check.py       # 列出新增但尚无中文的条目（这些条目会先显示英文，不会报错）
```

把 `i18n_check.py` 列出的条目补进 `src/data/i18n/zh-CN/terms.json` 或 `ui.json`，再重新构建即可。

**数据安全**

角色数据不保存在服务器上。服务端只在内存里临时缓存待下载的文件，30 秒后清除，所以更新或重启不会丢失任何用户数据。

---

## 4. 反向代理与 HTTPS

下面两种方案任选一种。示例域名 `charred.example.com` 请换成你自己的域名，并先把它的 A 记录指向服务器。

### 4.1 Caddy（推荐：自动申请和续期证书）

**安装**（Debian / Ubuntu）

```bash
sudo apt install -y debian-keyring debian-archive-keyring apt-transport-https curl
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | sudo gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' | sudo tee /etc/apt/sources.list.d/caddy-stable.list
sudo apt update && sudo apt install -y caddy
```

**配置** `/etc/caddy/Caddyfile`：

```caddyfile
charred.example.com {
    encode zstd gzip
    reverse_proxy 127.0.0.1:7878
}
```

**生效**

```bash
sudo systemctl reload caddy
```

Caddy 会自动向 Let's Encrypt 申请证书，并自动把 HTTP 跳转到 HTTPS。

### 4.2 Nginx + Certbot

**安装**

```bash
sudo apt install -y nginx certbot python3-certbot-nginx
```

**配置** `/etc/nginx/sites-available/charred`：

```nginx
server {
    listen 80;
    listen [::]:80;
    server_name charred.example.com;

    # 角色文件上传与 JSON 提交都很小；稍放宽以免误拦
    client_max_body_size 2m;

    location / {
        proxy_pass         http://127.0.0.1:7878;
        proxy_http_version 1.1;
        proxy_set_header   Host              $host;
        proxy_set_header   X-Real-IP         $remote_addr;
        proxy_set_header   X-Forwarded-For   $proxy_add_x_forwarded_for;
        proxy_set_header   X-Forwarded-Proto $scheme;
        proxy_read_timeout 60s;               # 生成角色卡通常不到 1 秒
    }
}
```

**启用并申请证书**

```bash
sudo ln -s /etc/nginx/sites-available/charred /etc/nginx/sites-enabled/
sudo nginx -t && sudo systemctl reload nginx
sudo certbot --nginx -d charred.example.com --redirect -m you@example.com --agree-tos
```

Certbot 会自动在上面的 server 块中加入 443 监听和证书配置，并设置定时续期。可以用 `sudo certbot renew --dry-run` 检查续期是否正常。

**已有证书时**

如果手动管理证书，443 部分可以写成这样：

```nginx
server {
    listen 443 ssl http2;
    listen [::]:443 ssl http2;
    server_name charred.example.com;

    ssl_certificate     /etc/letsencrypt/live/charred.example.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/charred.example.com/privkey.pem;

    client_max_body_size 2m;
    location / {
        proxy_pass http://127.0.0.1:7878;
        proxy_set_header Host $host;
        proxy_set_header X-Forwarded-Proto https;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    }
}
server {
    listen 80;
    server_name charred.example.com;
    return 301 https://$host$request_uri;
}
```

---

## 5. 汉化相关说明（维护者）

**对照表文件**

翻译以对照表实现，文件在 `src/data/i18n/zh-CN/`：

| 文件 | 内容 |
| --- | --- |
| `ui.json` | 界面文字（模板、前端提示、属性问题） |
| `terms.json` | 游戏数据名称与人生历程要求文字 |
| `trait_summaries.json` | 特质效果的**中文摘要**（为原创简述，并非规则书原文译文；导出的角色卡中有标注） |

**回退规则**

- 查不到翻译时一律显示英文原文，不会报错，也不会显示空白。
- `X-wise` 会自动显示为“X通晓”。
- 以逗号连接的资源描述会逐段翻译。

**待审核术语**

术语表以外的译名都记录在仓库根目录的 `pending_terms.csv`，列为：英文、建议译法、出处文件、理由。审核后修改 `terms.json` 中对应的值即可。

**相关工具**

| 命令 | 作用 |
| --- | --- |
| `python3 tools/i18n_check.py` | 检查覆盖率 |
| `python3 tools/i18n_extract.py` | 导出全部待译字符串 |
| `cd src && ruby ../tools/render_sample_export.rb` | 生成示例 `.htm` 与 `.docx` 角色卡，检查排版 |

**导出角色卡**

- 由 `src/lib/sheet_export.rb` 生成，只用 Ruby 标准库（`.docx` 由内置的小型 ZIP 打包器生成），不需要额外的 gem 或字体文件。
- `.htm` 为单文件网页，样式内嵌，可直接打印；`.docx` 使用“微软雅黑”作为中文字体，未安装时 Word/WPS 会自动替换为系统中文字体。
- 两种格式内容相同：角色索引、信念与本能填写栏、属性（含资质）、特性、身体承受度灰阶表、技能、特质（附中文效果摘要）、资源、特性问题。

**切回英文**

把环境变量 `CHARRED_LOCALE` 改为任意不存在的语言（如 `en`），页面与导出的角色卡即回退为英文。

---

## 6. 常见问题

### Q1. 国内服务器构建失败或极慢（拉取 `ruby:2.6.10` 超时，或 `bundle install` 卡住）

**镜像拉取慢**：给 Docker 配置镜像加速器。编辑 `/etc/docker/daemon.json`，加入你可用的加速地址，然后执行 `sudo systemctl restart docker`：

```json
{ "registry-mirrors": ["https://<你的加速地址>"] }
```

**gem 下载慢**：在 Dockerfile 的 `RUN bundle install` 之前加一行，改用 Ruby China 镜像：

```dockerfile
RUN bundle config --global mirror.https://rubygems.org https://gems.ruby-china.com
```

### Q2. 端口 7878 已被占用

用 `sudo ss -ltnp | grep 7878` 查看占用进程。也可以把 `docker-compose.yml` 中的映射改成 `"8080:7878"`：左边是宿主机端口，右边保持 7878 不变。

### Q3. 下载的角色卡或 .char 文件名是 `character.htm` 之类，而不是“姓名 角色卡.htm”

服务器同时发送了 UTF-8 中文文件名（`filename*`）和 ASCII 备用名。个别老旧浏览器或下载工具只认后者，属于正常现象，重命名即可。

### Q4. 打开 .htm 文件是乱码

文件本身是 UTF-8 编码并在页面中声明了编码，用现代浏览器打开即可。如果用记事本等编辑器另存过，可能被改成了其他编码，重新导出即可。

### Q5. .docx 里的字体和网页不一样

`.docx` 指定的中文字体是“微软雅黑”。在 macOS、Linux 或 WPS 中如果没有这个字体，会自动换成系统自带的中文字体，排版内容不受影响。也可以在 Word 里全选后自行换字体。

### Q6. 汉化版的 `.char` 能给用英文版的朋友用吗？

可以。`.char` 里保存的是英文内部名称，与上游完全一致；只有你自己输入的姓名、自定义装备或关系描述才会是中文。反过来，上游英文版的 `.char` 上传到汉化版也会正常显示为中文。

### Q7. 页面上还有个别英文

那是对照表里暂时没有的条目，属于设计上的回退显示，不影响使用。

运行 `python3 tools/i18n_check.py` 可以看到清单，补进 `terms.json` 或 `ui.json` 后重新构建即可。

### Q8. 能否多实例 / 负载均衡？

不建议。角色卡和 `.char` 的下载依赖进程内存中的临时缓存：提交与下载必须落在同一个进程上。单实例完全够用。

### Q9. 如何查看日志、重启、停止？

```bash
docker compose logs -f      # 实时日志
docker compose restart      # 重启
docker compose down         # 停止并删除容器（不影响镜像与代码）
```

### Q10. 容器显示 unhealthy

健康检查会访问 `/i18n.js`。先用 `docker compose logs` 查看是否有启动错误：常见原因是对照表 JSON 被手动改坏。可用 `python3 -m json.tool 文件名` 校验 JSON 格式。

### Q11. 点“Word（.docx）”下载到的却是 .htm

这是浏览器沿用了旧版 `burning.js` 缓存：旧脚本不会把格式传给服务器，服务器只能默认导出网页版。

现在页面会给脚本和样式加版本号（`?v=…`），服务器也要求浏览器每次重新验证静态文件，更新部署后不会再出现这个问题。如果仍遇到，按 Ctrl+F5（Mac 为 Cmd+Shift+R）强制刷新页面即可。
