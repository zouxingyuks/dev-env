# JetBrains 配置

## GoLand backend

`.devcontainer/devcontainer.json` 通过 `customizations.jetbrains.backend` 指定 `GoLand`，让支持该设置的 JetBrains Dev Containers 客户端选择 GoLand backend。现有插件清单继续生效；此设置不安装 Go SDK，项目运行时仍由项目自己的 `mise` 配置管理。

## GitHub Copilot

Dev Container 的插件清单包含 [GitHub Copilot](https://plugins.jetbrains.com/plugin/17718)，ID 为 `com.github.copilot`。插件安装后，需要在 GoLand 中登录拥有 Copilot 使用权限的 GitHub 账号；不要将登录凭据写入 `devcontainer.json`。

## 携带 IDE 设置

在 GoLand 中调整需要的设置后，打开 `.devcontainer/devcontainer.json`，点击左侧 Dev Container 图标，选择 **Add Modified Settings from IDE**。IDE 会将支持的已修改设置添加到 `customizations`；只保留需要随开发环境复现的选项。

**Export Settings** 导出的 `options/*.xml` 等文件是 IDE 设置导出包，不是可直接合并进 `devcontainer.json` 的 JSON 设置。不要将其中的 XML 选项名直接当作 `settings` 键。宿主客户端的语言和信任目录按下面的说明配置。

## 简体中文界面

Dev Container 声明了 JetBrains 中文语言包插件，ID 为 `com.intellij.zh`。当前版本的 JetBrains IDE 通常已经内置并启用了该插件。

在 JetBrains 客户端中选择简体中文：

```text
Settings | Appearance & Behavior | System Settings | Language and Region
```

将 **Language** 设置为 **Chinese (Simplified)**。如果 IDE 提示，按要求重启。

语言选择属于 JetBrains 客户端设置，不是可移植的 Dev Container 设置。

## 信任 `~/items`

Trusted Locations 同样属于 JetBrains 客户端设置。在宿主机中一次性添加 `~/items`：

1. 打开 **Settings | Appearance & Behavior | Trusted Locations**。
2. 添加 `~/items`。
3. 应用变更。

之后 `~/items` 下的项目都会被自动信任。调用方将该宿主目录挂载到容器后，对应的容器路径通常是 `/home/dev/items`。

这里的宿主路径和容器路径有意不同。JetBrains 会先要求客户端信任宿主项目位置，再连接 Dev Container。`dev-env` 的 Compose 文件本身不挂载源码；由调用方决定如何提供源码。

## 官方参考

- [Customizing Dev Container settings](https://www.jetbrains.com/help/go/customizing-devcontainer-json-file.html)
- [Language and region](https://www.jetbrains.com/help/idea/language-and-region.html)
- [Project security](https://www.jetbrains.com/help/idea/project-security.html)
