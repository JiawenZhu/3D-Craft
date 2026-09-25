# Video provider comparison · 24 September 2026

Open [the comparison page](index.html) to watch the clips and filter the full resolution/price table. The same five tested clips are bundled in the iOS app as labeled examples. The app now offers these Atlas animation models alongside its existing fal choices; the page itself never starts a generation.

## Controlled sample

- Input: the same 960 × 960 [blue-dragon still](../mascot-animations/source/cloud-dragon-960.jpg) used in the existing mascot study.
- Prompt: the dragon-thinking prompt recorded in [the original generation log](../mascot-animations/seedance-log.json), with the same image supplied as the first and last frame.
- Requested duration: 4 seconds. Audio disabled. Atlas Mini, Seedance 2.0, Seedance 2.5, and Wan Prime ran at their 480p tier; MiniMax H3 ran at its lowest Atlas I2V tier, 768p. All five Atlas predictions completed. Their IDs and local media paths are in [sample-results.json](sample-results.json).
- Baseline: the earlier raw fal Seedance 2.5 [dragon-thinking clip](../mascot-animations/raw/dragon-thinking.mp4). It is shown without the blending applied to the version bundled in the app.
- Observed output: Atlas Mini, Seedance 2.0, and Seedance 2.5 returned 640 × 640 at 24 fps and 4.04 seconds. H3 returned 768 × 768 at 24 fps and 4.46 seconds. Wan returned 640 × 640 at 30 fps and 4.00 seconds. Differences in output size and duration limit direct quality and cost comparisons.
- Account balance moved from $25.000000 to $23.504388 across these five jobs, a $1.495612 decrease. This is an aggregate observation, not a per-job invoice. The rate-card estimate for these outputs totaled approximately $1.5284; provider billing may use a different measured duration or pixel count.

## Interpreting the quality comparison

The page contains all five unedited Atlas MP4 outputs and the unedited fal baseline. Visual assessments are one observation per model, not a statistically meaningful quality score. Examine motion, character fidelity, lighting continuity, and whether the final frame rejoins the first. The page's PSNR values compare the first frame with the middle and final frames of **the same clip**. High first-to-last PSNR only means the end resembles the start; it does not prove visual quality. Low first-to-middle PSNR can indicate desirable motion or unwanted shifts. H3 has more pixels, and Wan has a different frame rate.

The Atlas URLs returned by the service were temporary signed links. They have been replaced by local media in `ios/CraftStudio/Resources/VideoComparisons`; neither those links nor the API credential is stored in this directory.

## Pricing conventions

All table rates are USD per generated second as published on 24 September 2026. A selected 4-, 8-, or 15-second total is simply rate × duration. Atlas Seedance rates came from the live **Price Examples** controls on its [model pricing page](https://www.atlascloud.ai/pricing/models). fal rates came from each linked model page. Two fal Seedance 2.0 entries (480p and 4K) were computed from its published output-pixel token formula; they are labeled “Computed.” They are estimates, not quoted invoices. Square clips can be charged differently than 16:9 examples. Native and super-resolution/enhanced output are different classes. The Atlas Wan pricing panel has a native 4K row that its [specific image-to-video API schema](https://www.atlascloud.ai/docs/more-models/alibaba/wan-3.0-prime-image-to-video/generateVideo) does not accept, so it is excluded.

The comparison is for **image-to-video** APIs. Other tasks, models, duration ranges, resolution availability, promotional credits, and audio settings can have different pricing. Before changing production routing, run multiple seeds on both the blue dragon and green panda, test all three waiting phases, inspect an actual provider invoice, and confirm the iPhone codec/loop/Reduce Motion behavior.

## Product implications

Atlas Seedance 2.5 is the app's default animation choice for local version 2.5 testing: it preserves the character and loop boundary at a lower listed 480p rate than fal in this sample. Seedance 2.0 Mini is cheaper but changed lighting near the seam. MiniMax H3 is cheaper at 768p on fal, despite Atlas being cheaper on most other listed matching tiers. Wan Prime barely animated the requested action in this sample. Users can choose among the supported models and review the Token quote before generating.

Existing Gemini image credits should be used before changing the image generator. Atlas Seedream 5.0 Pro is a different image model that needs subject-preservation tests. Tripo H3.1 was subsequently compared in the [3D study](../image-to-3d-comparison/README.md) and made the default 3D choice for local version 2.5 testing. App Token quotes use the pricing calculation rather than the old descriptive Seedance example.
