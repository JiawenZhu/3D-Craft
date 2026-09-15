# 3D Craft phone support

- Public number: +1 (747) 281-1202.
- Vapi number ID: 425bc418-1037-4353-b5b2-5982f5129fb9.
- Renamed number from CareerVivid Inbound to 3D Craft Support.
- Removed previous jastalk-firebase.web.app/vapi-webhook server URL; no replacement fabricated.
- Created dedicated assistant c9c58f0c-b1a3-4d2d-b27d-98e837976be1, 3D Craft Support. Published version v3, confirmed Current in version history, then assigned to number. Original Riley assistant unchanged.
- Prompt: vapi-system-prompt.txt. Provides AI disclosure, product FAQs, human email support and honest limitations; cannot access accounts, issue refunds or send support tickets.
- Audio recording, stored transcripts and assistant logging disabled in published v3. Vapi operational metadata/provider processing can still occur. No zero-data-retention guarantee.
- Existing private fallback destination retained; not displayed on website or public contact forms.
- Vapi editor produces a residual draft with compliancePlan.zdrEnabled=false when Advanced is opened. Version v3 remains Current; this residual default-only draft was not published.
- Website contact and privacy updated, production build passed and Firebase Hosting deployment succeeded. Live contact page verified with telephone link and AI disclosure.
- Apple DSA form now contains the authorized public number, address and email. Email verification code sent by Apple; waiting for user to enter it in the browser. Phone verification and document review remain incomplete. Vapi number SMS compatibility has not been verified; Apple manual verification may be needed.
- No real inbound call or fallback transfer was placed/tested. No existing active-call widget was operated.

## Human transfer update

Published assistant v6, “AI first with human transfer”. Attached published transferCall tool `8178d44e-eabf-4aff-bfae-16a68262e159` (`transfer_to_craft_support`) with the authorized private developer destination. The assistant answers first and invokes the transfer when a caller asks for a person. Dashboard confirms v6 is current and Published. Actual carrier transfer and receiving-phone ringing still require an inbound phone test; no outbound test call was placed.

Apple accepted the email verification code. Phone verification is still pending on the public support number. No replacement phone code was requested during this update.
