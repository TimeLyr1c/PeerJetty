# 许可证选择备忘：待双方决定

更新：2026-10-05。此文件是方案说明，不是正式许可证，不代表原作者已经授权。

目标：允许使用、修改、协作，同时让分发的衍生版本继续给予用户源码与修改自由。

## 主要选择

- MIT：简短宽松；保留版权和许可声明，可以闭源分发衍生产品。
- BSD-3-Clause：类似宽松；还限制借作者/贡献者名字暗示背书，不要求修改版开源。
- Apache-2.0：宽松，明确专利授权与有关终止规则，保留所需声明、标记修改及适用的 NOTICE；不要求修改版开源。
- MPL-2.0：按文件保留开源义务；分发时修改过的受保护文件要提供源码，独立新文件可使用其他许可。
- LGPL-3.0：主要用于库；库的修改与用户重新链接权利有要求，符合条件的使用方程序可以闭源。
- GPL-3.0：强 copyleft；分发受覆盖衍生作品时，整个受覆盖作品及相应源码遵守 GPL。单独独立作品不是因放在同一电脑或同一包里就自动被覆盖。
- AGPL-3.0：在强 copyleft 基础上增加修改版的远程网络交互源码提供义务。

对于当前桌面 App，可以优先讨论 GPLv3；若也希望覆盖别人把修改版做成网络服务的场景，讨论 AGPLv3。

## 实际边界

copyleft（著佐权）是通过许可条件保留用户后续修改和分享自由。它不禁止商业使用、收费或竞争 fork，也不保证 fork 回到我们的仓库提交 PR。
GPL 允许私人修改，源码义务以分发等许可规定的情形为准；AGPL 另有网络交互条件，条文不是仅指网页；若选择 AGPL，需评估局域网交互的适用情况与源码提供入口。没有一种这里推荐的开源许可要求所有私人实验都立即公开 GitHub。
义务通常是向有权获取源码的接收者/用户提供源码，不等于每个修改版必须有一个公开 GitHub 仓库。
独立重写同样功能不自动成为我们的衍生作品；“强 copyleft”不是把开发者所有其他项目都开源。

## 项目应用

决定后确认原作者允许相关源码、图标和工具按选定条款公开；添加完整 LICENSE 与准确版权/来源记录。
如果需要保证后续分发的修改版开源，MIT/Apache 不是该目标的选项。不要把 GPL 与 MIT 双许可理解为更强保护，使用者可能选择宽松的一条。
选择 GPL-3.0-only 还是 GPL-3.0-or-later 也要明确：前者限定该版，后者允许按未来 GNU GPL 版本使用。
已经依有效许可公开的版本通常不能因我们后来改变想法就收回既有许可；未来改变许可还涉及贡献者权利。
AI 辅助开发不代替来源和权利核对；GitHub Contributor、仓库账号与版权归属是不同概念。
图标、商标和项目名称也需明确处理，不把代码许可证当作品牌独占权。

参考原文：
- MIT：https://opensource.org/license/mit
- BSD：https://opensource.org/license/bsd-3-clause
- Apache：https://www.apache.org/licenses/LICENSE-2.0
- MPL：https://www.mozilla.org/en-US/MPL/2.0/FAQ/
- LGPL：https://opensource.org/license/lgpl-3-0
- GPL：https://opensource.org/license/gpl-3.0
- GNU FAQ：https://www.gnu.org/licenses/gpl-faq.en.html
- AGPL：https://opensource.org/license/agpl-3.0
