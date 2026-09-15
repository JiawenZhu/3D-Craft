# 3D Craft：iOS 计费规则与实施建议

调查日期：2026-09-09。以下区分 Apple 官方规则与本项目的产品建议；上线时仍需按目标 storefront、开发者实际合同及审核反馈复核。价格示例为美元，不是已配置商品。

## 1. 能否按日或按周收费

**自动续订支持每周，不支持每天。** App Store Connect 提供 1 周、1／2／3／6 个月及 1 年周期。日体验若有必要，可设计成一次性小额度购买；它不应冒充每天自动续订，也不应让买下的 credits 在一天后消失。首版建议「周订阅＋一次性补充包」，之后再验证月订阅，避免同时展示过多选择。[Apple：自动续订配置](https://developer.apple.com/help/app-store-connect/manage-subscriptions/offer-auto-renewable-subscriptions)

## 2. 余额与会员到期必须分开

Apple 3.1.1 明确要求 IAP 买到的 credits／虚拟货币不能过期；3.1.2 要求订阅提供持续价值。**项目建议：每次成功付款发放固定额度，已到账的付费额度不过期；取消续订只停止下一次收费和发放，会员服务到当前付费期结束。** 不要把随订阅出售的额度改名「赠送」后按周清零；官方规则没有对这类 AI credits 给出明确例外。若未来要做每周期重置的服务配额，应先确认其实际权益结构，再与持久购买余额分账，不能仅靠免责声明。[Apple：3.1.1、3.1.2](https://developer.apple.com/app-store/review/guidelines/#in-app-purchase)

账本至少区分：付费充值、订阅发放、真正免费促销、任务冻结、成功扣除、失败释放、退款冲正。所有付费余额跨设备保留，技术失败不重复收取用户 credits。过期会员仍能消费已购余额及导出已有资产——这是建议的客户承诺，应写入产品条款并纳入成本测算。

## 3. Web 与 iOS 共用账户

3.1.3(b) 允许多平台服务让用户使用在网站或其他平台取得的内容、订阅和功能，条件包括相关项目也在 App 内以 IAP 提供。3D Craft 可设计统一账户与资产库，但“生成 credits 跨端钱包”的具体商品映射需在审核说明中讲清楚，不能直接假定适用游戏消耗品的全部例子。首版在 iOS 提供 StoreKit 购买；Web 提供按量购买。二者记账渠道不同、扣费规则一致。[Apple：多平台服务](https://developer.apple.com/app-store/review/guidelines/#other-purchase-methods)

美国 storefront 的外部购买链接政策与其他地区不同；部分地区另有 entitlement／合同规则。首版建议不在全球统一显示“去网页更便宜”按钮。按 storefront 控制支付入口，不根据语言或 GPS 猜地区；美国许可不能当作全球许可。[Apple：3.1.1(a)](https://developer.apple.com/app-store/review/guidelines/#link-to-other-purchase-methods)

## 4. 平台抽成如何入账

Small Business Program 需申请并获批，符合条件的新开发者及上年 proceeds 不超过 100 万美元的开发者可适用 15%；还需合并关联开发者账户，超过门槛后后续销售适用标准费率。不能把“现在规模小”直接当成已经享有 15%。[Apple：Small Business Program](https://developer.apple.com/app-store/small-business-program/)

通常合同下，自动续订首个累计付费服务年开发者取得售价的 70%，同订阅组累计一年后为 85%；Small Business 获批后可从第一天取得 85%，均还涉及适用税项。区域特殊合同另算。商业模型同时跑 15% 与 30% 两档：$7.99 × 85% = $6.7915；$7.99 × 70% = $5.593，均是**简化、扣平台费后而未计税／退款／生成成本**的测算。[Apple：订阅 proceeds](https://developer.apple.com/help/app-store-connect/manage-subscriptions/offer-auto-renewable-subscriptions)

## 5. App 内付费墙要明确说什么

Apple 要求购买页写明订阅名、周期、提供内容、显著且本地化的完整续费金额，以及登录或恢复入口；App 和商店资料须包含使用条款与隐私政策。展示年套餐时，实际整年扣款金额必须比折算周价更突出；有试用则写明时长与试用后价格。[Apple：清晰描述订阅](https://developer.apple.com/app-store/subscriptions/#customer-journey)

建议交付文案模板（N、X、Y 待单位经济模型确定）：

> Creator Weekly · $7.99 / week
>
> N creation credits added after each successful payment. Enough for X standard 3D assets and Y concept images with the example settings below.
>
> Renews automatically each week until canceled. Unused paid credits do not expire. Different quality settings use different amounts. Manage or cancel in Apple subscriptions.

中文对应：每周成功付款到账 N 创作点数；在指定质量下可生成 X 个标准 3D 资产及 Y 张概念图；自动续费，可取消，付费余额不过期。不要把“最多 X 个纯 3D”与“X 个完整概念到 3D 流程”混写。旁边提供费用明细、恢复购买、管理订阅、条款、隐私、支持入口。App 运行时读取 StoreKit 本地化价格，不把 $7.99 硬编码给所有国家。

## 6. 支付可靠性与退款

使用 StoreKit 2 验证交易并关联账户，服务端以交易 ID 幂等发放额度。接收 App Store Server Notifications V2，处理续费、到期、退款、退款撤销等状态，并用 Server API 对账；取消自动续订不等于已付款权益立即撤回。`REVOKE` 主要涉及 Family Sharing，不能当作所有退款的唯一信号。[Apple：通知类型](https://developer.apple.com/documentation/appstoreservernotifications/notificationtype)

退款申请交由 Apple 处理，后台收到已确认退款后，对对应未花费额度冲正；已消耗部分依据已公示政策处理，不能悄悄删除不相关资产或重复扣款。系统生成失败退回的是产品 credits，与 Apple 现金退款是两条流程。[Apple：购买与退款支持](https://developer.apple.com/in-app-purchase/)

恢复购买按钮用于可恢复权益；**它不等于把已花掉的消耗型点数重新发一遍**。消耗记录和未用余额由账户服务端账本恢复，换机登录继续可见。验收需包含：成功、取消、pending、重复通知、离线重开、换机、恢复、升级降级、扣款失败、退款与退款撤销。[Apple：购买与恢复](https://developer.apple.com/documentation/storekit/offering-completing-and-restoring-in-app-purchases)

## 建议进入主计划的结论

首版采用原生 IAP 周订阅及补充包，Web 按量购买，统一服务端余额；付费额度不失效；价格页显示套餐真实能完成的工作量；用 30% 抽成也能成立的额度做保守发布方案。是否增加按日一次性包、月订阅，由留存与单位成本实验决定，避免在上线前把 SKU 做复杂。
