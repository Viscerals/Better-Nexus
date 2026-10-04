# Native channel owner identity

Task 037, control BN-CONTROL-SYNC-OWNER-20261003-037.

The owner confirms the current server contract: the Sync channel
`wrbuildssync` is realm-local. There are currently no cross-realm channels.
This is an owner-confirmed server assumption, not a fact established by the
installed client source or by offline tests. Revisit this rule before using
it on a server that adds cross-realm channel behavior.

MainLifecycle admits `CHAT_MSG_CHANNEL` using the existing channel check.
Only that callback calls `Sync.HandleNativeChannelIncoming`. A bare sender
from the game event can then use the current realm from
`GetNormalizedRealmName`, or `GetRealmName` when the first API is absent or
empty. The realm must be a valid string and cannot be `unknown`. The resulting
qualified identity must pass the existing strict transport parser. Missing or
invalid sender/realm context refuses before admission. Already qualified
senders remain as supplied, including a different realm.

This correction is limited to full-build owner admission and catalog storage.
The raw sender remains the peer/session and diagnostic identity. Payload owner
claims, stored-owner parsing, summaries, DPS and deletes keep their existing
rules. `Sync.HandleIncoming` without native channel provenance and addon
whispers retain qualified-transport authority. A handshake is not owner proof.

Build assembly retains the channel owner sender separately from the raw
sender. All chunks must carry the same value. Mixed native/unknown input or a
realm change cannot borrow authority from a different chunk. Deferred storage
keeps the same value for its later admission and catalog provenance decision.

Transport identity does not replace the stored-owner rules. Mismatched retained
claims, different-owner relays, conflicting stored keys, verified-owner
protections and local-owner protection remain enforced. A payload
`ownerVerified` flag is rejected by the unchanged wire schema.

The existing `owner_boundary` diagnostic keeps its meaning. A legitimate bare
native-channel sender can now produce `rawSenderQualified=false` and
`directOwner=true`. `claimMatches` and `localRealmAvailable` alone still grant
no authority. No diagnostic field or session retry rule was added.

Offline regressions use synthetic native events, two-chunk assembly and actual
catalog storage. They do not prove live transfer, saved persistence or later
session loading. The new candidate is native NOT TESTED until separate package
acceptance, installation and a two-client test.

## DPS native channel authority

The DPS correction extends the same owner-confirmed realm-local channel rule
to exact-record `WLD2` transfers. Assembly retains the qualified channel owner
sender separately from the raw peer identity, and every chunk must carry the
same authority context. A realm change or mixed native/unknown chunks refuses
the whole transfer. Only durable DPS admission receives that qualified sender;
response windows, peer/session identity and diagnostics retain the raw sender.

Qualified channel and addon transports keep their existing direct-owner rules.
Bare addon messages and unknown entry points cannot borrow the local realm.
No payload verification flag is trusted, no existing unverified saved record is
promoted at startup, and no score or replacement rule changes. An exact direct
owner replay may establish authority for matching historical evidence through
the existing promotion rule. Synthetic serialization/reload tests do not prove
live two-client SavedVariables persistence.
