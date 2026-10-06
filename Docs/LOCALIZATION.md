# Localization / 国际化

PeerJetty 0.3.0 adds English (`en`) and Simplified Chinese (`zh-Hans`). i18n means internationalization: separating interface text from code so the same application can support different languages. The public 0.2.4 installer predates this feature.

PeerJetty 0.3.0 支持英文和简体中文。i18n 是 internationalization（国际化）的缩写，指把界面文字与程序逻辑分开，让同一个 App 使用不同语言。公开的 0.2.4 安装包尚无此功能。

## Selecting a language / 选择语言

The app follows macOS's preferred languages, including a per-app override. Unsupported preferences fall back to English unless another preferred supported language is available. Quit and reopen PeerJetty after changing the preference. No in-app language selector is provided yet.

应用跟随 macOS 的语言偏好，也支持系统为单个应用指定语言。若首选语言不支持，会选择偏好列表中的可用语言，最终回退英文。修改语言后退出并重新打开 App；当前没有应用内语言开关。

In System Settings → General → Language & Region, use the Applications section to choose PeerJetty and its language. See [Apple's instructions](https://support.apple.com/guide/mac-help/change-the-system-language-mh26684/mac).

在系统设置 → 通用 → 语言与地区的“应用程序”区域，为 PeerJetty 指定语言。具体操作见上述 Apple 文档。

## Resource layout / 资源结构

`Sources/PeerCore/Resources/{en,zh-Hans}.lproj/` contains:

- `Localizable.strings`: complete sentences and labels, addressed by stable keys.
- `Localizable.stringsdict`: item-count sentences with native plural rules.
- `InfoPlist.strings`: local network, Downloads and Documents permission explanations.

SwiftPM processes these resources during development. `build.sh` copies the language folders into the App's own Resources directory before signing. An installed App uses these embedded resources, independently of the developer's build folder.

开发时由 SwiftPM 处理资源；打包时将语言目录放进 App 自身并签名，安装后的应用不依赖开发电脑的构建目录。界面、通知和应用自定义错误使用同一套资源。

## Translation rules / 翻译规则

Keep keys stable when editing wording. Translate whole sentences rather than joining translated fragments. For example, `drop.sending_peer` uses `%1$@` for the device name; preserve positional placeholders and their types in every language. Names, file paths and other user data are inserted literally and must never be treated as format templates.

修改文案时保留 key；翻译完整句子，不拼接句子片段。保留 `%1$@` 等参数占位符及类型，允许按语序调整位置。设备名称和文件名是用户数据，不进行翻译，也不能当成格式模板。

For plural entries, preserve `NSStringLocalizedFormatKey`, variable names and `NSStringFormatValueTypeKey`. English needs `one` and `other`; Simplified Chinese uses `other`. Use integer arguments at call sites. Percentages use the system's regional formatting. Dates and file-size labels are not currently displayed; add native formatters when introducing them.

数量句子使用原生单复数规则，英文区分单数和复数，中文使用 `other`；保留变量名与类型，调用时传整数。百分比按系统地区格式显示。目前没有日期或文件大小界面字段，后续增加时再采用对应格式化工具。

New languages require a matching resource folder, Package/Info language declarations, the supported-language list in `TranslationCatalog`, and expanded checks. Add both current translations when introducing a new key. Check layout with long labels, narrow windows, and system text sizes.

新增语言需要同时更新资源、语言声明、`TranslationCatalog` 支持列表及检查。新增文字必须提供当前两种翻译，并检查较长文字和小窗口的布局。

## Diagnostics and compatibility / 错误及兼容

New peers render known rejection diagnostics in their own language using optional error keys and string arguments. The allowlist in `Localization.swift` accepts only known plain-string keys, exact argument counts and fields up to 4,096 UTF-8 bytes. Extend the allowlist when adding a diagnostic and keep the key stable. Protocol v1's legacy text remains present; old peers can read it. Unknown or old diagnostics, and errors supplied by macOS or another provider, retain their original text and may use another language. See [PROTOCOL.md](PROTOCOL.md).

新版按本机语言显示已知拒收原因；旧版继续读取保留的文字字段。未知、旧版及系统提供的错误可能保留原语言。不要翻译协议字段、Bonjour、ALPN、身份标识、设备信任记录或用户数据；显示语言不改变配对及传输权限。

## Checks / 验证

```sh
/usr/bin/python3 Scripts/check-localization.py
./Scripts/test-localization.sh -AppleLanguages '(en)'
./Scripts/test-localization.sh -AppleLanguages '(zh-Hans)'
./build.sh
./Scripts/test-localization.sh --app "$PWD/outputs/PeerJetty.app" -AppleLanguages '(en)'
./Scripts/test-localization.sh --app "$PWD/outputs/PeerJetty.app" -AppleLanguages '(zh-Hans)'
./Scripts/test.sh -AppleLanguages '(en)'
./Scripts/test.sh -AppleLanguages '(zh-Hans)'
```

The flags affect only the check process; they do not modify system language settings. Packaged checks copy resources into an isolated temporary App and verify runtime selection, plural rules and native permission strings without production configuration or Keychain access. Run builds sequentially because they share the SwiftPM cache.

这些参数只影响测试进程。打包检查使用临时 App，不启动正式传输服务、不读日常配置或 Keychain。共享构建缓存，因此顺序执行。自动检查覆盖格式、缺失翻译回退、兼容消息和布局；实体 Mac 一中一英互传、实际权限对话框和通知仍须人工验收。
