"""Public provider-cost estimates, independent of the app's credit ledger.

Unknown endpoints and undocumented add-ons deliberately have no numeric quote.
Published image output rates do not include prompt, reference or thinking tokens.
"""
from datetime import date
from .commerce import policy, usage_quote
from .config import FAL_ENDPOINTS, GEMINI_IMAGE_MODEL, GEMINI_TEXT_MODEL, TRELLIS_RESOLUTIONS, TRELLIS_PRICES

VERIFIED_AT = "2026-09-24"
GOOGLE_SOURCE = "https://ai.google.dev/gemini-api/docs/pricing"


def catalog(today=None):
    today = today or date.today()
    def row(name, unit, price=None, note="", zh="", source="", **extra):
        return dict(name=name, unit=unit, unitUsd=price, note=note, noteZh=zh, source=source, **extra)
    fal = "https://fal.ai/models/"
    atlas = "https://www.atlascloud.ai/models/"
    models = {
        "tripo": row("Tripo H3.1", "generation", .22,
            "Standard geometry · texture · PBR. Low listed price with a very large default mesh; inspect fidelity and mobile weight together.",
            "标准几何形状，包含纹理与 PBR 材质。单次成本低，默认生成高面数网格。", atlas + "tripo-h3.1/image-to-3d",
            texturedUsd=.22, multiUnitUsd=None, multiTexturedUsd=None, facingYaw=90),
        "seed3d": row("Seed3D 2.0", "generation", .353,
            "High subdivision · GLB. ByteDance single-image textured mesh.",
            "字节跳动高细分网格，单图带纹理网格，输出 GLB。", atlas + "bytedance/seed3d-v2.0/image-to-3d",
            texturedUsd=.353, multiUnitUsd=None, multiTexturedUsd=None),
        "hunyuan-rapid": row("Hunyuan Rapid", "generation", .50,
            "Image · PBR on. Faster, lighter Tencent tier with PBR material maps enabled.",
            "腾讯快速档位，启用 PBR 材质贴图，模型更轻量。", atlas + "tencent/hunyuan3d-rapid/image-to-3d",
            texturedUsd=.50, multiUnitUsd=None, multiTexturedUsd=None),
        "hunyuan-pro": row("Hunyuan Pro", "generation", .70,
            "Normal · PBR on · default faces. Higher-detail Tencent tier with a configurable polygon budget.",
            "腾讯专业档位，高细节标准生成，启用 PBR 材质。", atlas + "tencent/hunyuan3d-pro/image-to-3d",
            texturedUsd=.70, multiUnitUsd=None, multiTexturedUsd=None),
        "hi3d-fast": row("HI3D v2.1 Fast", "generation", .425,
            "One image · texture · PBR. Fastest 1536³ tier in the four-model HI3D family.",
            "HI3D 四模型家族中速度最快的 1536³ 档位，包含纹理与 PBR。", atlas + "hi3d/v2.1-fast/image-to-3d",
            texturedUsd=.425, multiUnitUsd=None, multiTexturedUsd=None),
        "hi3d-pro": row("HI3D v2.1 Pro", "generation", .765,
            "One image · texture · PBR. More refinement on the 1536³ HI3D geometry family.",
            "HI3D 1536³ 几何增强档位，包含纹理与 PBR。", atlas + "hi3d/v2.1-pro/image-to-3d",
            texturedUsd=.765, multiUnitUsd=None, multiTexturedUsd=None),
        "hi3d-quality": row("HI3D v3.0 Quality", "generation", 1.105,
            "One image · texture · PBR. 2048³ tier intended to retain fine structures.",
            "2048³ 档位，旨在保留精细结构，包含纹理与 PBR。", atlas + "hi3d/v3.0-quality/image-to-3d",
            texturedUsd=1.105, multiUnitUsd=None, multiTexturedUsd=None),
        "hi3d-master": row("HI3D v3.0 Master", "generation", 5.185,
            "One image · texture · PBR. Highest listed tier.",
            "最高配置档位，包含纹理与 PBR。", atlas + "hi3d/v3.0-master/image-to-3d",
            texturedUsd=5.185, multiUnitUsd=None, multiTexturedUsd=None),
        "meshy-single": row("Meshy v7", "generation", .66,
            "One image · texture · PBR · 2K. Single-image Meshy endpoint with standard texture generation.",
            "单图重建，包含标准纹理生成与 PBR（2K 分辨率）。", atlas + "meshy-v7/image-to-3d",
            texturedUsd=.66, multiUnitUsd=None, multiTexturedUsd=None),
        "meshy-multi": row("Meshy v7 Multi", "generation", .66,
            "One reference in multi endpoint. Multi-image endpoint with standard texture generation.",
            "多视角接口单图参考，包含纹理与 PBR。", atlas + "meshy-v7/multi-image-to-3d",
            texturedUsd=.66, multiUnitUsd=None, multiTexturedUsd=None),
        "rodin": row("Rodin (Ultra)", "generation", .40,
            "Texture and reference views included. HighPack, when enabled, is $1.20 total; it is not enabled here.",
            "包含纹理和参考视角。HighPack 启用时共 $1.20；当前未启用。", fal + "fal-ai/hyper3d/rodin",
            texturedUsd=.40, multiUnitUsd=.40, multiTexturedUsd=.40, highPackUsd=1.20),
        "trellis-2": row("TRELLIS.2", "generation", .30,
            "512p $0.25; 1024p $0.30; 1536p $0.35 per model (5/6/7 units at $0.05). Multi-view uses 1024p at $0.30 total (verified with a three-view request).",
            "单个模型：512p $0.25，1024p $0.30，1536p $0.35（每单位 $0.05，共 5/6/7 单位）。多视角固定 1024p，共 $0.30（已用三视角请求核实账单）。", fal + "fal-ai/trellis-2",
            texturedUsd=.30, multiUnitUsd=.30, multiTexturedUsd=.30),
        "hunyuan3d-2.1": row("Hunyuan 3D 2", "generation", .16,
            "Single image: white mesh $0.16, textured $0.48. Front/back/left multi-view: $0.017 white, $0.051 textured.",
            "单图白模 $0.16，带纹理 $0.48；正面/背面/左侧三图：白模 $0.017，带纹理 $0.051。", fal + "fal-ai/hunyuan3d/v2",
            texturedUsd=.48, multiUnitUsd=.017, multiTexturedUsd=.051),
        "hunyuan3d-2-white": row("Hunyuan 3D 2 · White mesh", "generation", .16,
            "Geometry only, no color or texture. Single image $0.16; front/back/left multi-view $0.017.",
            "白模：仅几何形状，不含颜色或纹理。单图 $0.16；正面/背面/左侧三图 $0.017。", fal + "fal-ai/hunyuan3d/v2",
            texturedUsd=.16, multiUnitUsd=.017, multiTexturedUsd=.017),
        "hybrid": row("Hybrid", "generation", .30,
            "Textured at 1024p: TRELLIS.2 $0.30 + Hunyuan $0.48 = $0.78. Without texture only TRELLIS runs. Multi-view: TRELLIS.2 1024p $0.30 + Hunyuan $0.051 = $0.351.",
            "1024p 带纹理：TRELLIS.2 $0.30 + Hunyuan $0.48 = $0.78。不带纹理仅运行 TRELLIS；多视角：TRELLIS.2 1024p $0.30 + Hunyuan $0.051 = $0.351。", fal + "fal-ai/hunyuan3d/v2",
            texturedUsd=.78, multiUnitUsd=.30, multiTexturedUsd=.351),
        "gemini-3-pro-image": row("Gemini 3 Pro Image · Nano Banana Pro", "image", .134,
            "Per 1K/2K output image. 4K: $0.24. Input $2/M and text/thinking output $12/M tokens are additional.",
            "每张 1K/2K 输出图 $0.134；4K $0.24。另计输入 $2/百万、文字及思考输出 $12/百万 tokens。", GOOGLE_SOURCE,
            fourKUsd=.24, inputPerMillion=2., outputPerMillion=12.),
        "gemini-3.5-flash-lite": row("Gemini 3.5 Flash-Lite", "tokens", None,
            "Billed on actual input and output tokens. Fastest latency for interactive prompt planning.",
            "按实际输入和输出 tokens 计费。针对交互式规划优化超低延迟。", GOOGLE_SOURCE,
            inputPerMillion=.075,
            outputPerMillion=.30),
        "gemini-3.8-flash": row("Gemini 3.8 Flash", "tokens", None,
            "Billed on actual input and output (including thinking) tokens. Introductory rates through Dec 31, 2026.",
            "按实际输入和输出（含思考）tokens 计费。优惠费率截至 2026 年 12 月 31 日。", GOOGLE_SOURCE,
            inputPerMillion=.75 if today < date(2027,1,1) else 1.5,
            outputPerMillion=3.75 if today < date(2027,1,1) else 7.5),
        "seedance-2.5-i2v": row("Seedance 2.5 · Image to video", "video", None,
            "Billed on output pixels: $0.0214 per 1,000 tokens at 480p/720p, where tokens = width x height x seconds x 24 / 1024. "
            "A square 4 s 480p character loop is about $0.46; 16:9 at 720p for 4 s is about $1.85. Audio is off.",
            "按输出像素计费：480p/720p 每 1,000 tokens $0.0214，tokens = 宽 x 高 x 秒 x 24 / 1024。"
            "正方形 4 秒 480p 角色循环约 $0.46；16:9 720p 4 秒约 $1.85。不生成音频。",
            fal + "bytedance/seedance-2.5/image-to-video", perThousandTokensUsd=.0214),
        "minimax-h3-i2v": row("MiniMax Hailuo 02 · Image to video", "video", None,
            "Flat rate: 480p $0.25 (5s), 768p $0.30 (5s). Exceptional facial expression fidelity and accessory rigidity.",
            "按次固定计费：480p $0.25（5秒），768p $0.30（5秒）。面部表情生动自然，配饰物理结构稳定。",
            fal + "minimax/h3/image-to-video", rate480pUsd=.25, rate768pUsd=.30),
        "codex-gpt-image-2": row("GPT Image 2 · ChatGPT account", "account", 0,
            "0 app credits. Uses your own ChatGPT plan; its account limits apply. Only studio-provided generation is charged.",
            "0 App 积分。使用你自己的 ChatGPT 订阅额度，受账户限制；仅工作室提供的生成服务扣费。"),
    }
    expected = {"rodin":"fal-ai/hyper3d/rodin", "trellis-2":"fal-ai/trellis-2", "hunyuan3d-2.1":"fal-ai/hunyuan3d/v2"}
    for key, endpoint in expected.items():
        if FAL_ENDPOINTS.get(key) != endpoint:
            models[key] = row(models[key]["name"], "unknown", note="Configured endpoint has no verified price.", zh="当前配置接口的价格尚未核实。")
    if models["hunyuan3d-2.1"]["unit"] == "unknown":
        models["hunyuan3d-2-white"] = row("Hunyuan 3D 2 · White mesh", "unknown", note="Configured endpoint has no verified price.", zh="当前配置接口的价格尚未核实。")
    if FAL_ENDPOINTS.get("hunyuan3d-2.1-mv") != "fal-ai/hunyuan3d/v2/multi-view":
        for key in ("hunyuan3d-2.1", "hunyuan3d-2-white"):
            models[key].update(multiUnitUsd=None, multiTexturedUsd=None)
    if any(models[k]["unit"] == "unknown" for k in ("trellis-2", "hunyuan3d-2.1")):
        models["hybrid"] = row("Hybrid", "unknown", note="One or more stages have no verified price.", zh="部分阶段价格尚未核实。")
    if FAL_ENDPOINTS.get("trellis-multi") != "fal-ai/trellis-2/multi":
        models["trellis-2"].update(multiUnitUsd=None, multiTexturedUsd=None)
    if models["trellis-2"].get("multiTexturedUsd") is None or models["hunyuan3d-2.1"].get("multiTexturedUsd") is None:
        models["hybrid"].update(multiUnitUsd=None, multiTexturedUsd=None)
    for key, configured in (("gemini-3-pro-image",GEMINI_IMAGE_MODEL),("gemini-3.5-flash-lite",GEMINI_TEXT_MODEL)):
        if configured != key:
            models[key] = row(configured, "unknown", note="Configured model price pending verification.", zh="当前配置模型价格待核实。")
    for key in ("trellis-2", "hybrid"):
        model = models[key]
        if model["unit"] == "generation":
            model["effortUsd"] = {effort: TRELLIS_PRICES[res] for effort, res in TRELLIS_RESOLUTIONS.items()}
            model["effortTexturedUsd"] = {effort: round(usd + (.48 if key == "hybrid" else 0), 2) for effort, usd in model["effortUsd"].items()}
            model["effortCredits"] = {effort: usage_quote([{"id":"model", "providerUsd":str(usd)}])["credits"] for effort, usd in model["effortTexturedUsd"].items()}
    for model in models.values():
        if model["unit"] == "generation":
            for field, rate in (("texturedCredits", "texturedUsd"), ("multiTexturedCredits", "multiTexturedUsd")):
                usd = model.get(rate)
                model[field] = usage_quote([{"id": "model", "providerUsd": str(usd) if usd is not None else None}])["credits"]
    return {"currency":"USD", "verifiedAt":VERIFIED_AT, "kind":"provider_cost_estimate", "models":models, "billingPolicy":policy()}


# Seedance treats a resolution as a pixel budget, not a literal height: at
# "480p" a 1:1 clip comes back 640x640, the same pixel count as 854x480. These
# sizes were measured on delivered clips (the app's own mascot loops are
# 640x640), because the charge follows real output pixels.
HEADROOM = 1.03
ANIMATION_SIZES = {("480p","1:1"):(640,640), ("480p","16:9"):(854,480), ("480p","9:16"):(480,854),
                   ("720p","1:1"):(960,960), ("720p","16:9"):(1280,720), ("720p","9:16"):(720,1280)}
MINIMAX_RATES = {"480p": 0.25, "768p": 0.30, "720p": 0.30}
MINIMAX_SIZES = {("480p", "1:1"): (480, 480), ("768p", "1:1"): (768, 768), ("720p", "1:1"): (768, 768)}
# Native output tiers verified on Atlas's detailed pricing panel on 2026-09-24.
# Enhanced/SR tiers are intentionally excluded from the first app picker.
ATLAS_ANIMATION_RATES = {
    "atlas-seedance-2.0-mini": {"480p": .0112, "720p": .0242},
    "atlas-seedance-2.0": {"480p": .09, "720p": .1935},
    "atlas-seedance-2.5": {"480p": .1397, "720p": .3005},
    "atlas-minimax-h3": {"768p": .08, "2K": .13},
    "atlas-wan-3.0-prime": {"480p": .0612, "720p": .126},
}


def animation_usage(width, height, seconds, model="seedance-2.5-i2v", resolution=None):
    """Cost of a clip that already exists.

    For Seedance, fal bills on output pixels: tokens = w x h x seconds x 24 / 1024.
    For MiniMax Hailuo 02, flat rate applies ($0.25 for 480p, $0.30 for 768p/720p).
    """
    if model in ATLAS_ANIMATION_RATES:
        rate = ATLAS_ANIMATION_RATES[model].get(resolution)
        if rate is None or seconds <= 0:
            return {"totalUsd": None, "usageWithServiceFee": usage_quote([{"id": "animation", "providerUsd": None}])}
        total = rate * seconds
        return {"providerTokens": None, "width": width, "height": height,
                "seconds": round(seconds, 3), "totalUsd": round(total, 6),
                "usageWithServiceFee": usage_quote([{"id": "animation", "providerUsd": f"{total:.6f}"}])}
    if str(model).startswith("minimax"):
        is_hd = max(width or 0, height or 0) > 512
        total = 0.30 if is_hd else 0.25
        return {"providerTokens": None, "width": width, "height": height,
                "seconds": round(seconds, 3), "totalUsd": total,
                "usageWithServiceFee": usage_quote([{"id": "animation", "providerUsd": f"{total:.2f}"}])}

    model_info = catalog()["models"]["seedance-2.5-i2v"]
    rate = model_info.get("perThousandTokensUsd")
    if rate is None or not width or not height or seconds <= 0:
        return {"providerTokens": None, "totalUsd": None,
                "usageWithServiceFee": usage_quote([{"id": "animation", "providerUsd": None}])}
    provider_tokens = width * height * seconds * 24 / 1024
    total = provider_tokens * rate / 1000
    return {"providerTokens": round(provider_tokens), "width": width, "height": height,
            "seconds": round(seconds, 3), "totalUsd": round(total, 6),
            "usageWithServiceFee": usage_quote([{"id": "animation", "providerUsd": f"{total:.6f}"}])}


def animation_quote(resolution="480p", duration=4, aspect="1:1", model="seedance-2.5"):
    """Provider cost and Tokens for one character loop (Seedance 2.5 or MiniMax Hailuo 02)."""
    if model in ATLAS_ANIMATION_RATES:
        rate = ATLAS_ANIMATION_RATES[model].get(resolution)
        seconds = int(duration)
        if rate is None or seconds not in (4, 6) or aspect != "1:1":
            return {"currency": "USD", "kind": "provider_cost_estimate", "model": model,
                    "resolution": resolution, "aspect": aspect, "seconds": seconds, "totalUsd": None,
                    "note": "Price pending verification", "verifiedAt": VERIFIED_AT,
                    "usageWithServiceFee": usage_quote([{"id": "animation", "providerUsd": None}])}
        # Atlas's completed four-second sample files measured about 4.04 seconds.
        # Reserve a small cushion, then settle on the measured output duration.
        total = rate * seconds * HEADROOM
        return {"currency": "USD", "kind": "provider_cost_estimate", "model": model,
                "resolution": resolution, "aspect": aspect, "seconds": seconds,
                "ratePerSecondUsd": rate, "totalUsd": round(total, 6),
                "note": "Native tier; final charge follows measured output length, capped at reserved Tokens.",
                "verifiedAt": VERIFIED_AT,
                "usageWithServiceFee": usage_quote([{"id": "animation", "providerUsd": f"{total:.6f}"}])}
    if str(model).startswith("minimax"):
        canon_res = "768p" if resolution in ("768p", "720p") else resolution
        rate = MINIMAX_RATES.get(canon_res)
        size = MINIMAX_SIZES.get((canon_res, aspect))
        if rate is None or size is None:
            usage = usage_quote([{"id": "animation", "providerUsd": None}])
            return {"currency": "USD", "kind": "provider_cost_estimate", "model": "minimax-h3-i2v",
                    "resolution": resolution, "aspect": aspect, "seconds": 5, "totalUsd": None,
                    "note": "Price pending verification", "verifiedAt": VERIFIED_AT, "usageWithServiceFee": usage}
        width, height = size
        minimax_info = catalog()["models"]["minimax-h3-i2v"]
        usage = usage_quote([{"id": "animation", "providerUsd": f"{rate:.2f}"}])
        return {"currency": "USD", "kind": "provider_cost_estimate", "model": "minimax-h3-i2v",
                "resolution": canon_res, "aspect": aspect, "seconds": 5, "width": width, "height": height,
                "providerTokens": None, "totalUsd": rate,
                "note": minimax_info["note"], "verifiedAt": VERIFIED_AT,
                "usageWithServiceFee": usage}

    size = ANIMATION_SIZES.get((resolution, aspect))
    seconds = int(duration)
    model_info = catalog()["models"]["seedance-2.5-i2v"]
    rate = model_info.get("perThousandTokensUsd")
    if size is None or seconds < 1 or rate is None:
        usage = usage_quote([{"id": "animation", "providerUsd": None}])
        return {"currency":"USD", "kind":"provider_cost_estimate", "model":"seedance-2.5-i2v",
                "resolution":resolution, "aspect":aspect, "seconds":seconds, "totalUsd":None,
                "note":"Price pending verification", "verifiedAt":VERIFIED_AT, "usageWithServiceFee":usage}
    width, height = size
    # Delivered clips run a little past the requested length (4 s comes back as
    # about 4.04 s), and the charge is capped at what was authorized, so the
    # quote carries a small headroom instead of quietly absorbing the excess.
    actual = animation_usage(width, height, seconds * HEADROOM, model="seedance-2.5-i2v")
    return {"currency":"USD", "kind":"provider_cost_estimate", "model":"seedance-2.5-i2v",
            "resolution":resolution, "aspect":aspect, "seconds":seconds, "width":width, "height":height,
            "providerTokens":actual["providerTokens"], "totalUsd":actual["totalUsd"],
            "note":model_info["note"], "verifiedAt":VERIFIED_AT,
            "usageWithServiceFee":actual["usageWithServiceFee"]}


def model_quote(engine, *, texture=True, count=1, views=1, high_pack=False, addons=(), effort="high"):
    if not isinstance(count,int) or count < 1 or not isinstance(views,int) or views < 1:
        raise ValueError("Count and views must be positive integers")
    model = catalog()["models"].get(engine, {})
    base = model.get("multiUnitUsd" if views > 1 else "unitUsd")
    total = model.get("multiTexturedUsd" if views > 1 else "texturedUsd") if texture else base
    if views == 1:
        base = model.get("effortUsd", {}).get(effort, base)
        total = model.get("effortTexturedUsd" if texture else "effortUsd", {}).get(effort, total)
    if high_pack:
        total = model.get("highPackUsd")
    if addons or model.get("unit") != "generation":
        total = None
    return {"currency":"USD", "kind":"provider_cost_estimate", "model":engine, "count":count,
            "views":views, "texture":texture, "highPack":high_pack, "unitUsd":total,
            "totalUsd":round(total*count,6) if total is not None else None,
            "baseUsd":base, "optionsUsd":round(total-base,6) if total is not None and base is not None else None,
            "note":model.get("note", "Price pending verification"), "verifiedAt":VERIFIED_AT,
            "usageWithServiceFee":usage_quote([{ "id":"model", "providerUsd":str(total*count) if total is not None else None }])}
