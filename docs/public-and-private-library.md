# Public catalog and private creation library

- `scripts/build_public_gallery.py` packages the 20 reviewed records marked `galleryExample` and `visibility: public`. It copies their concept images and GLBs to `public/gallery`, and their JPEG concepts plus manifest into the iOS resource bundle. No user assets are included.
- iOS `PublicGallery.bundled` owns discovery independently of private account caches and studio availability. Signed-out visitors can browse examples; account-required APIs continue to gate creation and personal records.
- `server/showcase.py` derives private items from owner-scoped work and concepts. Each model references up to four concept IDs. Persisted selections are authoritative; older jobs use their project concepts, labeled “Related concepts.” An older model without concepts remains a model-only entry.
- `server/cloud_library.py` syncs two changed records per request. The iOS client continues batches until caught up. Models are content-addressed GLBs in `users/{uid}/models/{sha256}.glb`; document IDs remain stable. The cloud document is saved only after its model upload succeeds.
- Firebase Storage rules require the matching authenticated account for model reads. The web client uses authenticated `getBlob`, never public `getDownloadURL`, and does not publish token-bearing download links. Storage may attach download-token metadata to uploaded objects; tokenless signed-out reads remain denied. Signing out clears the library and open viewer; closing a private viewer revokes its object URL.
- Web `libraryGroups` uses explicit IDs and matching project IDs, never titles, to group models with their concepts. Extra concept sets remain visible. The original workbench renderer is lazy-loaded for rotation, zoom, material/solid/wire views and GLB download.

Verified September 13, 2026: 20 public examples, 64 private records, 21 private GLBs, 20 model records with related concepts. One older model has no saved concept relation. Signed-out private media access returned 403. Website deployed to `https://3d-craft.web.app`; iPhone build installed and launched. Private character-duo rendering was subsequently verified in the user's signed-in Chrome at localhost:3000, together with Sunset lighting, key/environment/exposure adjustment and reset.

## Web viewer and sign-out follow-up

- Storage CORS allows the two production app origins and localhost/127.0.0.1 ports 3000 and 3212 for GET/HEAD. Missing port 3000 caused private downloads to retry until failure. These origins do not bypass owner-only Storage rules.
- Private downloads now bound SDK retries to 20 seconds and the overall wait to 45 seconds, with a visible retry button.
- The web viewer exposes the same five lighting presets and three adjustment ranges as iOS; neutral multipliers are calibrated for the web renderer. The model remains visible while the desktop settings panel scrolls.
- iOS Profile displays the app account email and Sign out directly beneath the profile identity. Sign-out clears credentials and private store state; older refresh failures cannot sign out a newly connected account, and older library responses cannot repopulate the store.
- Web production build passed and Firebase Hosting release completed. Native device build/install passed with the working gateway retained. The user's phone account was not signed out during verification.
