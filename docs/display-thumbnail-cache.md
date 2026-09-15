# Transparent display thumbnails

Asset JSON now includes optional `thumbDisplayUrl`, alongside the unchanged `thumbUrl`. The display URL points to `/api/assets/{assetId}/thumbnail-display?v={sourceMtimeNs}`. Clients should prefer it for decorative thumbnails, and keep `thumbUrl` for source/reference use.

The endpoint resolves only known public asset records and that asset's own local thumbnail. It does not accept a URL or filesystem path. Unknown/private IDs return 404. Traversal, symlink escape, other asset paths and remote thumbnail URLs cannot enter the processor.

The first image request creates a semantic foreground PNG in `server/exports/display-thumbnails-v1`; later requests reuse a content-hashed cache. Cache identity includes source bytes and helper version. PNG alpha must contain both transparency and visible foreground. The original thumbnail, generated concept images and reconstruction inputs are never changed. Asset listing only adds metadata; it does not run segmentation.

Local macOS uses Apple's Vision foreground mask via a small compiled Swift helper. The helper preserves dark facial details rather than using a brightness/chroma key. It downsamples display output to at most 640 pixels and keeps the original composition. Compilation and inference are serialized and bounded. This fixes iOS Simulator environments where the on-device Vision inference context is unavailable, while actual iOS devices can still use their own Vision path.

No rembg/ONNX packages or weights were present, and none were installed or downloaded. On non-macOS hosts or failed inference, the endpoint returns the untouched original with `X-Craft-Thumbnail: original-fallback`; unsupported requests are negatively cached for five minutes. A portable semantic segmentation backend remains necessary when deploying this helper on Linux.

Verification: five mocked cache/path/API tests and 24 mobile API tests passed. Both existing dog assets returned real RGBA derivatives from the running backend, alpha range 0–255, while their source hashes stayed identical. `X-Craft-Thumbnail: transparent-display` identifies successful semantic output. The source dog images are byte-identical and correctly share one cached derivative.
