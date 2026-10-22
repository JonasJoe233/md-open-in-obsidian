# md-open-in-obsidian

[English](README.md)

在 macOS 上把 Obsidian 设为 Markdown 的默认打开程序后，双击 `.md` 文件只会打开
Obsidian——但停在你上次看的那个标签页，不是你点的那个文件。这个工具让它真的跳到
对应笔记。

## 为什么会这样

这不是设置项的问题。Obsidian 的 `open-file` 处理函数（macOS 双击时 Finder 发出的
Apple Event）只用传入的路径反查文件属于哪个 vault，然后把路径丢掉：

```js
app.on("open-file", function(event, filePath){
  event.preventDefault();
  let resolved = path.resolve(filePath), matched = "";
  for (let id in vaults) {                        // 遍历已注册的 vault
    let vaultPath = vaults[id].path;
    if (resolved.startsWith(vaultPath) && matched.length < vaultPath.length)
      matched = vaultPath;                        // 取最长匹配的 vault 根目录
  }
  matched && openVault(matched);                  // <- filePath 之后再未被使用
})
```

*（从 `Obsidian.app` 主进程 bundle 中提取，v1.13.7；更早版本结构相同）*

而 `obsidian://` URI 处理走的是完全独立的代码路径，那条路径**确实**会跳转到文件。
所以解法不是去配置 Obsidian，而是别把原始文件交给它，改交一个 URI。

## 工作原理

```
Finder 双击
      ↓  odoc Apple Event
MDOpener.app            ← 占用 Markdown UTI，本身不含逻辑
      ↓  argv
md-open-in-obsidian     ← 定位 vault → 发 obsidian:// → 验证 → 重发
      ↓  obsidian://open?path=…
Obsidian 跳转到对应笔记
```

有意思的是验证环节。「Obsidian 已就绪」这件事没有可靠信号：

- `obsidian.json` 里的 `open` 标记在启动后约 0.5 秒就翻成 `true`，远早于窗口能接受
  跳转。按这个信号发 URI 会被静默吞掉。
- 固定 sleep 是猜的，而且为了保险必须往长了猜。

所以这里不预测就绪时机，而是直接读 vault 自己的 `.obsidian/workspace.json`，检查
目标文件是否真的成了活动标签。没落地就再发一次 URI。重发是幂等的，所以循环安全，
且一落地立即退出——通常第一次就成（热启动约 1 秒，冷启动约 3 秒）。

## 安装

```sh
git clone https://github.com/JonasJoe233/md-open-in-obsidian.git
cd md-open-in-obsidian
./install.sh
```

安装到 `~/.local/bin` 和 `~/Applications`——不出 home 目录、不用 `sudo`、除系统自带
Python 3 外无任何依赖。可随时重跑，幂等。

```sh
PREFIX=/opt/homebrew ./install.sh     # 改安装位置
./uninstall.sh                        # 把 .md 还给 Obsidian
NEW_HANDLER=com.microsoft.VSCode ./uninstall.sh
```

## 配置

可选，放在 `~/.config/md-open-in-obsidian/config.json`。每个键也可以用环境变量设置
（`MD_OPEN_FALLBACK_APP` 等）。

```json
{
  "fallback_app": "TextEdit",
  "max_attempts": 6,
  "attempt_timeout": 3.0,
  "poll_interval": 0.25
}
```

`fallback_app` 接管 Obsidian 打不开的文件——不在任何 vault 内的，以及下面提到的
文件名边界情况。设为 `""` 表示什么都不做。

运行日志写在 `~/Library/Logs/md-open-in-obsidian.log`（会自动裁剪）。

## 权限弹窗

macOS 用 TCC 管着 `~/Desktop`、`~/Documents`、`~/Downloads` 三个目录。MDOpener
从不读你的笔记内容——那是 Obsidian 干的——但它要读
`<vault>/.obsidian/workspace.json` 来确认跳转是否落地，正是这次读取触发了
*「MDOpener 想访问您"下载"文件夹中的文件」*。

这个弹窗**每个目录只弹一次**，macOS 会记住你的选择，所以常见配置下总共也就点两三
次、一劳永逸。允许它是范围更小的授权，也是推荐做法。

如果你完全不想看到弹窗，「完全磁盘访问权限」可以一次性覆盖所有目录：

```sh
~/.local/bin/grant-full-disk-access          # 打开对应设置面板并在访达中定位 app
~/.local/bin/grant-full-disk-access --check  # 只报告状态，不做别的
```

这个授权无法脚本化完成——`/Library/Application Support/com.apple.TCC/TCC.db`
属 root，且 SIP 开启时 `tccd` 会拒绝第三方写入，即使用 root 也一样。这个辅助脚本
只做能自动化的部分：报告当前哪些 vault 可读、把系统设置打开到准确的那一页、在访达
里选中 `MDOpener.app` 供拖入。

状态是从 launcher 自己的日志里读的，而不是当场探测——因为 TCC 是按进程算的：一个
恰好拥有完全磁盘访问权限的终端会报告成功，而 MDOpener 实际仍然失败。

不授权只损失验证这一步：笔记照样正常打开，只是日志记成 `OK unverified` 而不是已
确认。

## 让文件列表跟着定位

本工具只负责跳到笔记，不碰 Obsidian 的文件列表。所以侧边栏停在原处，笔记所在目录
可能还是折叠的。这一步发生在 Obsidian 内部，要靠插件，而且要逐个 vault 安装：
Obsidian 没有全局插件。

推荐 [Auto Reveal in Explorer](https://github.com/martinopolo/obsidian-auto-reveal-in-explorer)
（社区插件 id `auto-reveal-in-explorer`）。每次打开文件，它会展开父目录、选中笔记、
滚动到可见位置，键盘焦点留在编辑器里。

不要用每次打开都调文件列表自带 `revealInFolder` 或
`file-explorer:reveal-active-file` 命令的插件。两者都会把焦点移到侧边栏，你没法
马上打字；本工具的验证循环也会把文件列表看成当前标签，一直重发 URI 直到放弃。

## 已知限制

**文件名含 `#` 的会回落到备选程序。** Obsidian 的 URI 解析器用 `decodeURI` 解码，
而 `decodeURI` 按标准不解码保留字符——`%23` 会原样留下，路径于是不存在了。
`?vault=&file=`、`obsidian://vault/<name>/<path>`、双重编码、绕过 `/usr/bin/open`
直接调 `LSOpenCFURLRef` 都试过，全部以同样方式失败。既然重试无法解决，这类文件会
立即交给 `fallback_app`，不做无谓的等待。空格、`&`、`+`、`%` 和非 ASCII 文件名都
正常。

**TCC 保护目录下的 vault 未授权时无法验证。** 如果 vault 位于 `~/Downloads`、
`~/Documents` 或 `~/Desktop`，读取其 `.obsidian/workspace.json` 会返回 `EPERM`
直到授权——即使笔记本身能正常打开。这种情况下 URI 只发一次，日志记为
`OK unverified`，不做盲目重试。参见[权限弹窗](#权限弹窗)。

**`.mdown` / `.mkd` / `.mdtext` 无法接管。** 这些扩展名在 macOS 上没有正式注册的
UTI，只有本机动态生成的，而 LaunchServices 拒绝为动态 UTI 绑定默认程序
（`kLSNotRegisteredErr`）。app bundle 里声明了它们，所以会出现在「打开方式」菜单
中，但没法设为默认。`.md` 和 `.markdown` 共用 `net.daringfireball.markdown`，两者
都正常。

**`.md` 的图标会变。** `MDOpener.app` 是 AppleScript bundle，所以 Finder 会给
Markdown 文件显示它的 droplet 图标。往 `MDOpener.app/Contents/Resources/` 里放一个
`.icns` 并改 `CFBundleIconFile` 即可替换。

## 排查

**还是用旧程序打开。** Finder 按窗口缓存 handler，跑 `killall Finder`。确认系统实际
会用哪个：

```sh
~/.local/bin/set-default-handler --show net.daringfireball.markdown
```

**`install.sh` 报告 handler 没变。** 在较新的 macOS 上，
`LSSetDefaultRoleHandlerForContentType` 会返回 `noErr` 却对某些 UTI 静默拒绝修改。
`set-default-handler` 能识别这种情况，转而直接改
`~/Library/Preferences/com.apple.LaunchServices/com.apple.launchservices.secure.plist`
并重启当前用户的 `lsd`。改动前会先备份（在原文件旁生成 `.bak.<时间戳>`）。如果仍然
失败，恢复备份并提 issue，附上你的 macOS 版本。

**完全没反应。** 看日志。`SKIP not a file` 说明路径没能穿过 Apple Event 传进来；
`FAIL after N attempts` 说明 URI 送到了但笔记始终没成为活动标签，这种值得提 issue。

## 仓库结构

| 路径 | 作用 |
|---|---|
| `bin/md-open-in-obsidian` | 核心逻辑：定位 vault、发送 URI、验证落地 |
| `bin/set-default-handler` | 设置 UTI 的默认程序，含 API 失效时改 plist 的兜底 |
| `bin/grant-full-disk-access` | 按 vault 报告 TCC 状态，并引导完成授权 |
| `src/MDOpener.applescript` | 接收 Finder 事件的 `.app` 的源码 |
| `install.sh` / `uninstall.sh` | 幂等的安装与卸载 |

## 许可

MIT
