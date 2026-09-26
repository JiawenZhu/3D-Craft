# Version 2.5.1 (Build 2026092602) — App Store Release Metadata & What's New

## 1. Release Context
Version 2.5.0 (Build 51) was approved and moved to "Ready for Distribution", closing the 2.5 pre-release train on App Store Connect.
Version 2.5.1 bumps `MARKETING_VERSION` to `2.5.1` and `CURRENT_PROJECT_VERSION` to `2026092602` to start a new TestFlight pre-release train and allow clean Xcode Cloud archive distribution.

## 2. What's New in This Version (此版本的新增功能)

### English (U.S.) — en-US
```text
3D Craft 2.5.1 delivers performance refinements, multi-engine 3D improvements, and character animation updates:

• Multi-Engine 3D Generation & Live Previews: Choose from industry-leading 3D generation engines—including Tripo H3.1, Seed3D 2.0, Rodin Ultra, Hunyuan, HI3D, and Meshy. Inspect real interactive 3D sample meshes, triangle counts, and surface details before you spend Tokens.
• Next-Gen Character Animation Suite: Breathe life into your 2D concepts with cutting-edge video animation models (Atlas MiniMax H3, Seedance 2.5, Seedance 2.0, and Wan 3.0 Prime). Watch full-size video previews side-by-side to pick the perfect motion style.
• Transparent Token Quotes: Real-time, server-verified Token quotes are now clearly displayed for every 3D engine, duration, and resolution before generating. No unexpected token deductions.
• Instant 3D Model Caching: Completed 3D GLB assets are now securely cached on your device per account. Reopen, rotate, and inspect your favorite creations instantly without re-downloading.
• Unified Visual Themes: Lavender and Emerald design themes now flow consistently across all studio tools, community games, and model viewports.
• Developer API v1: Power users and developers can generate personal API keys (craft_live_) directly in the app to orchestrate 3D generations, inspect live quotes, and manage cloud assets programmatically.
• Performance & Reliability: Full export compliance updates, automatic model fallback options, and ultra-fast scene loading.
```

### Simplified Chinese — zh-Hans (简体中文)
```text
3D Craft 2.5.1 带来性能细节优化、多引擎 3D 生成增强及角色动画工坊更新：

• 多引擎 3D 生成与交互式模型预览：全面接入行业前沿 3D 引擎（包括 Tripo H3.1、Seed3D 2.0、Rodin Ultra、混元 Hunyuan、HI3D 与 Meshy）。生成前可直接在 3D 视口中 360° 旋转检视真实样例网格、面数及细节，所见即所得。
• 新一代角色动画工坊：支持 Atlas MiniMax H3、Seedance 2.5、Seedance 2.0 及 Wan 3.0 Prime 多款顶级视频模型。内置全尺寸样例视频对比，动作流畅度一目了然。
• 透明实时 Token 报价：选择不同引擎、时长与分辨率时，系统均会在生成前显示由服务器实时计算的 Token 消耗报价，确认后再提交，扣费清晰透明。
• 本地 3D 模型高速缓存：已生成的 3D 模型采用账号隔离的安全本地磁盘缓存。再次打开时无需重复消耗流量下载，秒级载入、丝滑旋转。
• 统一视觉主题体验：熏衣草（Lavender）与翡翠绿（Emerald）双主题全面打通，在模型工坊、社区游戏与展厅页面保持一致质感。
• 开发者 API v1 开放：高阶创作者与开发者现可在 App 内直接创建专属 live API Key（craft_live_），支持通过标准 HTTP / OpenAPI 接口自动化生成 3D 模型及管理资产。
• 性能与合规性提升：补齐出口合规声明，优化弱网容错重试机制与场景启动速度。
```

## 3. TestFlight "What to Test" Notes (TestFlight 测试说明)

### English (en-US)
```text
3D Craft 2.5.1 focuses on multi-engine model selection, animation previews, and local GLB caching:
1. Model Generation Sheet: Verify the 3D engine selector (Tripo, Seed3D, Rodin, Hunyuan, HI3D, Meshy) and interactive sample 3D mesh rendering.
2. Character Animation Sheet: Test animation generation with Atlas MiniMax H3 and Seedance 2.5, including video comparison previews and token quote updates.
3. Offline / Fast Loading: Verify that previously downloaded 3D GLB models load instantly from disk cache.
4. Settings & Account: Test API key creation and Theme switching between Lavender and Emerald.
```

### Simplified Chinese (zh-Hans)
```text
3D Craft 2.5.1 重点测试多引擎选择、动画预览及本地 GLB 模型缓存：
1. 3D 模型生成页面：测试 3D 引擎选择器（Tripo、Seed3D、Rodin、混元、HI3D、Meshy）及示例 3D 网格的实时旋转与面数显示。
2. 角色动画生成弹窗：测试 Atlas MiniMax H3 与 Seedance 2.5 动画模型、视频对比预览及实时 Token 报价更新。
3. 秒开缓存体验：验证此前已下载的 3D 模型能否直接从本地缓存秒开，无需重复下载。
4. 设置与账号：测试 API Key 创建界面及 Lavender / Emerald 双主题切换的一致性。
```
