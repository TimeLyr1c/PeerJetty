# Multi-device drop / 多设备投放（1.1.0 candidate）

Settings and the menu's Default sending device submenu share persisted peer IDs. Saving refreshes the destination immediately; failure restores the previous preference. Unpaired discovery selections are not a sending default. File-picker requests lock their peer when the picker opens.

设置和菜单共用默认设备保存入口，失败恢复旧选择。未配对设备只供查看／配对，不暗示成为默认目标。文件选择器打开时锁定目标并显示名字。

A drag freezes a default-first, name/ID-stable list of up to six paired devices, including offline devices. One keeps the old card; 2–3 use one row, 4–6 three columns/two rows. Approximate cells: 170×76pt; gap8, inset12. One glass container; the existing transfer status may occupy a separate lower row. Frozen geometry does not move when connection or default changes. Revoked cells disable immediately.

每次拖拽冻结最多六台设备的位置。多设备仅一层玻璃，间距与阴影不接受投放。离线目标仍走原有五秒连接尝试，不改投其他设备。状态变化不重排，解除配对立即禁用。

The released hit cell locks a peer ID before reading URLs or resolving file promises. Async preparation cannot silently pick up a new default. Explicit tile choice affects this transfer only. Over six: show the default first plus five peers and a hint to change default from the menu and drag again; no pairing-count limit or grid pagination.

普通文件及异步文件承诺都携带松手时的 ID。分区不改变长期默认。超过六台时先在菜单换默认，再重新拖拽；没有限制保存的配对数量。

During update admission waiting, new drops are rejected. Already-admitted promises complete using their locked target and re-arm the engine drain barrier before installation. Actual Air/mini multi-device and visual acceptance remain to be performed; isolated checks are not a substitute.
