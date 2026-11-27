# Baro UI / UX 设计规范（Design）

## 1. 视觉语言：精密光学仪器 × 原生 Liquid Glass
- **外层容器唯一玻璃化**：仅主面板最外层容器在 macOS 26+ 应用 `.glassEffect(.regular, in: .rect(cornerRadius: 22))`（macOS 15 降级为 `.ultraThinMaterial`），杜绝内层二次叠加玻璃导致的“玻璃疲劳”。
- **内层 Bento 卡片**：统一采用 `Color.primary.opacity(0.055)` 微透底色 + `0.5pt` 内高光描边（`Color.white.opacity(0.14)` / `Color.primary.opacity(0.08)`），圆角 `14pt`，内边距 `11pt`。
- **字体与数字排版**：全部实时指标强制启用 `.monospacedDigit()`，确保数字刷新时宽度零抖动；主读数使用 `19pt–20pt Semibold rounded/default`，次要标签使用 `10pt–11pt Medium .secondary`。
- **静默语义色板**：
  - 平静态（Calm）：柔和翡翠绿 `#34C759` 点缀，其余保持通透黑白灰；
  - 中载态（Moderate）：琥珀黄 `#FF9F0A`；
  - 高压态（Elevated）：珊瑚红 `#FF453A`；
  - 指标识别色：P-Core（Indigo）、E-Core（Teal）、下载（Cyan/Sky）、上传（Purple/Violet）、功耗（Orange）、电池健康（Mint）。

## 2. 交互体验细节
- **单槽位防遮挡**：整个菜单栏只占用 1 个系统槽位，默认「极简双行」宽度约 `102pt–116pt`。
- **卡片原地展开抽屉**：点击 CPU、内存、功耗/温度、磁盘卡片可就地平滑展开深层细节（全核负载柱状图、内存构成明细、全传感器表、多卷列表），再次点击收起。
- **折线图 Hover Inspect**：鼠标滑过折线图时显示垂直游标线并动态读取历史采样点数值。
- **双形态电池卡**：自动识别本机是否存在内置电池；无电池的台式机显示交流供电与苹果 HID 外设电量，并支持在设置中切换预览笔记本电池完整形态。
