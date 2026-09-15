# 3D Craft：双主题设计稿

两套配色共 8 张。紫色前三张沿用已认可版本；绿色三张及两个 Profile 页面为本次新增。所有图片都是静态设计稿，并非已完成 App 的截图。

| 页面 | 柔雾紫 | 翡翠绿 |
| --- | --- | --- |
| 创作首页 | [查看](/Users/jiawenzhu/Developer/rodin-3d-studio/docs/design/ios-themes-20260910/lavender-home.png) | [查看](/Users/jiawenzhu/Developer/rodin-3d-studio/docs/design/ios-themes-20260910/emerald-home.png) |
| 概念选择 | [查看](/Users/jiawenzhu/Developer/rodin-3d-studio/docs/design/ios-themes-20260910/lavender-concepts.png) | [查看](/Users/jiawenzhu/Developer/rodin-3d-studio/docs/design/ios-themes-20260910/emerald-concepts.png) |
| 3D 展示 | [查看](/Users/jiawenzhu/Developer/rodin-3d-studio/docs/design/ios-themes-20260910/lavender-studio.png) | [查看](/Users/jiawenzhu/Developer/rodin-3d-studio/docs/design/ios-themes-20260910/emerald-studio.png) |
| Profile 外观设置 | [查看](/Users/jiawenzhu/Developer/rodin-3d-studio/docs/design/ios-themes-20260910/lavender-profile.png) | [查看](/Users/jiawenzhu/Developer/rodin-3d-studio/docs/design/ios-themes-20260910/emerald-profile.png) |

## 实现约定

- 默认柔雾紫；用户主动选择翡翠绿；不收集或推断性别、性取向。
- 相同布局、功能、角色素材；主题仅改变界面颜色。
- 紫色按钮 #D8A1F1，深色字 #302238；绿色按钮 #9CDCC3，深色字 #123428。用代码色值保证精确，生成图仅作视觉目标。
- 图片显示的默认猫属于示例；创作输入应优先显示用户自己的照片。
- 切换即时生效，Reduce Motion 下不做空间动画；选中状态同时有文本及勾选标记。
- 当前只保存设备设置，不声称账号同步。
- 保留中英文界面、真实概念选择、3D 确认、导出与明确点击进入游戏的流程。
- Profile 的 Preview 为无操作的外观示例，不能触发生成或扣费。

## 当前工程状态 · 2026-09-10

已按用户认可的设计更新现有 SwiftUI iOS App：创作首页、概念横向选择、真实 3D 展示、Profile 外观设置及相关确认面板。默认柔雾紫，Profile → Appearance 可切换翡翠绿，立即生效并保存到此设备。中英文界面保留。

本地构建和两条 UI 抽样测试通过：主题切换/重启持久化/中文切换/3D 全屏/游戏选择入口；概念选择/对应生成确认/重启恢复。检查使用现有真实照片和模型，没有触发付费生成。新增轻量按钮按压与主题切换动画，支持 Reduce Motion。

[实际截图](implementation/) 与 [抽样检查记录](../../../ios/design-qa.md) 已保存。设计图是视觉目标，implementation 目录才是实际 App 截图。原生安全区、系统控件、真实项目名称和已有参考照片会与静态设计图不同。

App 已安装并启动到 iPhone 17 Pro 模拟器，可在本地模拟器预览窗口检查。完整真机、多尺寸、全流程生成、支付和游戏内测试留待后续验收；本次没有发布 App 或修改网站。

## 第二轮视觉校准 · 01:03 截图反馈之后

修复首页小猫裁切、状态栏遮挡和概念轮播偏移；调整真实模型取景、柔光、白色底座及页面留白。概念图前置，3D 材质切换/游戏/导出操作常驻底部；Profile 预览改为真实模型。最新[截图与设计对照](polish/)单独保存，早期 implementation 截图保留作历史。当前模型本身仍与生成设计图的毛发、尾巴等细节有差距，本轮没有重新生成资产。
