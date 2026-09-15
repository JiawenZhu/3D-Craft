# Distribution validation fixes

Source: `CraftStudio_2026-09-14_18-58-28.992.xcdistributionlogs` supplied by the developer. Historical logs are preserved unchanged.

## Findings

- **90474 — iPad multitasking orientations:** the rejected archive omitted upside-down portrait. `ios/project.yml` now supplies all four orientations under `UISupportedInterfaceOrientations~ipad`, retaining the existing iPhone orientations. XcodeGen regenerates the app's Info.plist from that source.
- **90534 — unsupported SDK/Xcode:** the rejected archive was built with Xcode `27A5218g` and iOS SDK `24A5380g`, an early beta. Changing the archive metadata cannot fix this; create a new archive with an Apple-supported release or RC. Apple's release page lists Xcode 27 `27A266a` on September 14, 2026; the Mac App Store currently offers Xcode 26.6. The only locally installed Xcode at inspection was `/Applications/Xcode-beta.app`.
- **Account access:** an initial App Store Connect account failure recovered at 23:59:10 UTC in the same log. Subsequent application lookup and validation succeeded in contacting Apple. This is not an app code issue; sign-in may need refreshing if it recurs.
- **Version consistency:** the rejected archive recorded build `1`, despite the project build-number setting. The generated Info.plist now explicitly uses `$(CURRENT_PROJECT_VERSION)` and `$(MARKETING_VERSION)`, and the next build is `2026091403` / `1.0`.

## Remaining distribution steps

The Mac App Store download was cancelled, as requested by the user; no replacement Xcode was installed. Work continued through the CLI using the existing Xcode beta. A supported release/RC toolchain is still required to resolve error 90534; revalidating the same beta does not remove that restriction. Do not reuse or alter the previously rejected archive. This change does not establish overall App Review readiness; see `release-readiness.md` for independent product/backend blockers.

References:
- https://developer.apple.com/news/releases/
- https://developer.apple.com/documentation/bundleresources/information-property-list/uisupportedinterfaceorientations

## Additional build warnings

- Marked the concurrent vote-read helper `@Sendable`.
- Resolved the localized photo-picker label on the main actor before passing it into the picker label closure.
- The optional App Intents metadata extraction notice is expected because this app has no App Intents dependency; no unrelated framework was added to hide that notice.

## Verified CLI results

- Release build: succeeded (`/tmp/craft-distribution-check.log`).
- Signed archive: succeeded (`/tmp/CraftStudio-2026091403.xcarchive`).
- Strict/deep code-signature validation: succeeded.
- App Store distribution export: succeeded (`/tmp/CraftStudio-2026091403-export/CraftStudio.ipa`; log `/tmp/craft-distribution-export.log`).
- Verified in archive and exported IPA: version 1.0, build 2026091403, four iPad orientations. Archive also includes AppIcon and https://3d-craft.web.app.
- No new Apple server validation or upload was performed: the archive still reports the rejected beta toolchain 27A5218g / SDK 24A5380g. Local export success does not resolve error 90534.

## Follow-up validation at 19:43

The supplied `CraftStudio_2026-09-14_19-43-55.194.xcdistributionlogs` reports the same two errors, 90474 and 90534. It validates the older `~/Library/Developer/Xcode/Archives/2026-09-14/CraftStudio.xcarchive`, whose app still has build number 1, no iPad orientation override, and Xcode 27A5218g / SDK 24A5380g. It does not validate the corrected archive or the current GitHub source. Preserve this historical log; do not edit its errors away.

## Xcode Cloud distribution

- GitHub master and codex/app-store-cloud were synchronized to `eca871367b1d672a7cc557f27692bf58bba91b24`, including `ios/CraftStudio.xcodeproj` and its shared scheme.
- Cloud Build 2 (`b580ae11-5374-4dcf-ac42-4cb8e2c2aa90`) succeeded on Xcode 26.6 (17F113), with zero errors and zero warnings. It was a build-only action, not an upload.
- The Default workflow now has an Archive action using scheme CraftStudio and App Store Connect distribution preparation (`testFlightExternalAndAppStore`). It retains the existing device-build action.
- Cloud Build 3 (`56636a8a-4ec9-487d-880b-6d6d0a0508cc`) succeeded at 2026-09-15 00:56:56 UTC, with zero errors/warnings. Apple processed the uploaded binary as version 1.0 build 3, with state VALID and audience APP_STORE_ELIGIBLE. Build ID `d423e311-2ff4-4b24-8ae9-e7f33697ba96` was attached and saved to version 1.0; the relationship was then verified through App Store Connect. Xcode Cloud assigns build number 3, replacing the local project build number in this cloud artifact.
- No replacement Xcode was downloaded. Cloud build success does not establish the independent backend and product acceptance requirements in `release-readiness.md`.

## Latest verified distribution

Xcode Cloud Build 10, source `e776c696ee3fb8d7ef9dd93c62cce0bb83c7bd27`, passed Build and Archive with zero errors and warnings. Apple processed it as VALID / APP_STORE_ELIGIBLE. Build `7a51645a-3a00-4f3c-bb5e-80b59c2c226b` is attached to version 1.0; the saved relationship was read back successfully. The historical 19:43 validation errors 90474 and 90534 were reconfirmed in the supplied log; the accepted cloud build supersedes that old archive. No new Xcode download was needed. This does not mean the app has been submitted or approved. The newer concept-generation native changes require the next processed Cloud build.
