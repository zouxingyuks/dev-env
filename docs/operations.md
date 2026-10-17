# 操作指南

## 前置条件

- Docker Engine 或带 Compose v2 的 Docker Desktop。
- 如果通过 GitHub clone 私有仓库，需要 GitHub CLI (`gh`)。
- 使用个人工作区约定时，宿主机需要有 `~/items`。
- 使用 IDE 集成时，需要 JetBrains IDE 或其他 Dev Containers 客户端。

Windows 上建议使用带 WSL2 backend 的 Docker Desktop。宿主工作区需要放在 Docker Desktop 可以共享给容器的位置。不要假设 Linux `$HOME` 表达式在每个 Windows shell 中含义相同；通过选定的调用方或客户端提供源码挂载。

## 启动基础环境

在已 clone 的 `dev-env` 仓库中执行：

```sh
cp .env.example .env
# 在 .env 中填写 TS_AUTHKEY
docker compose build
docker compose up -d
docker compose exec devbox zsh
```

在 Tailscale 管理控制台创建 auth key 时，同时启用 `Reusable` 和
`Ephemeral`，再将 key 填入 `.env` 的 `TS_AUTHKEY`。这会让临时 devbox
在离线后自动从 tailnet 移除；不要使用普通的持久 auth key。

Compose 会启动一个空闲的 `devbox` 和一个 Tailscale sidecar。`devbox` 与
sidecar 共享网络命名空间，因此开发容器中的网络请求可以访问 tailnet。
Tailscale 的状态仅写入 sidecar 的临时文件系统；重建 sidecar 会注册新的
临时节点。Tailscale CLI 和状态检查在 sidecar 中执行：

```sh
docker compose exec tailscale tailscale status
docker compose logs tailscale
```

`devbox` 使用 `privileged: true`，入口脚本自动启动独立的 Docker Engine。
日常 shell 仍以 `dev` 运行，可以直接使用 `docker`、`docker compose` 和 Buildx。
Docker 使用本容器的 Unix socket，不挂载宿主机 Docker socket。
如果 JetBrains 或 Dev Containers 客户端复用了旧容器，必须重建该容器，确保
Compose 中的 `entrypoint` 生效；仅重新连接不会启动新的 `dockerd`。

在容器内验证：

```sh
docker info
docker compose version
docker buildx version
docker run --rm hello-world
docker run --rm -v "$PWD:/workspace:ro" alpine ls /workspace
docker run -d --name docker-smoke -p 8080:80 nginx:alpine
curl --fail http://localhost:8080
docker rm -f docker-smoke
```

bind mount 的源路径是 devbox 内路径。发布的端口可以在 devbox 内通过
`localhost` 访问；远程通过 Tailscale 地址访问，宿主机 localhost 不会自动转发。
由于 devbox 与 Tailscale 共享网络，避免发布到 Tailscale 已使用的端口。

Docker 状态独立保存在 `/var/lib/docker` 和 `/var/lib/containerd` 对应的
`personal-devbox-docker`、`personal-devbox-containerd` volumes 中。
`docker compose down` 保留这些状态；`docker compose down -v` 会连同 home
一起删除。启动失败时使用 `docker compose logs devbox` 查看 daemon 日志。

Compose service 不会 clone 项目，也不会选择项目工作区，这是有意的边界。

停止容器但保留持久化状态：

```sh
docker compose stop
```

删除容器但保留 home 和 Docker volumes：

```sh
docker compose down
```

除非确实要删除 home 和全部 Docker 数据，否则不要使用 `docker compose down -v`。

## 注入环境变量

个人凭据和机器相关变量通过 `.env` 文件注入容器，`.env` 不纳入 git 管理，本仓库只提供 `.env.example` 作为模板：

```sh
cp .env.example .env
```

`docker-compose.yml` 通过 `env_file` 读取 `.env`，并设置 `required: false`，所以缺少 `.env` 时仍可正常构建和启动。变量会作为容器进程的环境变量存在，容器内的 shell、`mise` 任务和工具都能读取。

也可以继续用 `.env` 为 Compose 提供 `USER_UID`、`USER_GID` 等构建参数。

不要在 `.env.example`、Compose 文件、Dockerfile 或任何提交到 git 的文件中写入真实 secret。

## 提供项目源码

调用方负责提供源码。使用个人工作区约定时，可以先把项目 clone 到宿主机 `~/items`，再挂载到容器的 `/home/dev/items`：

```text
~/items/<project>  ->  /home/dev/items/<project>
```

之后由调用方把需要开发的项目目录设置为 IDE 工作区。基础 `dev-env` Compose 文件不会写死该挂载，因此也可以配合其他源码提供方式使用。

## 首次应用 dotfiles

镜像包含 `chezmoi`，但 `docker build` 阶段绝不会访问私有 dotfiles 仓库。源码仓库在容器内可用后，显式初始化并应用：

```sh
chezmoi init --source "$HOME/items/dotfiles"
chezmoi apply --source "$HOME/items/dotfiles"
```

如果 dotfiles 源码是私有仓库且没有通过挂载目录提供，需要先配置 Git 或 SSH 认证，再执行 `chezmoi init`。不要把 token 写进 `Dockerfile`、Compose 文件或 Git 仓库。

已有 dotfiles 仓库继续负责 `.zshrc`、`.zshenv`、插件、alias、prompt 配置和 `mise activate`。

## 使用 `mise` 管理项目工具

项目仓库负责自己的工具声明：

```text
<project>/mise.toml
<project>/mise.lock
```

进入项目目录后执行：

```sh
mise trust
mise install
```

只信任你理解其来源和命令的配置。基础镜像必须确保 `mise` 的 data、config、cache 和 state 目录都可由 `dev` 写入；这些目录放在 `/home/dev` 下更合适，因为该 home 是持久化 volume。

## 验证清单

构建或升级后执行：

```sh
docker compose config --quiet
docker compose build
docker compose up -d
docker compose exec -T devbox sh -lc \
  'id; pwd; command -v mise; command -v chezmoi; zsh --version'
```

另外确认：

- 日常命令以 `dev` 运行；入口管理进程和 `dockerd` 以 root 运行。
- `dev` 可以直接执行 `docker info`、Compose 和 Buildx，嵌套容器可启动。
- `/home/dev` 可由 `dev` 写入。
- `mise` 的 data、config、cache 和 state 目录可写。
- 不访问私有 dotfiles 仓库时，`chezmoi` 也可以正常使用。
- 调用方提供的项目路径在容器内的预期位置可见。
- `.env` 中的变量在容器内可用，且缺少 `.env` 时构建和启动不报错。
- `tailscale` sidecar 使用 `/dev/net/tun`、`NET_ADMIN` 和 `NET_RAW`，并且
  `devbox` 使用其网络命名空间。
- 使用 `Reusable` + `Ephemeral` auth key 时，Tailscale 节点在离线后自动清理。
- 重建容器不会删除持久化 home volume。
- 重建容器不会删除 Docker data volumes，已有镜像和 volumes 仍可使用。
- JetBrains 可以以 `dev` 用户连接 Compose service。

## 已知坑

### 在构建镜像时安装私有 dotfiles

这会失败，因为构建镜像时没有用户的 GitHub 或 SSH 凭据。镜像中只安装 `chezmoi`，等运行时凭据或源码挂载可用后再应用 dotfiles。

### 把 `mise` 状态写入 root 拥有的系统目录

以 root 安装二进制，不代表非 root 的 `dev` 用户可以写入 data 和 cache。运行时目录应放在 `/home/dev` 下，并且每次修改镜像后都要以 `dev` 身份验证。

### 把容器路径当成宿主路径

JetBrains Trusted Locations 在宿主客户端配置。应该信任宿主路径 `~/items`；在容器内信任 `/home/dev/items` 不会配置宿主 IDE。

### 让基础镜像绑定某一个项目

不要仅仅因为当前项目需要，就把语言运行时、项目依赖、源码挂载或固定工作区加入基础镜像。把它放到项目仓库或调用方配置中。

### 依赖 `latest`

固定镜像使用的 `mise` 和 `chezmoi` 版本。版本升级要作为环境变更审查，修改版本参数后重新构建。

## 升级流程

1. 一次只修改一个版本或一个分层。
2. 验证基础镜像或安装器变更时，使用 `docker compose build --no-cache`。
3. 以 `dev` 用户执行验证清单。
4. 重新测试 dotfiles 初始化，以及一个代表性项目的 `mise install`。
5. 检查 JetBrains 连接和工作区行为。
6. 将新的兼容性约束或失败原因记录到本文档。
7. 将 Dockerfile、配置和文档一起提交。
