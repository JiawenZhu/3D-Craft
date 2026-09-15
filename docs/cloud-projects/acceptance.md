# Firebase project and reference uploads

Verified September 14, 2026, US Central.

## Deployed behavior

`POST /api/mobile/projects` and `POST /api/mobile/projects/{id}/references` now publish through Firebase at `https://3d-craft.web.app`. Cloud Run revision `craft-api-00007-bwr` serves the routes (same image as the verified `00006-mkn` deployment, with upload capacity settings).

- Firebase authentication supplies the owner. Foreign projects and accounts under deletion are rejected.
- Original/reference images are validated as JPEG, PNG or WebP, bounded to 20 MB and 40 million pixels, oriented correctly, converted to JPEG and stripped of EXIF/GPS metadata.
- Private Storage objects are written before a Firestore transaction publishes the project, concept, shared `mobileCreations` gallery entry, and request receipt. The transaction rechecks account deletion and project ownership.
- A stable optional `clientId` makes identical retries return the original result; different content with that ID returns 409. New native clients retain an account-scoped request ID until upload acknowledgment. Older clients remain compatible.
- Cloud Tasks cleanup is enqueued before each image write. The `craft-upload-cleanup` queue runs after one hour, beyond the bounded upload/request window, and retries failures. Its OIDC-authenticated worker retains only a published owned concept or removes the orphaned object. This also handles account deletion racing an upload. No public download token is generated.
- The service allows two concurrent requests per instance with 2 GiB memory, avoiding the previous 40-request concurrency for image decoding. A maximum-size 40-megapixel image normalized successfully in a local boundary check.
- Runtime Storage create/get permissions are restricted to the existing `users/` bucket condition. Metadata stays in Firestore and bytes in Storage; no SQLite or laptop service is involved.

## Evidence

- 44 focused backend tests passed, including malformed/oversized images, metadata removal, deletion guards, worker authentication and cloud media resolution.
- Isolated real Firestore/Storage integration passed identical and conflicting retries, foreign-project rejection, shared-library publication, orphan cleanup and deletion after upload began but before publication. All fixture records and files were removed.
- A disposable authenticated user exercised both routes through the canonical URL. Project reload returned both references; the website's Firebase library read returned both matching entries. Owner image read returned 200; unauthenticated read returned 403. Identical retry returned the same project and changed-content retry returned 409.
- The API enqueued two cleanup tasks. A forced task dispatch reached the authenticated Cloud Run worker and returned 200 at `2026-09-15T02:12:14.504547Z`. Remaining fixture tasks, files, records and the disposable Auth user were removed.
- Local iPhone Release compilation passed. Physical-device upload UI acceptance remains; this change has not replaced the working phone app.

## Remaining release work

These routes provide durable inputs, not generation itself. Cloud generation is still explicitly unavailable. Implement provider submission/recovery, jobs, concept/chat/planning routes, output publication, and transactional reservation/settlement before setting `generationReady=true`. Then perform phone acceptance against the cloud with the Mac service off.
