# Version 2.5.2 (Build 2026100102) — App Store Release Metadata & What's New

## 1. Release Context
Version 2.5.1 (Build 53) was approved and moved to "Ready for Sale", closing the 2.5.1 pre-release train on App Store Connect.
Version 2.5.2 bumps `MARKETING_VERSION` to `2.5.2` and `CURRENT_PROJECT_VERSION` to `2026100102` for Xcode Cloud test delivery and comprehensive secret key exclusion.

## 2. What's New in This Version (此版本的新增功能)

### English (U.S.) — en-US
```text
3D Craft 2.5.2 delivers stability enhancements, credential protection, and performance refinements:

• Security & Privacy Hardening: Comprehensive exclusion rules to ensure cloud API credentials and certificates remain strictly protected.
• Multi-Engine 3D Generation: Continuous improvements across Tripo H3.1, Seed3D 2.0, Rodin Ultra, Hunyuan, HI3D, and Meshy engines.
• Character Animation Suite: Smooth motion generation powered by Atlas MiniMax H3, Seedance 2.5, Seedance 2.0, and Wan 3.0 Prime.
• Real-Time Token Quotes: Transparent quote breakdowns before every 3D and animation creation.
• Instant 3D Model Caching: Ultra-fast local GLB caching for seamless offline viewing and 360° inspection.
• Overall Performance & Stability: Enhanced network fault tolerance and accelerated startup times.
```

### Simplified Chinese — zh-Hans (简体中文)
```text
3D Craft 2.5.2 带来安全性加固、证书凭证隔离与稳定性提升：

• 安全与合规性增强：全面强化凭证与私钥安全过滤，确保云端服务与本地运行绝对安全。
• 多引擎 3D 生成持续优化：涵盖 Tripo H3.1、Seed3D 2.0、Rodin Ultra、混元 Hunyuan、HI3D 与 Meshy 引擎的精度与贴图增强。
• 角色动画工坊深度支持：无缝支持 Atlas MiniMax H3、Seedance 2.5、Seedance 2.0 及 Wan 3.0 Prime 动态生成。
• 透明实时 Token 消耗报价：生成前清晰预览 Token 预计消耗，明细精准透明。
• 本地 3D 模型高速磁盘缓存：秒开已下载 GLB 资产，支持 360° 丝滑检视与旋转。
• 启动与网络性能提升：优化弱网重试机制与场景载入速度。
```

## 3. TestFlight "What to Test" Notes (TestFlight 测试说明)

### English (en-US)
```text
3D Craft 2.5.2 focuses on security updates, multi-engine reliability, and offline cache verification:
1. Model Generation & 3D Viewport: Verify 3D generation across available engines with mesh rotation and wireframe view.
2. Character Animation: Test motion generation with video comparisons and real-time quote validation.
3. Offline Caching: Confirm cached GLB models load instantaneously without network requests.
4. Settings & Account: Verify API key management and Lavender/Emerald theme toggles.
```

### Simplified Chinese (zh-Hans)
```text
3D Craft 2.5.2 重点测试安全性更新、多引擎稳定性及离线缓存：
1. 3D 模型生成与视口预览：测试各引擎 3D 模型生成、360° 旋转与网格细节检视。
2. 角色动画工坊：测试动作生成流程、视频对比及实时 Token 报价。
3. 离线缓存秒开：验证已生成模型无需二次网络下载即可快速载入。
4. 设置与账号中心：测试 API Key 管理与 Lavender / Emerald 双主题切换。
```
