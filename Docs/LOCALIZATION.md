# Localization / 国际化

PeerJetty supports English (`en`) and Simplified Chinese (`zh-Hans`). i18n means internationalization: separating interface text from code so the same application can support different languages.

PeerJetty 支持英文和简体中文。i18n 是 internationalization（国际化）的缩写，指把界面文字与程序逻辑分开，让同一个 App 使用不同语言。

## Selecting a language / 选择语言

In PeerJetty's Settings, choose **Follow system**, **English** or **简体中文** under Language. The choice saves automatically on this Mac. Finish current transfers, quit PeerJetty from its menu, and reopen it to apply. Closing the settings window does not quit the menu bar app. The app does not force a restart or change macOS language preferences.

在 PeerJetty 设置中直接选择“跟随系统 / English / 简体中文”，本机自动保存。请先完成传输，通过菜单退出 PeerJetty 再重新打开，语言即生效；关闭设置窗口不等于退出菜单栏 App。不会强制重启或改动 macOS 语言设置。

Follow system uses macOS's preferred language list (including any existing per-app override), falling back to a supported preferred language or English. An explicit app choice takes precedence for PeerJetty-owned UI, menus, notifications and diagnostics. Native file pickers, macOS authorization dialogs and provider-generated errors are still controlled by macOS and may use the system language. Percentages follow regional formats independently of the chosen UI language.

“跟随系统”沿用 macOS 偏好列表（包括已有单应用语言设置），找不到支持的语言时回退英文。应用内指定语言优先控制 PeerJetty 自身界面、菜单、通知和错误；系统文件选择器、授权弹窗及系统生成的错误仍由 macOS 控制，可能使用系统语言。百分比仍按地区格式显示。

The preference uses the app's local UserDefaults key `PeerJettyDisplayLanguage`; it is separate from transfer configuration and never sent to peers. Missing or unsupported stored values follow system. Choosing Follow system removes the override. TranslationCatalog remains immutable per launch, so a preference change cannot leave an active transfer or pairing half-switched.

语言设置单独保存在本机应用偏好里，不传给另一台电脑、不改变身份或接收配置；旧版本没有该字段时默认跟随系统。选择“跟随系统”清除应用自身覆盖。每次启动确定语言，避免一次传输或配对期间混用两种语言。

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

For plural entries, preserve `NSStringLocalizedFormatKey`, variable names and `NSStringFormatValueTypeKey`. English needs `one` and `other`; Simplified Chinese uses `other`. Use integer arguments at call sites. Percentages use the system's regional formatting. Text history dates use DateFormatter with the selected app language. Use native formatters when adding other dates or file-size labels.

数量句子使用原生单复数规则，英文区分单数和复数，中文使用 `other`；保留变量名与类型，调用时传整数。百分比按系统地区格式显示。文本历史时间使用 DateFormatter，跟随应用所选语言；其他日期或文件大小字段新增时也应使用原生格式化器。

New languages require a matching resource folder, Package/Info language declarations, the supported-language list in `TranslationCatalog`, `DisplayLanguage`/the picker, and expanded checks. Add both current translations when introducing a new key. Check layout with long labels, narrow windows, and system text sizes.

新增语言需要同时更新资源、语言声明、`TranslationCatalog` 支持列表、`DisplayLanguage`/选择控件及检查。新增文字必须提供当前两种翻译，并检查较长文字和小窗口的布局。

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
