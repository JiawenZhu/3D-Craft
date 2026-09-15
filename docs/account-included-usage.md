# Personal ChatGPT usage — September 13, 2026

Personal ChatGPT planning/chat and GPT Image 2 use the connected user's account.
They cost zero 3D Craft tokens; the user's ChatGPT account limits still apply.
Gemini images retain the existing review tariff of 15 per image. Model generation
uses its provider cost plus the configured 15% service fee, rounded up at $0.01 usage value per Token; selecting ChatGPT does not make 3D free.
Single-view textured costs: Rodin 46, TRELLIS 3, Hunyuan 56, Hybrid 58. Unknown quotes block before reservation. Accepted jobs retain their quoted charge across retries and catalog changes.
The commercial 15% service fee applies to studio-paid provider costs, not the
user's account-included calls. These review tariffs are not production settlement.

The mobile queue now snapshots imageTokenCost. Reservation, successful and partial
image settlement, refinements and interrupted-worker recovery use that snapshot.
Zero-cost jobs need no paid or trial reservation. Legacy jobs without a snapshot
retain their original tariff. Already-settled historical charges are not rewritten.
A partial zero-cost result is classified from saved images, not from charged amount.

Personal-account availability is still checked on the server. Firebase-authenticated
account-only jobs and ChatGPT chat do not require a paid balance. The explicit
nonproduction CRAFT_ALLOW_LOCAL_REVIEW mode can use its existing test wallet for
other generation; production studio-paid jobs still fail closed while production
cost settlement remains incomplete. Selecting Gemini planning with ChatGPT images
is not classified as fully account-only because that planner can incur studio cost.

The iOS estimate, concept/refine confirmation, candidate-view actions, paywall
wording and wallet guards use the selected image provider. ChatGPT account image
and planning labels show zero app tokens. The cost calculator excludes account
images from studio provider costs.

Validation: 82 backend tests passed covering mobile generation/chat, pricing and
paid access. Added zero-balance, partial-result, worker-recovery and authenticated
account-only reservation cases; 3D tests verify per-engine reservation and settlement. iOS build
succeeded. Signed Debug app installed and launched on the connected iPhone with
its private gateway verified; local backend reloaded while no jobs were active.
The user-provided test account authenticated successfully with 1000 paid/test
credits and 45 concept tokens. It has no connected ChatGPT account, so provider
execution and zero-charge settlement were verified with mocked provider outputs,
not live ChatGPT generation. No Firebase deployment or production metering claim.
