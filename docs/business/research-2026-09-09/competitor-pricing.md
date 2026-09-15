# 3D Craft 竞品收费核查

核查日期：2026-09-09。币种：美元。仅使用官方价格页、开发者文档和美国 App Store 页面；未登录结账、未购买。价格可能随地区、促销或账户改变。下列“约多少模型”是厂商估算，不等于质量合格、绑定骨骼且带动画的完整游戏资产。

| 产品 | 已核实价格与额度 | Web / API / 手机的边界 |
|---|---|---|
| Meshy | 免费 100 credits/月；Pro 1,000 credits/月。官方帮助中心将 $20 优惠券描述为一个月 Pro，支持约 $20/月参考价，但主价格卡未被当前网页读取完整，最终金额须结账确认。订阅额度每月重置；购买额度不失效。 | API 使用预付 credits，不应照搬 Web 每次操作费率。API Meshy 6/7 图生 3D 为无贴图 20、带贴图 30、8K 35 credits；Ultra 再加 5。当前读取未确认 API credits 的美元兑换率，不能把 Web 套餐均价作为采购成本。 |
| Tripo | Studio Pro 页面列 $20/月、3,000 credits/月、约 200 模型；年付 $240。Max $90/月、25,000 credits、约 1,660 模型；年付 $1,080。加购 $10/1,000 credits。页面年付折扣标签、月价及“每模型”文案有不一致，正式比较须复核结账。 | API 独立预付：1 credit=$0.01；H 系列图生或多视图带标准贴图 30 credits=$0.30。HD 贴图 +$0.10、HD 几何 +$0.20；自动绑定 $0.25、每个重定向动画 $0.10。API 价格与 Studio“约模型数”分别计量。 |
| Hyper3D / Rodin | Creator $30/月，年付 $288（折合 $24/月），页面估计约 60 模型。Business $120/月，年付 $1,152（$96/月），约 416 模型。直接购买 credit 为 $1.50/credit。 | Creator 不含完整 API；Business 含完整 API。网页支持预览后确认花费、包含一定几何／材质重做额度。约 416 模型不是每次 API 成本保证；当前页面没有给出所有模型版本和 API 操作的逐项兑换表。 |
| Polycam | Basic $30/月或 $150/年（折合 $12.50/月）；Business $400/年/用户；Enterprise $1,200/年/席，至少 3 席。Basic 标注不限对象扫描和 AI captures。 | iOS、Android、Web 均有；这主要是扫描／捕获工具，其“不限”不可推导成我们可无限调用生成 API。Enterprise 列 Content management API，不等于向外转售生成模型 API。仅订阅，无一次性买断。 |
| Customuse | Web Starter $14.99/月、1,000 credits；Pro $35/月、3,000 credits；Studio $99/月、9,000 credits、含 3 席。年付基础档标注减 20%。 | 官网说 Web 订阅绑定账户，可在手机登录使用。API/定制集成在 Enterprise。美国 App Store 列 $6.99、$59.99 等 IAP，但没有明确显示对应周期及额度，不能写成“$6.99/周”。各生成工具耗额不同，公开价格页未列每资产消耗。 |

## 对 3D Craft 的收费含义

1. **$7.99/周是待验证的新套餐，不是已经证明的行业标准。** 本次确认的官网主要是月／年订阅加 credits，未确认上述厂商有等价的公开日订阅；Customuse IAP 金额无法确认周期。可上线周订阅实验，但不能以竞品价格为理由直接承诺无限生成。
2. **用户购买的是可理解的产出组合。** 手机写明“每周包含 X 张概念图＋Y 个标准 3D 资产”，同时提供全部用量明细；桌面按 Token 充值，必须公布每种操作的 Token 价格。概念图与 3D 两步分别确认，不因生成概念就自动扣除 3D 费用。
3. **高精度成本独立建模。** Tripo API 的三张 2K banana2 概念图＋一份带标准贴图 3D，公开基础成本是 $0.30+$0.30=$0.60；若加 HD 几何、HD 贴图则为 $0.90。此计算尚未包括重试、存储、下载流量、支付手续费、支持、税与获客，也未证明其质量达到我们的产品标准。不能把“$0.30/3D”误写成完整工作流成本。
4. **权益应有明确边界。** 标准导出、已有资产重复下载与试玩可以作为套餐权益；重新生成、更高分辨率、重拓扑、绑定、动画等计算任务分别报价。供应商之间 credits 不通兑，产品 Token 应是我们定义的稳定消费单位，并由实际任务账单核对成本。

## 官方直接来源

- [Meshy 价格与额度](https://www.meshy.ai/pricing)
- [Meshy 当前促销说明：$20 对应一个月 Pro](https://help.meshy.ai/en/articles/12224982-current-promotions-and-how-they-work)
- [Meshy API 逐项费率](https://docs.meshy.ai/en/api/pricing)
- [Tripo Studio 价格](https://www.tripo3d.ai/pricing)
- [Tripo API 当前美元与逐项费率](https://developers.tripo3d.ai/en/pricing)
- [Tripo 旧版 API 价格及任务实际 consumed_credit](https://docs.tripo3d.ai/get-started/pricing.html)
- [Hyper3D 价格与 API 档位](https://hyper3d.ai/pricing)
- [Polycam 当前价格](https://poly.cam/pricing)
- [Customuse Web 当前价格](https://customuse.com/pricing)
- [Customuse 美国 App Store 内购列表](https://apps.apple.com/us/app/customuse-ai-3d-creator/id1606479305)

采购前待核：Meshy 当前账户结账金额与 API 美元单价；Tripo 年/月折扣标签及所选模型版本；Rodin 完整 API 费表与包含额度；Customuse iOS 内购周期及每操作消耗。所有竞品商用、转售、客户数据、品牌使用权须按实际签约条款核对，营销页不能代替我们的供应商合同。
