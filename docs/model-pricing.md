# Model pricing display

Prices are USD **provider-cost estimates**, separate from the app's existing Token ledger. Token quotes use the existing conversion: ceil(provider USD × 1.15 / $0.01). Quotes are reserved and snapshotted before generation; historical charges are unchanged. HighPack is not enabled.

`server/pricing.py` is the shared catalog. Web reads `GET /api/pricing`; authenticated iOS reads `GET /api/mobile/pricing`. Each record has a unit, nullable rates, explanation and source. Unknown rates remain null, including unverified future models or overridden endpoints. ChatGPT account models use account allowances, not a $0 API quote.

Verified 2026-09-14:

| Current route | Price |
| --- | --- |
| fal-ai/hyper3d/rodin | $0.40/result; texture and reference views included |
| fal-ai/trellis-2 | Single image: 512p $0.25 / 29 Tokens; 1024p $0.30 / 35 Tokens; 1536p $0.35 / 41 Tokens |
| fal-ai/trellis-2/multi | 2–5 consistent views; fixed 1024p $0.30 / 35 Tokens |
| fal-ai/hunyuan3d/v2 | Separate White mesh / 白模 option: $0.16 / 19 Tokens. Textured: $0.48 / 56 Tokens |
| fal-ai/hunyuan3d/v2/multi-view | Exactly front/back/left: white $0.017 / 2 Tokens; textured $0.051 / 6 Tokens |
| Hybrid | Single 1024p: $0.78 / 90 Tokens. Multi-view: $0.351 / 41 Tokens; both provider stages billed |
| Gemini 3 Pro Image | $0.134/1K–2K output image; $0.24/4K output; input $2/M tokens and text/thinking output $12/M additional |
| Gemini 3.8 Flash | Input $0.75/M and output/thinking $3.75/M through 2026-12-31; switches to $1.50/$7.50 on 2027-01-01 |

Rodin HighPack's published total is $1.20. It is informational only until the generator supports an explicit selection. Undocumented add-ons produce no numeric quote. TRELLIS.2 single and three-view 1024p calls both returned GLBs; the signed-in fal usage dashboard showed $0.30 for the multi call. Multi-view is deliberately fixed at the verified 1024p resolution. Hunyuan multi-view prices were verified against the official model page and authenticated unit-pricing API; textured_mesh is three times the white-mesh rate. Unknown endpoint overrides still suppress quotes.

The native image subtotal follows selected count and adds a token-usage note; token spend cannot be fixed upfront. Native 3D confirmation follows selected engine and views. Web direct generation follows texture, batch, and A/B engines. The legacy concept pipeline determines usable views at runtime and can retry; it displays component rates rather than a false fixed total.

Mobile 3D jobs snapshot `providerEstimate` at submission; this is not an invoice or actual usage settlement. Provider invoices remain authoritative.

Sources: [Rodin](https://fal.ai/models/fal-ai/hyper3d/rodin), [TRELLIS.2](https://fal.ai/models/fal-ai/trellis-2), [Hunyuan](https://fal.ai/models/fal-ai/hunyuan3d/v2), [Gemini](https://ai.google.dev/gemini-api/docs/pricing).

Validation: `venv/bin/python -m unittest discover -s tests -p 'test_pricing.py'` covers texture, quantity, known/unknown add-ons, unknown endpoints, account usage, and rate expiry. Native pricing smoke checks never submit generation work.

## Optional details and creation calculator

Technical pricing is now hidden by default behind a persisted preference (iOS `craftShowPriceDetails`, web `craft.showPricingDetails`). Generation confirmation still shows app credit reservations. The native calculator can be opened from the Create header, concept toolbar, model toolbar, confirmation sheet or Profile.

Native usage totals are summed from recorded job `charged` values, scoped to a project or all creations. `reserved` is shown separately for active jobs. Duplicate job IDs are counted once; historical records without charged values are marked as missing and are not estimated retrospectively. Refunded unused reservations are not counted as consumption. Planned image/3D credits are a separate budget and never affect the ledger. USD remains a provider estimate, available inside optional details; this app does not yet record a complete provider-dollar invoice.

The web calculator is a planning tool: no actual dollar ledger is available in that workflow. Its image and reconstruction inputs do not change generation settings or submit jobs.

## Input contracts and white-mesh option

- Rodin: 1–5 images. Multi-view uses concat, with every selected image forwarded.
- TRELLIS.2: single image or 2–5 images of one object; multi uses image_urls, 1024p and model_glb output.
- Hunyuan: single image or exactly front, back and left. Direction labels determine API slots regardless of selection order. White mesh shares this API and forcibly disables textured_mesh.
- Hybrid: same front/back/left requirement, feeding both stages.
- iOS shows reviewed concept-set thumbnails, keeps the primary source selected, and rejects missing, unrelated, duplicate or unusable views before reserving Tokens. White mesh is localized beside its Token cost.
- The legacy hunyuan3d-2.1 ID is retained for saved data; the fal route is supported v2. fal-ai/hunyuan3d-v21 is deprecated and is not selected.

Multi sources: https://fal.ai/models/fal-ai/trellis-2/multi/api and https://fal.ai/models/fal-ai/hunyuan3d/v2/multi-view/api.

Live acceptance on 2026-09-14: Hunyuan three-view white and textured requests both returned GLBs through the actual engine adapters. GLB JSON inspection found zero textures/images in white and one texture/image in textured. fal usage showed 4 billing generations × $0.017 = $0.068 combined, confirming the 1x/3x rates. These bounded provider checks did not charge an app user's wallet. iPhone install sequence 5208 completed and launched successfully; device UI acceptance remains with the user.
