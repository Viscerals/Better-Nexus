# Stop Sharing confirmation layer

The native NATIVE08 finding recorded the Build Library at DIALOG level 50
and its normal Stop Sharing confirmation at DIALOG level 1. The Library
covered the confirmation buttons. Closing the Library exposed the original
confirmation. One accepted click then produced the reviewed busy refusal.

Only NEXUS_STOP_SHARING_BUILD changes. Its OnShow callback saves the current
popup slot's stratum once and uses FULLSCREEN_DIALOG while this confirmation
is shown. OnHide restores the saved value and clears it. Frame levels,
other popup definitions, and global popup defaults stay unchanged. Repeated
display cannot replace the saved original stratum with the temporary one.

The confirmation remains visible above the Library after a Library close or
reopen. Cancel, Escape, acceptance, and reuse restore the slot. The existing
payload still names the original record. Ownership checks and NATIVE07's
refused, pending, and committed outcomes stay unchanged. No catalog admission,
scheduler, automatic retry, transport, or resource path changes.

Two new regressions invoke the actual detail button and actual dialog
callbacks. A test-only native popup boundary supplies the reported DIALOG/1
frame, child strata inheritance, standard Close behavior, and callback
dispatch. It does not emulate native pixels or hit testing. Tests cover both
buttons, repeated display, Cancel, Escape, Library close/reopen, a changed
selection, original-ID acceptance, zero accepted tickets on busy refusal,
pending and committed local removal, original layer restoration, and reuse
by an unrelated dialog. The 94 previous scripts and support files remain
unchanged. All tests use synthetic data and the established LuaJIT route.

Native visibility, clicks, frame callback timing, and terminal cleanup still
require separate authorized observation of this exact package. Peer withdrawal
remains unsupported and resource spending remains unapproved.
