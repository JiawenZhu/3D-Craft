# Physical iPhone acceptance

Record build number, iOS version, date and result for each case. Use the shared cloud origin https://3d-craft.web.app with the Mac backend stopped. Repeat core creation, library and purchase layouts on iPad before App Review.

| Case | Expected result | Result |
| --- | --- | --- |
| Fresh install, cellular connection | App opens; public examples load without a Mac service | Not tested on this release |
| Email sign-in, sign-out, sign-in again | Correct account; prior user's private data disappears on sign-out | Not tested on this release |
| Private library | Existing images and actual 3D models load from Firebase | Cloud API verified previously; phone pending |
| New photo/text concept | Correct reference and prompt; recoverable errors; result saved in Firebase | Blocked: cloud generation unavailable |
| 3D generation | Confirmed engine/cost; output saved; completion opens correct asset | Blocked: cloud generation unavailable |
| Background and network recovery | Job survives; no duplicate job or Token debit on retry | Blocked: durable cloud jobs missing |
| Lighting, rotation and export | Actual generated model renders and exported file opens | Phone pending |
| Pack purchase in Apple sandbox | Correct verified amount delivered once; Wallet opens before animation | Blocked: cloud purchase delivery unavailable |
| Cancel/pending purchase | No false success or Token increase | Cloud purchase acceptance pending |
| Repeat verification / restore | Existing receipt never credits twice | Cloud purchase acceptance pending |
| Subscription renewal and expiry | Only verified current-period allowance; purchased packs preserved | Cloud ledger acceptance pending |
| Switch subscription period | Apple's actual transaction/effective date used; no invented surcharge | Cloud purchase acceptance pending |
| Sign out during purchase verification | Purchase cannot credit another user's wallet | Cloud purchase acceptance pending |
| Delete account | In-app request removes/revokes account and associated cloud content per policy | Implementation audit and test pending |
| Community links, votes, reports and block | Links open; controls persist; abusive content can be reported/blocked | Cloud community acceptance pending |
| Accessibility | VoiceOver labels, Dynamic Type, reduced motion and Chinese/English text work | Pending |

Use Apple sandbox or StoreKit testing for purchase tests. Do not make a real payment merely to verify the integration. A successful old local test is not evidence that the shared cloud version passes.
