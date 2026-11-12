-- One assigned target and one explicit Start. Reading either view is passive.
-- One window, NexusOrbPanel, holds two pages: the run controls and the
-- read-only history (NexusOrbRunLog, a child page, not its own window).
-- Switching pages only shows and hides frames: it starts, resumes, confirms
-- and cancels nothing. Closing the window (Close or Escape) is the one place
-- an armed new-run review is cancelled, exactly as before.
Nexus=Nexus or {}
local UI={};Nexus.OrbPanel=UI
local frame,advanced=nil,false
local sourcePage=1
local page="run"
local refreshFailing=false
-- Localization (full UI, issues #143-#148). Every code-owned text of these
-- windows names a stable key and is resolved through Nexus.Localization at
-- display time (looked up at each call, never cached at load). Runtime text
-- (reasons, refusals, notes) stays the runtime's raw English, because it is
-- compared, recorded and reported elsewhere; only this display boundary
-- (truthful) turns a known raw text into its key. A translated text is never
-- compared, matched or handed back to the runtime: decisions below use
-- states, kinds and flags, never shown words.
-- The English base of each key, used only while the seam is absent or a
-- key cannot be answered (unavailable): the window then shows the exact
-- English it showed before. It is the same English as the reviewed catalog
-- (data/LocalizationEnglish.lua); tests/prototype/l10n_ui_orb.lua checks that
-- every entry equals the seam's English base.
-- ORB-ENGLISH BEGIN (the English base of every orb.* key; see above)
local ENGLISH={
    ["orb.assignment.identity_found"]="Wishlist identity found; {reason}.",
    ["orb.assignment.identity_found_open_editor"]="Wishlist identity found; {reason}. Open the Wishlist Editor to choose and confirm its locked targets.",
    ["orb.assignment.identity_found_reason"]="{reason}.",
    ["orb.assignment.identity_found_reason_open_editor"]="{reason}. Open the Wishlist Editor to choose and confirm its locked targets.",
    ["orb.body.copy_report_help"]="Press Select all, then copy with Ctrl+C. Opening this view sends nothing anywhere.",
    ["orb.body.history_consumed_source"]="Consumed source: {echo}",
    ["orb.body.history_eligible_surplus"]="Eligible surplus at selection: {value} copy(ies). This is what the policy could draw from, not a count of copies sacrificed.",
    ["orb.body.history_operation"]="Operation {number}: {result}",
    ["orb.body.history_proposed_source"]="Proposed source: {echo}; no consumed source is recorded for this operation.",
    ["orb.body.history_recycle_candidate"]="This source was the run's permitted recycle candidate.",
    ["orb.body.history_select_operation"]="Select an operation to see what was offered and why it was chosen.",
    ["orb.body.history_since_start"]="{seconds}s after the run started",
    ["orb.body.history_technical"]="Technical: serial {serial}; state {state}; source {source}; selected {selected} ({kind}); obtained {obtained}",
    ["orb.body.start_approval"]="Start approves this maximum: eligible surplus copies/recycling. Ordinary Auto OFF.\nUp to 2 recovery checks within this maximum; owned Echoes decide completion.",
    ["orb.body.start_approval_history"]="Start approves this maximum + Echo baseline; {count} unconfirmed; late gains may arrive.\nSurplus/recycling; Auto OFF; 2 checks within max; owned Echoes decide completion.",
    ["orb.body.start_approval_history_full"]="Start approves this maximum. {count} {risk}\nSafe surplus/recycling; ordinary Auto OFF. Up to 2 recovery checks within this maximum; owned Echoes decide completion.",
    ["orb.body.timeline_choice_proposed"]="Choice proposed; submission and result are not confirmed by this stage.",
    ["orb.body.timeline_confirmed"]="Replacement confirmed from the recorded result.",
    ["orb.body.timeline_offer"]="Actual Orb offer observed.",
    ["orb.body.timeline_requested"]="Orb request prepared; a send receipt is not recorded.",
    ["orb.body.timeline_spend_unconfirmed"]="Spend not confirmed from this record; a host call may have occurred.",
    ["orb.body.timeline_stored"]="Operation recorded on this client.",
    ["orb.body.timeline_unconfirmed"]="Result not confirmed; the current outcome remains unconfirmed.",
    ["orb.button.advanced"]="Advanced",
    ["orb.button.cancel_review"]="Cancel review",
    ["orb.button.check_progress"]="Check progress...",
    ["orb.button.clear_exclusions"]="Clear source exclusions",
    ["orb.button.clear_focus"]="Clear focus",
    ["orb.button.close"]="Close",
    ["orb.button.confirm_new_run"]="Confirm new run",
    ["orb.button.continue_cancel"]="Cancel",
    ["orb.button.continue_check"]="Check the game's state",
    ["orb.button.continue_confirm"]="Continue",
    ["orb.button.continue_open"]="Continue...",
    ["orb.button.copy_report"]="Copy report",
    ["orb.button.details"]="Details",
    ["orb.button.exclude"]="Exclude",
    ["orb.button.help"]="Help",
    ["orb.button.hide_until_next_run"]="Hide until next run",
    ["orb.button.history_current"]="Current run",
    ["orb.button.history_previous"]="Previous run",
    ["orb.button.max"]="Max",
    ["orb.button.mini_panel"]="Mini panel",
    ["orb.button.my_builds"]="My Builds",
    ["orb.button.open_orbs"]="Open Orbs",
    ["orb.button.page_next"]="Next",
    ["orb.button.page_previous"]="Previous",
    ["orb.button.pause"]="Pause",
    ["orb.button.recheck"]="Recheck",
    ["orb.button.reference"]="Reference",
    ["orb.button.resume"]="Resume",
    ["orb.button.review_check"]="Review check...",
    ["orb.button.review_outcome"]="Review outcome...",
    ["orb.button.review_target"]="Review target",
    ["orb.button.select_all"]="Select all",
    ["orb.button.start"]="Start",
    ["orb.button.start_new_run"]="Start new run",
    ["orb.button.stop"]="Stop",
    ["orb.button.why_blocked"]="Why blocked...",
    ["orb.column.history_replaced"]="Replaced Echo",
    ["orb.column.history_replacement"]="Replacement",
    ["orb.column.history_result"]="Result",
    ["orb.column.history_why"]="Why selected",
    ["orb.error.all_rolled_complete"]="All rolled targets are already complete. No Orbs are needed.",
    ["orb.error.assign_resolved"]="Assign a resolved Wishlist through My Builds or the Wishlist Editor.",
    ["orb.error.assignment_fixed"]="Orb mode uses the assigned Wishlist. Change its assignment through My Builds or the Wishlist Editor.",
    ["orb.error.auto_accept_first"]="Turn off the game's automatic Echo acceptance first.",
    ["orb.error.balance_invalid"]="Orb balance is unavailable or invalid.",
    ["orb.error.balance_server_invalid"]="The server's Orb balance is invalid.",
    ["orb.error.balance_state_unavailable"]="Orb balance state is unavailable.",
    ["orb.error.balance_unsupported"]="The client does not expose the Orb balance capability.",
    ["orb.error.balance_waiting"]="Waiting for the server's Orb balance.",
    ["orb.error.balance_waiting_recheck"]="Waiting for the server's Orb balance. Use Recheck once it is available.",
    ["orb.error.catalog_not_ready"]="The local Echo catalog is not ready.",
    ["orb.error.changed_while_confirming"]="Echoes or resources changed while confirming. Review again.",
    ["orb.error.choose_echo"]="Choose an Echo first.",
    ["orb.error.choose_maximum"]="Choose a maximum, or press Max, before starting.",
    ["orb.error.confirmation_expired"]="The confirmation expired. Review the plan again.",
    ["orb.error.echo_data_waiting"]="Waiting for current rolled and locked Echo data from the server.",
    ["orb.error.exclusions_fixed"]="Exclusions are fixed during this run.",
    ["orb.error.limit_range"]="Choose a whole-number Orb limit from 1 to 10,000.",
    ["orb.error.max_changed_start"]="The maximum changed. Review it, then press Start again.",
    ["orb.error.max_fixed"]="The maximum is fixed during this run.",
    ["orb.error.max_fixed_unchanged"]="The maximum is fixed during this run. Nothing was changed.",
    ["orb.error.max_needs_balance"]="Max needs a confirmed Orb balance above zero. Your maximum was not changed.",
    ["orb.error.new_run_needs_balance"]="A new run needs a confirmed Orb balance above zero. Your maximum was not changed.",
    ["orb.error.new_run_needs_finished"]="Only a finished run can be followed by a new one.",
    ["orb.error.no_confirmed_orbs"]="No confirmed Orbs are available.",
    ["orb.error.no_safe_surplus"]="No safe surplus copies are available. Required and locked copies remain protected.",
    ["orb.error.orb_state_unreadable"]="The game's Orb state could not be read. No Orb will be spent.",
    ["orb.error.order_follows_wishlist"]="Target order follows the assigned Wishlist. Edit the Wishlist to change its targets.",
    ["orb.error.recheck_failed"]="The read-only refresh failed; no new action was requested.",
    ["orb.error.recheck_session_paused"]="Nexus is paused for this session. No refresh was requested.",
    ["orb.error.recheck_wait"]="Please wait before requesting another refresh.",
    ["orb.error.recycle_fixed"]="Recycling permission is fixed during this run.",
    ["orb.error.replaceable_changed"]="Your approved replaceable counts changed. Review them again.",
    ["orb.error.resume_context_changed"]="The original character/run/service no longer matches. This run cannot resume.",
    ["orb.error.resume_not_owner"]="This run no longer owns the action. Stop and approve a new run after settlement.",
    ["orb.error.resume_only_paused"]="Only an explicitly paused run can resume.",
    ["orb.error.resume_settle_first"]="The original operation must settle before Resume can adopt a changed assignment. Pending exposure is retained.",
    ["orb.error.resume_spend_unknown"]="The spend outcome remains unknown. No action will be repeated.",
    ["orb.error.resume_wait_wishlist"]="Wait for the assigned Wishlist to resolve.",
    ["orb.error.rival_addon"]="Disable the other Echo automation addon before starting Orb mode.",
    ["orb.error.rolled_complete_locked"]="Rolled targets are complete. Remaining locked Echo targets cannot be changed by Orbs; no spend will start.",
    ["orb.error.run_owns_action"]="An Orb run already owns this action.",
    ["orb.error.session_paused"]="Nexus is paused for this session. Resume Nexus first; no Orb action was sent.",
    ["orb.error.source_count_invalid"]="Choose a valid source-copy count.",
    ["orb.error.source_protected"]="That would replace a protected or unavailable copy.",
    ["orb.error.source_unsafe"]="An approved source is no longer safe. Review the replacement pool.",
    ["orb.error.sources_fixed"]="Replaceable copies are fixed during this run.",
    ["orb.error.state_unreadable"]="The current Orb state could not be read. No new action was sent.",
    ["orb.error.wishlist_changed_start"]="The selected Wishlist changed or is unavailable. Choose it again before starting.",
    ["orb.heading.copy_report"]="Copy this report",
    ["orb.heading.history_timeline"]="Recorded timeline (intermediate steps have no saved timestamps):",
    ["orb.label.details"]="Details:",
    ["orb.label.history_offered"]="Offered:",
    ["orb.label.history_run"]="Run {id}",
    ["orb.label.history_why"]="Why:",
    ["orb.label.history_why_selected"]="Why selected:",
    ["orb.label.include_technical"]="Include technical details",
    ["orb.label.maximum_this_run"]="Maximum Orbs this run:",
    ["orb.label.progress_unavailable"]="Target progress unavailable:",
    ["orb.label.recorded_note"]="Recorded note:",
    ["orb.label.source_row"]="{name} (quality {quality}): {count} safe excess",
    ["orb.label.sources_page"]="Eligible sources {page} / {pages}",
    ["orb.label.start_reason"]="Start:",
    ["orb.note.close_keeps_run"]="Closing the window does not stop an approved run. Use Pause or Stop.",
    ["orb.note.history_reload_cleared"]="History clears on reload or logout; steps before the reload are not listed.",
    ["orb.note.history_session"]="History clears on reload or logout.",
    ["orb.note.mini_close_keeps_run"]="Closing this panel does not stop the run.",
    ["orb.recovery.offer_open_proposed"]="The earlier Orb offer is still open. Before the reload Nexus proposed {echo} for it, and that call was refused before it reached the game. Nexus can confirm this action only if you choose that same Echo in the game's offer window. If you choose a different Echo, Nexus cannot confirm the action. The record and its spending exposure are kept.",
    ["orb.recovery.offer_open_proposed_exits"]="For the original no-choice class, Continue is available only after a reload for a client-observed spend with no usable recorded choice and no open offer, after a read-only check. Separately, a stopped attribution-ambiguous action needs its fresh distinct chosen gain actually owned. Both exits require a quiet read-only check and your confirmation.",
    ["orb.recovery.offer_open_proposed_route"]="Open /nexus orbs for this record's eligibility and explanation. Nexus never continues by itself. Nexus will not choose or spend.",
    ["orb.status.action_continue"]="What you can do: Continue... below checks the game, then asks you to confirm.",
    ["orb.status.action_finish_check"]="What you can do: finish or cancel the check in the Continue window.",
    ["orb.status.action_follow_details"]="What you can do: follow the details below.",
    ["orb.status.action_review_check"]="What you can do: Review check... below says why the check stopped.",
    ["orb.status.action_why_blocked"]="What you can do: follow the details; Why blocked... below explains this record.",
    ["orb.status.assign_to_begin"]="Assign a Wishlist through My Builds to begin.",
    ["orb.status.assigned_none"]="Assigned Wishlist: none",
    ["orb.status.assigned_wishlist"]="Assigned Wishlist: {name}",
    ["orb.status.balance_confirmed"]="Confirmed Orb balance: {count}",
    ["orb.status.balance_loading"]="Orb balance: loading",
    ["orb.status.balance_state"]="Orb balance: {state}. {reason}",
    ["orb.status.compact_paused_lost"]="Paused - this run can no longer resume",
    ["orb.status.compact_paused_not_ready"]="Paused - Wishlist not ready",
    ["orb.status.compact_paused_pending_many"]="Paused - {count} Orbs pending",
    ["orb.status.compact_paused_pending_one"]="Paused - {count} Orb pending",
    ["orb.status.compact_paused_result"]="Paused - result must settle",
    ["orb.status.compact_paused_review"]="Paused - review it in the Orb window",
    ["orb.status.compact_paused_settle"]="Paused - original must settle first",
    ["orb.status.compact_resume_uses"]="Resume uses: {target}",
    ["orb.status.compact_target_back"]="Target back to {target}",
    ["orb.status.compact_target_new"]="New target: {target}",
    ["orb.status.compact_target_unknown"]="Resume target unknown",
    ["orb.status.confirm_new_run_tail"]="Press Confirm new run to start a new run of up to {amount} Orb(s). Close this window to cancel.",
    ["orb.status.continue_checking"]="Continue: Checking",
    ["orb.status.continue_held"]="Continue held",
    ["orb.status.continue_ready"]="Continue ready",
    ["orb.status.continue_refused"]="Continue refused",
    ["orb.status.continue_state_checking"]="Checking the game's current state...",
    ["orb.status.continue_state_done"]="Continued",
    ["orb.status.continue_state_ready"]="Ready: waiting for your confirmation",
    ["orb.status.continue_state_refused"]="Not continued",
    ["orb.status.continue_state_unavailable"]="Not available",
    ["orb.status.continue_state_unchecked"]="Not checked yet",
    ["orb.status.enter_whole_maximum"]="Enter a whole-number maximum from 1 to 10,000, or press Max.",
    ["orb.status.fact_copies_left"]="{count} copies left",
    ["orb.status.fact_copy_left"]="{count} copy left",
    ["orb.status.fact_not_settled"]="last Orb not settled",
    ["orb.status.fact_pending_many"]="{count} Orbs pending",
    ["orb.status.fact_pending_one"]="{count} Orb pending",
    ["orb.status.headline_paused"]="Paused - a result restored after a reload is unresolved: no new Orb run or ordinary roll until it settles.",
    ["orb.status.headline_paused_continue"]="Paused - a result restored after a reload is unresolved: no new Orb run or ordinary roll until it settles or you continue past it.",
    ["orb.status.headline_recovery"]="Previous result is unresolved: no new Orb run or ordinary roll until it settles.",
    ["orb.status.headline_recovery_continue"]="Previous result is unresolved: no new Orb run or ordinary roll until it settles or you continue past it.",
    ["orb.status.history_max_increased"]="(maximum was increased)",
    ["orb.status.history_new_operations"]="{count} new operation(s) recorded. Use Next to read them.",
    ["orb.status.history_none_started"]="No run has been started in this session.",
    ["orb.status.history_now"]="Now: {now} (last recorded: {recorded})",
    ["orb.status.history_page_bounded"]="(recording stopped at this bound)",
    ["orb.status.history_page_none"]="No operations recorded",
    ["orb.status.history_page_range"]="Operations {first}-{last} of {total}",
    ["orb.status.history_pending_many"]="Pending (requested, not confirmed): {count} Orbs; the run has an unresolved operation and is not settled.",
    ["orb.status.history_pending_one"]="Pending (requested, not confirmed): {count} Orb; the run has an unresolved operation and is not settled.",
    ["orb.status.history_state_complete"]="Targets complete",
    ["orb.status.history_state_finished"]="Finished - Orb limit reached",
    ["orb.status.history_state_idle"]="Not started",
    ["orb.status.history_state_limit"]="Maximum reached",
    ["orb.status.history_state_no_sources"]="No safe surplus copies remain",
    ["orb.status.history_state_out_of_orbs"]="No Orbs remain",
    ["orb.status.history_state_paused"]="Paused",
    ["orb.status.history_state_ready"]="Preparing next replacement",
    ["orb.status.history_state_recovery"]="Previous result is unresolved",
    ["orb.status.history_state_rolled_complete"]="Rolled targets complete",
    ["orb.status.history_state_stopped"]="Stopped",
    ["orb.status.history_state_wait_offer"]="Waiting for the Orb offer",
    ["orb.status.history_state_wait_result"]="Waiting for result confirmation",
    ["orb.status.history_state_wait_world"]="Waiting for the game after loading",
    ["orb.status.history_truncated"]="The history reached its bound; later operations are not listed.",
    ["orb.status.line_awaiting_result"]="{count} awaiting result",
    ["orb.status.line_result_not_settled"]="result not settled",
    ["orb.status.line_run"]="Orb run: {status}",
    ["orb.status.line_spend_unconfirmed"]="spend not confirmed",
    ["orb.status.line_usage_limit_unknown"]="Used {spent} (approved limit unavailable)",
    ["orb.status.line_usage_no_max"]="Used {spent} (maximum not recorded)",
    ["orb.status.line_usage_of"]="Used {spent} of {limit} approved",
    ["orb.status.line_usage_spent_unknown"]="Used unavailable (approved limit {limit})",
    ["orb.status.locked_copies_remain"]="{count} locked target copies remain. Orbs cannot change locked Echo slots.",
    ["orb.status.max_changed_review"]="The maximum changed. Review it, then press Start new run again.",
    ["orb.status.max_fixed_during_run"]="The maximum cannot change during a run. Stop this run, then start a new run with a higher maximum.",
    ["orb.status.max_follows_balance"]="Maximum follows this balance (up to {count}) until you enter another amount.",
    ["orb.status.max_follows_unconfirmed"]="Maximum follows the confirmed balance; unavailable until it is confirmed.",
    ["orb.status.max_reached_stop"]="The approved maximum is reached. Stop, then start a new run with a higher maximum.",
    ["orb.status.mini_loading"]="Run status loading...",
    ["orb.status.mini_no_run"]="No approved Orb run",
    ["orb.status.mini_not_paused_unread"]="Not paused: the run status could not be read.",
    ["orb.status.mini_not_paused_was_not_running"]="Not paused: the run was not running.",
    ["orb.status.mini_not_resumed_lost"]="Not resumed: this run can no longer resume.",
    ["orb.status.mini_not_resumed_no_run"]="Not resumed: there is no approved run.",
    ["orb.status.mini_not_resumed_not_paused"]="Not resumed: only a paused run can resume.",
    ["orb.status.mini_not_resumed_not_ready"]="Not resumed: the Wishlist is not ready.",
    ["orb.status.mini_not_resumed_reason"]="Not resumed: {reason}",
    ["orb.status.mini_not_resumed_review_back"]="Not resumed: review the target in Open Orbs",
    ["orb.status.mini_not_resumed_review_new"]="Not resumed: review the new target in Open Orbs",
    ["orb.status.mini_not_resumed_settle"]="Not resumed: a pending result must settle.",
    ["orb.status.mini_not_resumed_unread"]="Not resumed: the run status could not be read.",
    ["orb.status.mini_not_stopped_inactive"]="Not stopped: no run is active or pending.",
    ["orb.status.mini_not_stopped_no_run"]="Not stopped: there is no approved run.",
    ["orb.status.mini_not_stopped_reason"]="Not stopped: {reason}",
    ["orb.status.mini_not_stopped_unread"]="Not stopped: the run status could not be read.",
    ["orb.status.mini_open_to_start"]="Open Orbs to review a maximum and start a run.",
    ["orb.status.mini_pause_failed"]="Pause failed: an error occurred.",
    ["orb.status.mini_paused"]="Paused.",
    ["orb.status.mini_paused_not_ready"]="Paused - the assigned Wishlist is not ready",
    ["orb.status.mini_paused_review_back"]="Paused - review the target in Open Orbs",
    ["orb.status.mini_paused_review_new"]="Paused - review the new target in Open Orbs",
    ["orb.status.mini_paused_settle"]="Paused - a pending result must settle first",
    ["orb.status.mini_pending_counts"]="Unknown spend: {unknown}; Reserved: {reserved}; Outcomes: {outcomes}",
    ["orb.status.mini_pending_many"]="Pending: {count} Orbs requested, not confirmed yet",
    ["orb.status.mini_pending_none"]="Pending: none",
    ["orb.status.mini_pending_one"]="Pending: {count} Orb requested, not confirmed yet",
    ["orb.status.mini_pending_unavailable"]="Pending: unavailable",
    ["orb.status.mini_reading_saved"]="Reading local saved data.",
    ["orb.status.mini_refused"]="Orb mode refused it.",
    ["orb.status.mini_result_not_settled"]="Last Orb result is not settled",
    ["orb.status.mini_resume_accepted"]="Resume accepted.",
    ["orb.status.mini_resume_failed"]="Resume failed: an error occurred.",
    ["orb.status.mini_resume_not_running"]="Resume accepted; the run is not running now.",
    ["orb.status.mini_resumed"]="Resumed with the same approved maximum.",
    ["orb.status.mini_rolled_missing"]="Rolled target copies missing: {value}",
    ["orb.status.mini_rolled_missing_short"]="Rolled missing: {count}",
    ["orb.status.mini_running"]="Running - {state}",
    ["orb.status.mini_stop_failed"]="Stop failed: an error occurred.",
    ["orb.status.mini_stopped"]="Stopped.",
    ["orb.status.mini_unavailable"]="Run status unavailable",
    ["orb.status.mini_unknown_state"]="Unknown state: {state}",
    ["orb.status.mini_unread"]="Could not read the run. Open Orbs for details.",
    ["orb.status.mini_unread_error"]="Reading the run status failed.",
    ["orb.status.mini_unread_malformed"]="The run status has an unexpected form.",
    ["orb.status.mini_unread_missing"]="The Orb runtime is not loaded.",
    ["orb.status.mini_usage_limit_unknown"]="Orbs used: {spent} (approved limit unavailable)",
    ["orb.status.mini_usage_no_max"]="Orbs used: {spent} (maximum not recorded)",
    ["orb.status.mini_usage_none"]="Orbs used: no run approved this session",
    ["orb.status.mini_usage_of"]="Orbs used: {spent} of {limit} approved",
    ["orb.status.mini_usage_spent_unknown"]="Orbs used: unavailable (approved limit {limit})",
    ["orb.status.mini_usage_unavailable"]="Orbs used and approved limit: unavailable",
    ["orb.status.no_change"]="No change.",
    ["orb.status.not_paused_not_running"]="Not paused: the run is not running.",
    ["orb.status.not_resumed_lost_approval"]="Not resumed: this run no longer owns the action. Stop, then approve a new run.",
    ["orb.status.not_resumed_not_offered"]="Not resumed: Orb mode does not offer Resume now.",
    ["orb.status.not_resumed_not_ready"]="Not resumed: the assigned Wishlist is not ready.",
    ["orb.status.not_resumed_running"]="Not resumed: the run is already running.",
    ["orb.status.not_resumed_settle"]="Not resumed: the original operation must settle first.",
    ["orb.status.original_operation"]="Original operation: {name}",
    ["orb.status.phase_complete"]="Targets complete",
    ["orb.status.phase_finished"]="Finished - limit reached",
    ["orb.status.phase_idle"]="Not started",
    ["orb.status.phase_limit"]="Maximum reached",
    ["orb.status.phase_no_sources"]="No safe surplus copies remain",
    ["orb.status.phase_out_of_orbs"]="No Orbs remain",
    ["orb.status.phase_paused"]="Paused",
    ["orb.status.phase_ready"]="Preparing next replacement",
    ["orb.status.phase_recovery"]="Previous result is unresolved",
    ["orb.status.phase_rolled_complete"]="Rolled targets complete",
    ["orb.status.phase_stopped"]="Stopped",
    ["orb.status.phase_wait_offer"]="Waiting for the Orb offer",
    ["orb.status.phase_wait_result"]="Waiting for result confirmation",
    ["orb.status.phase_wait_world"]="Waiting for the game after loading",
    ["orb.status.progress_unavailable"]="Target progress unavailable.",
    ["orb.status.reading_saved_data"]="Reading local saved data. Shared-library loading is not required.",
    ["orb.status.recovery_checking"]="Recovery: Checking",
    ["orb.status.recovery_held"]="Recovery held",
    ["orb.status.recovery_ready"]="Recovery ready",
    ["orb.status.recovery_refused"]="Recovery refused",
    ["orb.status.refresh_failed"]="Orb panel refresh failed. Controls are unavailable.",
    ["orb.status.restoring_assignment"]="Restoring assigned Wishlist...",
    ["orb.status.resume_back_held"]="Target changed and is back: Resume would use {target} again. Review target first.",
    ["orb.status.resume_back_reviewed"]="Reviewed: Resume would use {target}, the run's own target again, with the same maximum.",
    ["orb.status.resume_lost_approval"]="Resume is not available: this run no longer owns the action (for example after a loading screen). Stop, then approve a new run.",
    ["orb.status.resume_new_held"]="New target: Resume would use {target}. Review target first.",
    ["orb.status.resume_new_held_instead"]="New target: Resume would use {target} instead of {original}. Review target first.",
    ["orb.status.resume_new_reviewed"]="Reviewed: Resume would use {target} with the same maximum.",
    ["orb.status.resume_new_reviewed_instead"]="Reviewed: Resume would use {target} instead of {original} with the same maximum.",
    ["orb.status.resume_original"]="Resume continues the original operation for {target}.",
    ["orb.status.resume_same"]="Resume would use {target}, the same target.",
    ["orb.status.resume_settle"]="Resume waits: the original operation must settle before a changed target can be used.",
    ["orb.status.resume_unknown_loading"]="Resume target unknown: the assigned Wishlist is loading.",
    ["orb.status.resume_unknown_not_ready"]="Resume target unknown: the assigned Wishlist is not ready.",
    ["orb.status.resume_unknown_restoring"]="Resume target unknown: the assigned Wishlist is restoring.",
    ["orb.status.resume_unknown_unassigned"]="Resume target unknown: the assigned Wishlist is not assigned.",
    ["orb.status.resume_unknown_unavailable"]="Resume target unknown: the assigned Wishlist is unavailable.",
    ["orb.status.review_back_first"]="Review the target first: it changed and is back to {target}. Nothing was resumed.",
    ["orb.status.review_cancelled"]="Review cancelled. Resume stays withheld; nothing was spent.",
    ["orb.status.review_done"]="Reviewed: Resume would use {target} with the same maximum. Nothing was spent.",
    ["orb.status.review_new_first"]="Review the new target first: Resume would use {target}. Nothing was resumed.",
    ["orb.status.review_none"]="No changed target to review. Nothing was changed.",
    ["orb.status.review_state_changed"]="The review changed after it was shown; nothing was reviewed or cancelled. Check the target shown now. Nothing was spent.",
    ["orb.status.review_target_changed"]="The target changed after it was shown; nothing was reviewed. Check the target shown now, then review it again. Nothing was spent.",
    ["orb.status.rolled_missing"]="{count} rolled target copies still missing",
    ["orb.status.run_all_complete"]="All selected targets are complete.",
    ["orb.status.run_approved"]="Approved. Preparing one Orb replacement.",
    ["orb.status.run_auto_accept"]="Turn off the game's automatic Echo acceptance before continuing.",
    ["orb.status.run_balance_changed"]="The Orb balance changed unexpectedly. No further action will be submitted.",
    ["orb.status.run_choice_different"]="A different Echo choice appeared. Resolve it manually before continuing.",
    ["orb.status.run_choice_sent"]="Choice sent; waiting for the confirmed replacement.",
    ["orb.status.run_confirmed_next"]="Replacement confirmed. Preparing the next approved Orb.",
    ["orb.status.run_confirmed_paused"]="Last replacement confirmed; no next Orb will be spent until you explicitly continue.",
    ["orb.status.run_context_changed"]="Character, run, or service changed. The pending operation will not be replayed.",
    ["orb.status.run_idle"]="Choose a maximum, then Start to use safe surplus copies for the assigned Wishlist.",
    ["orb.status.run_internal_error"]="Orb mode encountered an internal error. No automatic repeat will be sent.",
    ["orb.status.run_internal_error_stopped"]="Orb mode stopped after an internal error. Check diagnostics; no automatic repeat will be sent.",
    ["orb.status.run_loading_interrupted"]="Loading interrupted the approved Orb run. Waiting to reconcile the current choice; no action is repeated.",
    ["orb.status.run_locked_changed"]="Locked Echoes changed; no further Orb action will be submitted.",
    ["orb.status.run_locked_changed_resolve"]="Locked Echoes changed during the operation. Resolve the result manually.",
    ["orb.status.run_log_offer_observed"]="The actual offer was observed.",
    ["orb.status.run_log_receipt_failed"]="The receipt could not be saved; no Orb was requested.",
    ["orb.status.run_log_requested"]="One Orb requested for this source copy.",
    ["orb.status.run_no_orbs"]="No Orbs remain. New resources will not restart this run automatically.",
    ["orb.status.run_no_sources"]="No safe surplus source copies remain. Required and locked copies stay protected.",
    ["orb.status.run_offer_changed"]="The pending Orb offer changed unexpectedly. Resolve the original operation manually.",
    ["orb.status.run_original_confirmed_review"]="Original replacement confirmed. Review the new assigned Wishlist, then Resume; usage is unchanged.",
    ["orb.status.run_other_action"]="Another Echo action is active. Resolve it first.",
    ["orb.status.run_ownership_mismatch"]="Echo ownership does not match the expected replacement. No further Orb will be spent.",
    ["orb.status.run_paused"]="Paused before the next spend.",
    ["orb.status.run_paused_pending"]="Paused. A submitted spend may still finish; the native offer remains available.",
    ["orb.status.run_previous_confirmed"]="Previous result confirmed. No spending restarted; review a new run explicitly.",
    ["orb.status.run_recovery_restored"]="An earlier Orb action is unresolved. Nothing will restart. Nexus is checking, read-only, whether its offer is still open.",
    ["orb.status.run_requested"]="One Orb requested; waiting for the actual offer.",
    ["orb.status.run_requested_balance"]="One Orb requested; waiting for the actual offer and balance confirmation.",
    ["orb.status.run_rival_picker"]="Another Echo picker is active. Disable it before continuing.",
    ["orb.status.run_rolled_changed"]="Rolled Echoes changed outside the pending sacrifice; resolve the offer manually.",
    ["orb.status.run_rolled_complete"]="Rolled targets are complete. Remaining locked targets are unchanged; no more Orbs will be spent.",
    ["orb.status.run_spend_visible"]="The spend outcome is now visible. Review the offer and press Resume, or resolve it manually.",
    ["orb.status.run_stopped"]="Stopped. No further Orb will be spent.",
    ["orb.status.run_stopped_pending"]="Stopped. A submitted operation may still finish; resolve any pending offer manually.",
    ["orb.status.run_waiting_after_loading"]="Waiting briefly after loading before acting. Cached data is not proof of a fresh server answer.",
    ["orb.status.run_wishlist_changed_resolve"]="The selected Wishlist changed; resolve the pending offer manually.",
    ["orb.status.run_wishlist_changed_review"]="The assigned Wishlist changed. Review it and Resume without resetting this run's usage.",
    ["orb.status.run_world_unavailable"]="The game state is still unavailable after loading. No Orb action was repeated. Recheck, then Resume when readable.",
    ["orb.status.segment_awaiting_result"]="awaiting Orb result",
    ["orb.status.segment_current_exposure"]="current exposure: {value}",
    ["orb.status.segment_history_reload"]="earlier outcome/check totals unavailable after reload",
    ["orb.status.segment_history_unavailable"]="earlier outcome/check totals unavailable",
    ["orb.status.segment_result_not_settled"]="Last Orb result not settled",
    ["orb.status.segment_unconfirmed_outcomes"]="unconfirmed outcomes: {value}",
    ["orb.status.segment_unknown_exposure"]="unknown spend exposure: {value}",
    ["orb.status.segment_unknown_spend"]="Unknown spend: {value}",
    ["orb.status.start_balance_unavailable"]="The maximum follows the confirmed Orb balance, which is not available. Nothing was started.",
    ["orb.status.start_balance_zero"]="The confirmed Orb balance is 0. Nothing was started.",
    ["orb.status.start_needs_whole_maximum"]="Enter a whole-number maximum from 1 to 10,000, or press Max. Nothing was started.",
    ["orb.status.strip_copies_remaining"]="{count} target copies remaining",
    ["orb.status.strip_not_settled"]="Last Orb action is not settled",
    ["orb.status.strip_pending_many"]="{count} Orbs pending, not confirmed yet",
    ["orb.status.strip_pending_one"]="{count} Orb pending, not confirmed yet",
    ["orb.status.strip_target_unavailable"]="Target data unavailable",
    ["orb.status.strip_usage_no_max"]="Orbs used: {spent}; max not recorded",
    ["orb.status.usage_head"]="Orbs used: {spent} / {limit}",
    ["orb.status.usage_pending_many"]="pending: {count} Orbs requested, not confirmed yet",
    ["orb.status.usage_pending_one"]="pending: {count} Orb requested, not confirmed yet",
    ["orb.tab.run_controls"]="Run controls",
    ["orb.tab.run_history"]="Run history",
    ["orb.title.continue_unconfirmed"]="Continue with an unconfirmed Orb outcome",
    ["orb.title.mini"]="Orb run status",
    ["orb.title.unresolved_action"]="Unresolved Orb action",
    ["orb.title.window"]="Orbs / Lost Memories",
    ["orb.tooltip.history_replaced"]="Replaced Echo: {echo}",
    ["orb.tooltip.history_replacement"]="Replacement: {echo}",
    ["orb.tooltip.history_replacement_proposed"]="Replacement: {echo} - selected, not received",
    ["orb.tooltip.history_result"]="Result: {result}",
    ["orb.tooltip.history_why_fallback"]="Why this Echo was selected",
    ["orb.tooltip.max_follow_balance"]="Follow your confirmed Orb balance, up to 1000, until you enter another amount or start the run. This does not spend Orbs.",
    ["orb.tooltip.mini_close"]="Hides this panel only. An approved run keeps running: use Pause or Stop. Mini panel in the Orb window shows it again.",
    ["orb.tooltip.mini_drag"]="Drag to move this panel. It stays where you put it until you reload; nothing is saved.",
    ["orb.tooltip.mini_missing"]="Copies, not Echo families: the rolled target copies this run still needed at its latest check. Locked targets are not counted, because Orbs cannot change locked Echoes. Unavailable is not 0, and 0 does not mean the whole build is complete.",
    ["orb.tooltip.mini_open"]="Opens the full Orb window. Opening it starts, resumes and spends nothing.",
    ["orb.tooltip.mini_panel_open"]="Shows a small movable panel with this run's status and Pause, Resume and Stop. Opening it starts, resumes and spends nothing.",
    ["orb.tooltip.mini_pause"]="Pause holds the run before its next Orb. An Orb already requested cannot be undone. Offered only while the run is running.",
    ["orb.tooltip.mini_pending"]="An Orb requested whose spend is not confirmed yet, or an Orb action whose result has not settled. It counts against the approved maximum until it settles.",
    ["orb.tooltip.mini_resume"]="Resume continues this paused run with the same approved maximum; its usage is not reset. It is not offered while an earlier action must settle first: one restored after a reload, one whose offer was already chosen, or one for a changed assignment. After a target change, review the new target in Open Orbs and resume there. Orb mode checks again before it continues.",
    ["orb.tooltip.mini_stop"]="Stop ends this run: no further Orb is spent. An action already submitted may still finish; resolve its offer in the game.",
    ["orb.tooltip.mini_usage"]="Orbs this run has used, against its current approved maximum. Unavailable means it could not be read; it is not 0.",
    ["orb.tooltip.reason_fallback_detail"]="Not a missing exact Wishlist target; chosen under the approved fallback rule. It may be replaced again only after the normal safety checks.",
    ["orb.value.balance_loading"]="loading",
    ["orb.value.balance_unknown"]="unknown",
    ["orb.value.balance_unsupported"]="unsupported",
    ["orb.value.echo_no_replacement"]="No replacement",
    ["orb.value.echo_not_recorded"]="Not recorded",
    ["orb.value.echo_proposed"]="{name} (proposed)",
    ["orb.value.echo_unknown"]="Unknown Echo ({id})",
    ["orb.value.echo_with_rarity"]="{name} ({rarity})",
    ["orb.value.limit_approved"]="{count} approved",
    ["orb.value.max_not_recorded"]="maximum not recorded",
    ["orb.value.offer_not_recorded"]="Offer not recorded",
    ["orb.value.offer_received"]="{echo} [received]",
    ["orb.value.offer_selected"]="{echo} [selected]",
    ["orb.value.quality_common"]="Common",
    ["orb.value.quality_epic"]="Epic",
    ["orb.value.quality_legendary"]="Legendary",
    ["orb.value.quality_rare"]="Rare",
    ["orb.value.quality_uncommon"]="Uncommon",
    ["orb.value.quality_unknown"]="Unknown quality",
    ["orb.value.rarity_proposed"]="{rarity} - proposed",
    ["orb.value.reason_fallback"]="Reusable fallback",
    ["orb.value.reason_manual"]="Manual choice",
    ["orb.value.reason_missing_target"]="Missing Wishlist target",
    ["orb.value.reason_unavailable"]="Reason unavailable",
    ["orb.value.result_awaiting"]="Awaiting result",
    ["orb.value.result_choice"]="Waiting for choice",
    ["orb.value.result_confirmed"]="Confirmed",
    ["orb.value.result_paused"]="Paused",
    ["orb.value.result_requested"]="Request prepared",
    ["orb.value.result_spend_unconfirmed"]="Spend not confirmed",
    ["orb.value.result_unconfirmed"]="Unconfirmed",
    ["orb.value.state_unknown"]="unknown",
    ["orb.value.target_tag_back"]="(back)",
    ["orb.value.target_tag_new"]="(new)",
    ["orb.value.target_tag_same"]="(same)",
    ["orb.value.target_unknown_short"]="target ?",
    ["orb.value.unavailable"]="unavailable",
    ["orb.value.unnamed_short"]="(unnamed)",
    ["orb.value.unnamed_wishlist"]="an unnamed Wishlist",
    ["orb.value.wishlist_none"]="none",
}
-- ORB-ENGLISH END
local function T(key)
    local L=Nexus.Localization
    if type(L)=="table" and type(L.Text)=="function" then
        local text,source=L.Text(key)
        if type(text)=="string" and source~="unavailable" then return text end
    end
    return ENGLISH[key]
end
-- A count slot record, as the seam builds it: unknown is never zero.
local function N(value)
    local L=Nexus.Localization
    if type(L)=="table" and type(L.Count)=="function" then return L.Count(value) end
    if type(value)=="number" and value>=0 and value<math.huge and value==math.floor(value) then
        return {known=true,value=value}
    end
    return {known=false}
end
-- The English template filled with the same slot values (seam absent or
-- unavailable): one pass, a count record as its value or "?".
local function fill(english,args)
    return (english:gsub("{(%l[%w_]*)}",function(slot)
        local v=args[slot]
        if type(v)=="table" then return v.known and tostring(v.value) or "?" end
        return tostring(v)
    end))
end
local function TF(key,args)
    local L=Nexus.Localization
    if type(L)=="table" and type(L.Format)=="function" then
        local text,source=L.Format(key,args)
        if type(text)=="string" and source~="unavailable" then return text end
    end
    return fill(ENGLISH[key],args)
end
-- Page sizes. The run page keeps its measured sizes; the history page is
-- taller so its footer sits below the details instead of over them. Both fit
-- a 768-unit-high UI (1280x720 or 1366x768 at the largest UI scale).
local RUN_W,RUN_H,RUN_H_ADVANCED=620,445,660
local LOG_TOP=40
local LOG_W,LOG_H=760,588
local function text(parent,x,y,w,h,value)
    local f=parent:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
    f:SetPoint("TOPLEFT",x,y);f:SetSize(w,h);f:SetJustifyH("LEFT");f:SetJustifyV("TOP")
    f:SetText(value or "");return f
end
local function button(parent,x,y,w,label,fn)
    local b=CreateFrame("Button",nil,parent,"UIPanelButtonTemplate")
    b:SetSize(w,24);b:SetPoint("TOPLEFT",x,y);b:SetText(label);b:SetScript("OnClick",fn)
    b:SetFrameLevel(parent:GetFrameLevel()+2);b:EnableMouse(true);return b
end
local function enable(b,on)if on then b:Enable()else b:Disable()end end
local function selected(b,on)
    if Nexus.Theme and Nexus.Theme.SetSelected then Nexus.Theme.SetSelected(b,on) end
end
local function styled(window,alpha)
    if not Nexus.Theme then return end
    if Nexus.Theme.StyleWindow then Nexus.Theme.StyleWindow(window,alpha) end
    if Nexus.Theme.StyleTree then Nexus.Theme.StyleTree(window) end
end
-- A size change keeps the top-left corner where it is, so the control the
-- player just pressed stays under the pointer. GetLeft/GetTop and anchor
-- offsets share the frame's own scale.
local function pinTopLeft(f)
    local left,top=f:GetLeft(),f:GetTop()
    if not left or not top then return end
    f:ClearAllPoints();f:SetPoint("TOPLEFT",UIParent,"BOTTOMLEFT",left,top)
end
-- The whole window stays on the visible UI. A page taller or wider than the
-- UI is scaled down (LayoutMetrics.FitToScreen: never below 0.5, scale 1 when
-- it fits). Because GetLeft/GetTop and anchor offsets are in the frame's own
-- scale, a scale change converts the corner the player sees to the new scale,
-- then keeps every edge on the UI. Four size reads per refresh; nothing
-- moves unless the UI size or the page size changed.
local fitSeen={}
local function fitWindow()
    local LM=Nexus.LayoutMetrics
    if not (frame and LM and LM.FitToScreen and UIParent) then return end
    local sw,sh=tonumber(UIParent:GetWidth()),tonumber(UIParent:GetHeight())
    local w,h=tonumber(frame:GetWidth()),tonumber(frame:GetHeight())
    if fitSeen.sw==sw and fitSeen.sh==sh and fitSeen.w==w and fitSeen.h==h then return end
    fitSeen.sw,fitSeen.sh,fitSeen.w,fitSeen.h=sw,sh,w,h
    local before=tonumber(frame:GetScale()) or 1
    local left,top=frame:GetLeft(),frame:GetTop()
    -- nil: no plausible UI size was reported, so nothing is moved.
    local scale=LM.FitToScreen(frame)
    if not (scale and left and top and w and h) then return end
    local x,y=left*before,top*before
    local cx=math.max(0,math.min(x,sw-w*scale))
    local cy=math.min(sh,math.max(y,h*scale))
    if math.abs(scale-before)>0.001 or math.abs(cx-x)>0.5 or math.abs(cy-y)>0.5 then
        frame:ClearAllPoints();frame:SetPoint("TOPLEFT",UIParent,"BOTTOMLEFT",cx/scale,cy/scale)
    end
end
-- The runtime still names a limit-increase step that no window offers. Until
-- that runtime text changes, the window states the step that does exist.
-- Values are keys: "orb.status.max_fixed_during_run" is "The maximum cannot
-- change during a run. Stop this run, then start a new run with a higher
-- maximum." and "orb.status.max_reached_stop" is "The approved maximum is
-- reached. Stop, then start a new run with a higher maximum."
local OBSOLETE_TEXT={
    ["Use Increase limit while paused, or finish this run first."]="orb.status.max_fixed_during_run",
    ["The approved limit is reached. Confirm an increased limit or stop."]="orb.status.max_reached_stop",
}
-- Exact raw runtime texts this window can say in the active language (the
-- display boundary only; the runtime keeps and compares its raw English). A
-- text not listed here is shown exactly as the runtime wrote it.
-- ORB-RUNTIME BEGIN (exact raw runtime text -> key; generated from the fragment)
local RUNTIME_TEXT={
    ["A different Echo choice appeared. Resolve it manually before continuing."]="orb.status.run_choice_different",
    ["A new run needs a confirmed Orb balance above zero. Your maximum was not changed."]="orb.error.new_run_needs_balance",
    ["All rolled targets are already complete. No Orbs are needed."]="orb.error.all_rolled_complete",
    ["All selected targets are complete."]="orb.status.run_all_complete",
    ["An Orb run already owns this action."]="orb.error.run_owns_action",
    ["An approved source is no longer safe. Review the replacement pool."]="orb.error.source_unsafe",
    ["An earlier Orb action is unresolved. Nothing will restart. Nexus is checking, read-only, whether its offer is still open."]="orb.status.run_recovery_restored",
    ["Another Echo action is active. Resolve it first."]="orb.status.run_other_action",
    ["Another Echo picker is active. Disable it before continuing."]="orb.status.run_rival_picker",
    ["Approved. Preparing one Orb replacement."]="orb.status.run_approved",
    ["Assign a resolved Wishlist through My Builds or the Wishlist Editor."]="orb.error.assign_resolved",
    ["Character, run, or service changed. The pending operation will not be replayed."]="orb.status.run_context_changed",
    ["Choice sent; waiting for the confirmed replacement."]="orb.status.run_choice_sent",
    ["Choose a maximum, or press Max, before starting."]="orb.error.choose_maximum",
    ["Choose a maximum, then Start to use safe surplus copies for the assigned Wishlist."]="orb.status.run_idle",
    ["Choose a valid source-copy count."]="orb.error.source_count_invalid",
    ["Choose a whole-number Orb limit from 1 to 10,000."]="orb.error.limit_range",
    ["Choose an Echo first."]="orb.error.choose_echo",
    ["Disable the other Echo automation addon before starting Orb mode."]="orb.error.rival_addon",
    ["Echo ownership does not match the expected replacement. No further Orb will be spent."]="orb.status.run_ownership_mismatch",
    ["Echoes or resources changed while confirming. Review again."]="orb.error.changed_while_confirming",
    ["Exclusions are fixed during this run."]="orb.error.exclusions_fixed",
    ["Last replacement confirmed; no next Orb will be spent until you explicitly continue."]="orb.status.run_confirmed_paused",
    ["Loading interrupted the approved Orb run. Waiting to reconcile the current choice; no action is repeated."]="orb.status.run_loading_interrupted",
    ["Locked Echoes changed during the operation. Resolve the result manually."]="orb.status.run_locked_changed_resolve",
    ["Locked Echoes changed; no further Orb action will be submitted."]="orb.status.run_locked_changed",
    ["Max needs a confirmed Orb balance above zero. Your maximum was not changed."]="orb.error.max_needs_balance",
    ["Nexus is paused for this session. No refresh was requested."]="orb.error.recheck_session_paused",
    ["Nexus is paused for this session. Resume Nexus first; no Orb action was sent."]="orb.error.session_paused",
    ["No Orbs remain. New resources will not restart this run automatically."]="orb.status.run_no_orbs",
    ["No confirmed Orbs are available."]="orb.error.no_confirmed_orbs",
    ["No safe surplus copies are available. Required and locked copies remain protected."]="orb.error.no_safe_surplus",
    ["No safe surplus source copies remain. Required and locked copies stay protected."]="orb.status.run_no_sources",
    ["One Orb requested for this source copy."]="orb.status.run_log_requested",
    ["One Orb requested; waiting for the actual offer and balance confirmation."]="orb.status.run_requested_balance",
    ["One Orb requested; waiting for the actual offer."]="orb.status.run_requested",
    ["Only a finished run can be followed by a new one."]="orb.error.new_run_needs_finished",
    ["Only an explicitly paused run can resume."]="orb.error.resume_only_paused",
    ["Orb balance is unavailable or invalid."]="orb.error.balance_invalid",
    ["Orb balance state is unavailable."]="orb.error.balance_state_unavailable",
    ["Orb mode encountered an internal error. No automatic repeat will be sent."]="orb.status.run_internal_error",
    ["Orb mode stopped after an internal error. Check diagnostics; no automatic repeat will be sent."]="orb.status.run_internal_error_stopped",
    ["Orb mode uses the assigned Wishlist. Change its assignment through My Builds or the Wishlist Editor."]="orb.error.assignment_fixed",
    ["Original replacement confirmed. Review the new assigned Wishlist, then Resume; usage is unchanged."]="orb.status.run_original_confirmed_review",
    ["Paused before the next spend."]="orb.status.run_paused",
    ["Paused. A submitted spend may still finish; the native offer remains available."]="orb.status.run_paused_pending",
    ["Please wait before requesting another refresh."]="orb.error.recheck_wait",
    ["Previous result confirmed. No spending restarted; review a new run explicitly."]="orb.status.run_previous_confirmed",
    ["Recycling permission is fixed during this run."]="orb.error.recycle_fixed",
    ["Replaceable copies are fixed during this run."]="orb.error.sources_fixed",
    ["Replacement confirmed. Preparing the next approved Orb."]="orb.status.run_confirmed_next",
    ["Rolled Echoes changed outside the pending sacrifice; resolve the offer manually."]="orb.status.run_rolled_changed",
    ["Rolled targets are complete. Remaining locked Echo targets cannot be changed by Orbs; no spend will start."]="orb.error.rolled_complete_locked",
    ["Rolled targets are complete. Remaining locked targets are unchanged; no more Orbs will be spent."]="orb.status.run_rolled_complete",
    ["Stopped. A submitted operation may still finish; resolve any pending offer manually."]="orb.status.run_stopped_pending",
    ["Stopped. No further Orb will be spent."]="orb.status.run_stopped",
    ["Target order follows the assigned Wishlist. Edit the Wishlist to change its targets."]="orb.error.order_follows_wishlist",
    ["That would replace a protected or unavailable copy."]="orb.error.source_protected",
    ["The Orb balance changed unexpectedly. No further action will be submitted."]="orb.status.run_balance_changed",
    ["The actual offer was observed."]="orb.status.run_log_offer_observed",
    ["The approved maximum is reached. Stop, then start a new run with a higher maximum."]="orb.status.max_reached_stop",
    ["The assigned Wishlist changed. Review it and Resume without resetting this run's usage."]="orb.status.run_wishlist_changed_review",
    ["The client does not expose the Orb balance capability."]="orb.error.balance_unsupported",
    ["The confirmation expired. Review the plan again."]="orb.error.confirmation_expired",
    ["The current Orb state could not be read. No new action was sent."]="orb.error.state_unreadable",
    ["The game state is still unavailable after loading. No Orb action was repeated. Recheck, then Resume when readable."]="orb.status.run_world_unavailable",
    ["The game's Orb state could not be read. No Orb will be spent."]="orb.error.orb_state_unreadable",
    ["The local Echo catalog is not ready."]="orb.error.catalog_not_ready",
    ["The maximum cannot change during a run. Stop this run, then start a new run with a higher maximum."]="orb.status.max_fixed_during_run",
    ["The maximum changed. Review it, then press Start again."]="orb.error.max_changed_start",
    ["The maximum is fixed during this run."]="orb.error.max_fixed",
    ["The maximum is fixed during this run. Nothing was changed."]="orb.error.max_fixed_unchanged",
    ["The original character/run/service no longer matches. This run cannot resume."]="orb.error.resume_context_changed",
    ["The original operation must settle before Resume can adopt a changed assignment. Pending exposure is retained."]="orb.error.resume_settle_first",
    ["The pending Orb offer changed unexpectedly. Resolve the original operation manually."]="orb.status.run_offer_changed",
    ["The read-only refresh failed; no new action was requested."]="orb.error.recheck_failed",
    ["The receipt could not be saved; no Orb was requested."]="orb.status.run_log_receipt_failed",
    ["The selected Wishlist changed or is unavailable. Choose it again before starting."]="orb.error.wishlist_changed_start",
    ["The selected Wishlist changed; resolve the pending offer manually."]="orb.status.run_wishlist_changed_resolve",
    ["The server's Orb balance is invalid."]="orb.error.balance_server_invalid",
    ["The spend outcome is now visible. Review the offer and press Resume, or resolve it manually."]="orb.status.run_spend_visible",
    ["The spend outcome remains unknown. No action will be repeated."]="orb.error.resume_spend_unknown",
    ["This run no longer owns the action. Stop and approve a new run after settlement."]="orb.error.resume_not_owner",
    ["Turn off the game's automatic Echo acceptance before continuing."]="orb.status.run_auto_accept",
    ["Turn off the game's automatic Echo acceptance first."]="orb.error.auto_accept_first",
    ["Wait for the assigned Wishlist to resolve."]="orb.error.resume_wait_wishlist",
    ["Waiting briefly after loading before acting. Cached data is not proof of a fresh server answer."]="orb.status.run_waiting_after_loading",
    ["Waiting for current rolled and locked Echo data from the server."]="orb.error.echo_data_waiting",
    ["Waiting for the server's Orb balance."]="orb.error.balance_waiting",
    ["Waiting for the server's Orb balance. Use Recheck once it is available."]="orb.error.balance_waiting_recheck",
    ["Your approved replaceable counts changed. Review them again."]="orb.error.replaceable_changed",
}
-- ORB-RUNTIME END
-- Full-UI remainder (v3): the other texts core/OrbRuntime.lua,
-- core/OrbAdapter.lua and logic/OrbPolicy.lua produce and keep raw (state,
-- reasons, Continue check, recovery), each English equal to the producer's
-- bytes; and the producer's own formats (%d a count, %s a code-filled slot;
-- nested: a slot value shown through its key or through this same book).
-- ORB-REMAINDER BEGIN (generated from the fragment)
local ORB_REMAINDER={exact={
    ["Orb mode already owns an operation."]="orb.adapter.already_owns",
    ["Assignment or source protection changed before submission. Resume only after reviewing the current assignment."]="orb.adapter.assignment_protection_changed",
    ["Cannot verify the game's automatic Echo-choice setting."]="orb.adapter.auto_choice_unverifiable",
    ["The live Echo catalog entry is unavailable or changed. Wait for verified catalog data."]="orb.adapter.catalog_entry_changed",
    ["Another choice is pending or no Orbs remain."]="orb.adapter.choice_pending_or_empty",
    ["The game refused the Orb choice. Resolve the offer manually."]="orb.adapter.choice_refused",
    ["The current Echo choices are malformed. No Orb was sent."]="orb.adapter.choices_malformed",
    ["The current Echo choices are unavailable."]="orb.adapter.choices_unavailable",
    ["This Echo is unavailable to this class."]="orb.adapter.class_unavailable",
    ["The character, loadout, or game service changed. Orb mode is paused."]="orb.adapter.context_changed_paused",
    ["The current rolled/locked Echo counts exceed the supported limits."]="orb.adapter.counts_exceed",
    ["Disable the other Echo automation addon before using Orb mode."]="orb.adapter.disable_rival",
    ["Echo discovery data or GetDiscoveredEchoes is unavailable."]="orb.adapter.discovery_unavailable",
    ["The Echo state check failed. No selection was sent."]="orb.adapter.echo_check_failed",
    ["The server reports that this Echo is disabled."]="orb.adapter.echo_disabled",
    ["The final Echo protection check failed. No selection was sent. Resolve the original pending operation manually."]="orb.adapter.echo_protection_failed",
    ["Your Echo state changed. Review the plan again."]="orb.adapter.echo_state_changed",
    ["The ID-only choice interface cannot distinguish the offered qualities. Resolve the offer manually."]="orb.adapter.id_only_interface",
    ["Invalid source."]="orb.adapter.invalid_source",
    ["Nexus rejected the current locked Echo data: a locked record is above the limit Nexus supports."]="orb.adapter.locked_record_over_limit",
    ["This client cannot observe a manual Echo choice."]="orb.adapter.manual_choice_unobservable",
    ["The client cannot create a frame."]="orb.adapter.no_create_frame",
    ["Orb mode is unavailable: the client does not expose OrbService."]="orb.adapter.no_orbservice",
    ["Orb mode is unavailable: the client does not expose PerkService."]="orb.adapter.no_perkservice",
    ["This Echo has not been discovered or observed."]="orb.adapter.not_discovered",
    ["The observer frame could not be created."]="orb.adapter.observer_frame_failed",
    ["Orb offer active -- manual action required"]="orb.adapter.offer_active_manual",
    ["The Orb offer changed or another action is pending."]="orb.adapter.offer_changed",
    ["The current Echo offer is invalid."]="orb.adapter.offer_invalid",
    ["The current Echo offer has unknown quality."]="orb.adapter.offer_quality_unknown",
    ["Orb action ownership is unavailable."]="orb.adapter.ownership_lock_unavailable",
    ["Echo ownership has an unsupported shape."]="orb.adapter.ownership_shape",
    ["Echo ownership is unavailable."]="orb.adapter.ownership_unavailable",
    ["Echo ownership could not be read."]="orb.adapter.ownership_unreadable",
    ["Echo ownership could not be verified."]="orb.adapter.ownership_unverified",
    ["Actions are blocked in passive diagnostics."]="orb.adapter.passive_diagnostics",
    ["Nexus is paused for this session. No Orb action was sent."]="orb.adapter.paused_not_sent",
    ["Cannot verify pending game actions."]="orb.adapter.pending_actions_unverifiable",
    ["The final Orb protection check failed. No Orb was sent."]="orb.adapter.protection_failed",
    ["Resolve the current Echo action first."]="orb.adapter.resolve_current_action",
    ["The original owner or a pending action prevents resuming."]="orb.adapter.resume_prevented",
    ["Another Echo picker may interfere. Orb mode is paused."]="orb.adapter.rival_may_interfere",
    ["This run no longer owns Orb actions."]="orb.adapter.run_not_owner",
    ["The selection outcome is unknown. No selection will be repeated."]="orb.adapter.selection_unknown",
    ["Nexus is paused for this session."]="orb.adapter.session_paused",
    ["The approved source or balance changed before spending."]="orb.adapter.source_or_balance_changed",
    ["The spend call failed; its server outcome is unknown. No repeat will be sent."]="orb.adapter.spend_call_failed",
    ["The game refused the Orb spend."]="orb.adapter.spend_refused",
    ["orb state capability missing"]="orb.adapter.state_capability_missing",
    ["The Orb state check failed. No Orb was sent."]="orb.adapter.state_check_failed",
    ["orb state not yet known"]="orb.adapter.state_not_yet_known",
    ["orb state unavailable"]="orb.adapter.state_unavailable",
    ["The current game state is unavailable."]="orb.adapter.state_unavailable_sentence",
    ["orb state unknown"]="orb.adapter.state_unknown",
    ["The assigned target changed before selection. The original pending operation must be resolved."]="orb.adapter.target_changed",
    ["PerkService.IsTomeEchoDisabled is unavailable."]="orb.adapter.tome_api_unavailable",
    ["PerkService.IsTomeEchoDisabled did not provide a known answer."]="orb.adapter.tome_api_unknown",
    ["Turn off the game's automatic Echo acceptance before starting Orb mode."]="orb.adapter.turn_off_auto_accept",
    ["unreadable error"]="orb.adapter.unreadable_error",
    ["Waiting for the complete three-choice offer."]="orb.adapter.waiting_three_choices",
    ["Choose or create a wishlist to begin your first run."]="orb.assignment.choose_or_create",
    ["First-run wishlist target"]="orb.assignment.first_run_target",
    ["First-run wishlist data is temporarily unavailable; waiting for the server mirror."]="orb.assignment.first_run_unavailable",
    ["Assigned Wishlist is absent from the current server list. Its saved plan is retained. Refresh the list or reassign deliberately."]="orb.assignment.mirror_absent",
    ["Assigned Wishlist has no distinct current server mirror. Its exact saved plan is retained. Refresh the list or reassign deliberately."]="orb.assignment.mirror_not_distinct",
    ["Wishlist needs locked targets. Open the Wishlist Editor to choose and confirm them."]="orb.assignment.needs_locked_targets",
    ["Waiting for loadout data..."]="orb.assignment.waiting_loadout",
    ["Your fresh Echo ownership shows the distinct chosen gain, but an earlier unconfirmed action could have caused it. This action remains UNCONFIRMED. Explicit Continue ends this old run and archives its original receipt unchanged, with confidence NONE. "]="orb.continue.attribution_owned_gain",
    ["The check asks read-only for the Orb count and Echoes twice and requires quiet unchanged state. Those arrivals do not prove that no older reply is still on its way. "]="orb.continue.check_explanation",
    ["Checking the game's current state. Nexus asked the game for the Orb count (and for your Echoes) and waits for an answer observed after that request began; it asks a second time after the first. No spend and no choice is sent, only these read-only questions. Any change in the game, or a loading screen, cancels this check."]="orb.continue.checking",
    ["Checking; wait for both observed answers."]="orb.continue.checking_wait",
    ["Choose Check, then explicitly confirm, or cancel."]="orb.continue.choose_check_confirm",
    ["Confirm this unconfirmed exit?"]="orb.continue.confirm_question",
    ["Continued with an unconfirmed outcome. The earlier Orb action is saved unchanged in the archive. Observed spend stays counted and unknown spend exposure stays unknown. Nothing was refunded, repeated or chosen. A new Orb run needs its own approval and every normal check."]="orb.continue.done",
    ["Observed spent Orbs stay counted; unknown spend exposure stays unknown, without a refund or another charge. No spend, choice or automatic Resume is sent. Ordinary rolling is released only after the checked archive saves. A new Orb run needs new approval. "]="orb.continue.exit_consequences",
    ["An earlier Orb action has a spend observed by this client (one Orb fewer with its offer; the game reports no server confirmation of it) and no recorded outcome, and its offer is gone. Continue lets you go on without that outcome. First Nexus checks the game's current state read-only: it asks the game twice for the Orb count (and for your Echoes) and waits for each answer. No spend and no choice is sent, only those read-only questions. You then confirm, or cancel."]="orb.continue.intro",
    ["The eight-entry recovery archive is full. Waiting or reload does not free space; retained records are not evicted."]="orb.continue.live_archive_full",
    ["A newer recovery archive format is retained unchanged."]="orb.continue.live_archive_future",
    ["The recovery archive is unreadable and retained unchanged."]="orb.continue.live_archive_malformed",
    ["Automatic recovery history capacity is reserved: two of eight entries and their space remain for explicit recovery. Waiting or reload does not free this finite space."]="orb.continue.live_archive_reserved",
    ["The game's automatic Echo acceptance is no longer known off."]="orb.continue.live_auto_accept",
    ["The answer differs from the current Orb balance."]="orb.continue.live_balance_mismatch",
    ["The Orb count refresh raised an error."]="orb.continue.live_charge_refresh_failed",
    ["This client cannot request the current Echo choice."]="orb.continue.live_choice_query_unavailable",
    ["The current Echo choice request raised an error."]="orb.continue.live_choice_request_failed",
    ["The current Echo choice is unreadable."]="orb.continue.live_choice_unreadable",
    ["The current game state could not be verified."]="orb.continue.live_default",
    ["The unresolved record exceeds the finite archive entry limits."]="orb.continue.live_entry_too_large",
    ["An Echo offer arrived; finish that offer in the game, or use Resume if it is offered for this unchosen action."]="orb.continue.live_late_choice",
    ["A pick result arrived during the check."]="orb.continue.live_late_result",
    ["A loading transition cancelled the check."]="orb.continue.live_loading_transition",
    ["The outgoing choice request cannot be observed safely."]="orb.continue.live_no_choice_observer",
    ["No usable empty-choice answer was observed; the choice remains unknown."]="orb.continue.live_no_empty_choice_reply",
    ["The game reply observer is unavailable."]="orb.continue.live_no_observer",
    ["No usable Echo ownership answer was observed in time."]="orb.continue.live_no_ownership",
    ["No usable charge answer was observed in time."]="orb.continue.live_no_reply",
    [" No automatic retry is available for this check. Wait for the actual result, resolve any native offer, or Stop. A reload keeps passive recovery; open Orbs to see whether explicit Continue is eligible."]="orb.continue.live_no_retry_tail",
    ["An unusable game packet prevents a quiet check."]="orb.continue.live_observer_tainted",
    ["An offer, native choice latch or other game action is active; finish it in the game."]="orb.continue.live_offer_or_action",
    ["This client cannot distinguish its own choice request from an empty answer."]="orb.continue.live_own_choice_request",
    ["The Echo refresh failed after the Orb count was requested."]="orb.continue.live_ownership_refresh_failed",
    ["The game reports a pending Orb offer; finish it in the game."]="orb.continue.live_pending_positive",
    ["The action record or its owner changed."]="orb.continue.live_receipt_changed",
    ["The Orb count or Echo refresh is unavailable."]="orb.continue.live_refresh_unavailable",
    ["An unusable game packet arrived during the check."]="orb.continue.live_rejected_packet",
    ["The observed Orb answers changed or disagreed."]="orb.continue.live_reply_changed",
    ["The Orb answer cannot establish that no offer is pending."]="orb.continue.live_reply_unqualified",
    ["The required refresh could not complete."]="orb.continue.live_request_failed",
    ["Another Echo picker is active."]="orb.continue.live_rival",
    ["The Orb balance, Echoes or loadout changed during the check."]="orb.continue.live_state_changed",
    ["The bounded reply history overflowed."]="orb.continue.live_transport_overflow",
    ["The current game state cannot be read."]="orb.continue.live_unreadable",
    ["The pending record cannot be saved durably."]="orb.continue.live_write_failed",
    ["The saved list of continued Orb actions is full. Nothing was changed and nothing was deleted."]="orb.continue.refusal_archive_full",
    ["The saved list of continued Orb actions was written by a newer version and is kept unchanged. Nothing was changed."]="orb.continue.refusal_archive_future",
    ["The saved list of continued Orb actions is not readable and is kept unchanged. Nothing was changed."]="orb.continue.refusal_archive_malformed",
    ["Automatic recovery history limit reached. Two entry slots and their space are reserved for explicit recovery; existing records are retained."]="orb.continue.refusal_archive_reserved",
    ["The game automatic acceptance setting changed. Automatic recovery stopped with its pending record retained."]="orb.continue.refusal_auto_accept",
    ["The answer about the Orb count does not match what the game shows, so the check was cancelled. Nothing was changed."]="orb.continue.refusal_balance_mismatch",
    ["The Orb count refresh raised an error. The check stopped and the pending record is retained."]="orb.continue.refusal_charge_refresh_failed",
    ["This client cannot request the current Echo choice; no recovery was authorized."]="orb.continue.refusal_choice_query_unavailable",
    ["A choice is recorded for the earlier Orb action. Wait for its matching result. An attribution-ambiguous action has an explicit exit only when fresh ownership shows its exact distinct chosen gain; the flag alone supplies no exit."]="orb.continue.refusal_choice_recorded",
    ["The Echo choice request raised an error; the pending record is retained."]="orb.continue.refusal_choice_request_failed",
    ["The current Echo choice is unreadable. Automatic recovery stopped with its record retained."]="orb.continue.refusal_choice_unreadable",
    ["The record of the earlier Orb action is too large to archive. Nothing was changed."]="orb.continue.refusal_entry_too_large",
    ["The game sent an Echo offer during the check. Resolve it in the game. Nothing was changed."]="orb.continue.refusal_late_choice",
    ["The game sent a pick result during the check, so it was cancelled. Nothing was changed. Check again."]="orb.continue.refusal_late_result",
    ["A loading screen started or ended, so this check was cancelled. Nothing was changed. Start the check again once the game is ready."]="orb.continue.refusal_loading_transition",
    ["The outgoing Echo choice request cannot be observed safely; no recovery was authorized."]="orb.continue.refusal_no_choice_observer",
    ["No usable empty-choice answer was observed. The choice remains unknown; the pending record and exposure are retained."]="orb.continue.refusal_no_empty_choice_reply",
    ["This client does not let Nexus observe the game's replies, so Continue is not available. Nothing was changed."]="orb.continue.refusal_no_observer",
    ["No fresh answer about your Echoes was observed in time. Nothing was changed. Use Check in the Continue window to check again."]="orb.continue.refusal_no_ownership",
    ["There is no unresolved Orb action."]="orb.continue.refusal_no_receipt",
    ["No answer was observed in time. Nothing was changed. Use Check in the Continue window to check again."]="orb.continue.refusal_no_reply",
    ["The check is not ready to confirm. Nothing was changed."]="orb.continue.refusal_not_ready",
    ["This action belongs to this session. Explicit Continue requires either passive recovery after reload or a stopped attribution-ambiguous action with a fresh exact distinct chosen gain actually owned."]="orb.continue.refusal_not_restored",
    ["A game packet that Nexus could not accept may have changed the game's cached offer or slot. A reload usually clears it. Nothing was changed."]="orb.continue.refusal_observer_tainted",
    ["An Orb or Echo offer is open in the game. Finish it in the game first; Continue starts only when no offer is open."]="orb.continue.refusal_offer_open",
    ["Something is open or in progress in the game (an offer, a choice or an action). Nothing was changed. Finish it, then check again."]="orb.continue.refusal_offer_or_action",
    ["The earlier Orb action belongs to another character."]="orb.continue.refusal_other_character",
    ["This client cannot distinguish its own choice request from an empty answer. Automatic recovery stopped with its record retained."]="orb.continue.refusal_own_choice_request",
    ["The Echo ownership refresh failed after the Orb count was requested. That outstanding request is retained; no later query was sent."]="orb.continue.refusal_ownership_refresh_failed",
    ["The game reports Orb offer(s) still pending. Resolve them in the game's offer window. No spend and no choice was sent."]="orb.continue.refusal_pending_positive",
    ["The earlier Orb action's record changed, so this check was cancelled. Nothing was changed."]="orb.continue.refusal_receipt_changed",
    ["This client cannot request the required Orb count and Echo ownership refresh."]="orb.continue.refusal_refresh_unavailable",
    ["A game message that Nexus could not accept arrived during the check, so it was cancelled. Nothing was changed."]="orb.continue.refusal_rejected_packet",
    ["An answer about the Orb count reported a change, or two answers disagree, so the check was cancelled. Nothing was changed. Check again."]="orb.continue.refusal_reply_changed",
    ["An answer about the Orb count was missing a field, malformed or not accepted, so the check cannot show that no Orb offer is pending. Nothing was changed."]="orb.continue.refusal_reply_unqualified",
    ["The required refresh requests did not all complete. Partial replies do not allow recovery; the pending record is retained."]="orb.continue.refusal_request_failed",
    ["Another Echo picker is active. Automatic recovery stopped with its record retained."]="orb.continue.refusal_rival",
    ["An Orb run is active. Pause or stop it first."]="orb.continue.refusal_running",
    ["Nexus is paused for this session. No read-only check was sent; check again after Resume Nexus."]="orb.continue.refusal_session_paused",
    ["Continue is not available for this record."]="orb.continue.refusal_spend_unconfirmed",
    ["This confirmation is no longer current. Nothing was changed."]="orb.continue.refusal_stale_token",
    ["Your Orb count, Echoes or loadout changed during the check, so it was cancelled. Nothing was changed. Check again when nothing is changing."]="orb.continue.refusal_state_changed",
    ["Too many game messages arrived during the check. Nothing was changed. Check again."]="orb.continue.refusal_transport_overflow",
    ["The game's current state cannot be read right now. Nothing was changed. Try again in a moment."]="orb.continue.refusal_unreadable",
    ["The record could not be saved safely. Nothing was changed. Try again."]="orb.continue.refusal_write_failed",
    ["Choose a resolved Wishlist first."]="orb.policy.choose_resolved_wishlist",
    ["EchoWeaver Orb policy"]="orb.policy.name",
    ["No safe target or approved recyclable offer. Resolve the offer manually."]="orb.policy.no_safe_target",
    ["Targets exceed 79 rolled and 6 locked copies. Confirm the locked targets in the Wishlist editor."]="orb.policy.targets_exceed",
    ["The target list is invalid."]="orb.policy.targets_invalid",
    ["Your Echoes show the recorded gain, but an earlier unconfirmed attempt could have caused it. This action cannot be confirmed. Its record and exposure are kept. Stop, then open Orbs for the explicit checked Continue exit, or use that exit during passive recovery after reload. No spending restarts."]="orb.recovery.attribution",
    ["A choice for the earlier Orb action is recorded, but an Echo choice is open in the game. Nexus checks the result only while no Echo choice is open; Recheck cannot close it. Taking an Echo from that choice changes your Echoes, and Nexus then cannot confirm the earlier action."]="orb.recovery.board",
    ["An earlier Orb action is unresolved. Another game action or an incomplete offer is visible. Nexus is waiting, read-only. Nothing will be sent."]="orb.recovery.checking",
    ["A choice for the earlier Orb action is recorded. Another game action is still in flight. Nexus is waiting, read-only, until it ends. Nothing will be sent."]="orb.recovery.host",
    ["The original loadout of the earlier Orb action cannot be verified. Nexus cannot confirm that action."]="orb.recovery.loadout",
    ["An earlier Orb action is unresolved. The game has not yet sent this character's build-slot data since it loaded, so Nexus cannot check the original loadout yet. Nexus is waiting, read-only, and records nothing until then: if an Orb offer is open, a choice made in it now cannot be recorded for the earlier action. Nothing will be sent."]="orb.recovery.loadout_unknown",
    ["The earlier Orb offer is still open. Choose an Echo in the game's offer window. Nexus will record that choice and wait for the matching result. Nexus will not choose or spend."]="orb.recovery.offer_open",
    ["The earlier Orb offer is still open, but this client cannot observe a manual choice. If you choose in the game, Nexus cannot confirm the earlier action afterwards."]="orb.recovery.offer_open_blind",
    ["An Orb offer is open, but the Orb balance or rolled Echoes do not match the saved record of the earlier action. Nexus cannot confirm the earlier action from this offer. Resolve the offer in the game."]="orb.recovery.offer_unmatched",
    ["A choice for the earlier Orb action is recorded. Echo ownership does not show the chosen Echo yet. Nexus is waiting for an ownership response that shows it. Recheck requests one. Nothing will be sent."]="orb.recovery.ownership",
    ["Locked Echoes changed since the earlier Orb action. Nexus cannot confirm that action."]="orb.recovery.permanent_changed",
    ["The earlier Orb action could not be linked to an observed result. The game gives no record of which choice belonged to it, so Nexus cannot confirm it, and Recheck cannot settle it. The record, its spending exposure, and the block on new Orb runs and ordinary rolling are kept. Nothing is retried, refunded or deleted."]="orb.recovery.unobservable",
    ["A choice for the earlier Orb action is recorded, and Echo ownership already shows the chosen Echo. Nexus needs an ownership response newer than its first read after the reload, and asked the game once for one. Recheck requests one more. No Orb and no choice will be sent."]="orb.recovery.wait_fresh_asked",
    ["The earlier Orb action is unresolved and no Orb offer is open. If the game opens an offer that matches the saved record and you choose in the game's offer window, Nexus records that choice at the moment you make it, unless another game action is in flight at that moment. Nexus cannot tell whether the game refused the spend."]="orb.recovery.wait_offer",
    ["The earlier Orb action is unresolved and no Orb offer is open. This client cannot observe a manual choice, so Nexus cannot confirm the earlier action if its offer opens later."]="orb.recovery.wait_offer_blind",
    ["A choice for the earlier Orb action is recorded. Nexus is waiting for a fresh ownership response that matches it exactly. Recheck requests one. Nothing will be sent."]="orb.recovery.wait_result",
    ["Assign a Wishlist before starting Orb mode."]="orb.runtime.assign_before_start",
    ["Could not disable ordinary automation."]="orb.runtime.automation_disable_failed",
    ["The ordinary automation owner is not available; no Orb action will be sent."]="orb.runtime.automation_owner_missing",
    ["Choose the open Echo choice in the game window first."]="orb.runtime.choose_echo_first",
    ["The earlier Orb count request remains pending. Requested Echo ownership only; no duplicate Orb count request was sent. No Orb or choice was submitted."]="orb.runtime.count_request_pending",
    ["A different choice was submitted during the pending Orb action. Nexus cannot confirm this action. The record and its spending exposure are kept."]="orb.runtime.different_choice_submitted",
    ["A different Echo was chosen than the one Nexus had proposed for this Orb action. Nexus can confirm only the proposed Echo, so it cannot confirm this action. The record and its spending exposure are kept."]="orb.runtime.different_echo_chosen",
    ["An earlier unconfirmed attempt may match this source and choice. The current result is not confirmed. Its record and exposure remain counted; no command will be repeated."]="orb.runtime.earlier_attempt_may_match",
    ["An Echo choice is shown."]="orb.runtime.echo_choice_shown",
    ["Finish the open Orb offer in the game window first."]="orb.runtime.finish_orb_offer_first",
    ["Observed gain retained with attribution unconfirmed by explicit consent."]="orb.runtime.gain_retained_unconfirmed",
    ["Retained Orb history changed. Review the new baseline before starting."]="orb.runtime.history_changed",
    ["Retained Orb history has no reserved space for another unresolved outcome. No new Orb action was sent; ordinary rolling remains available."]="orb.runtime.history_no_reserved_space",
    ["Review the displayed unconfirmed-history baseline before approving a new Orb run."]="orb.runtime.history_required",
    ["unconfirmed; Start accepts current Echoes baseline; late results may arrive."]="orb.runtime.history_risk",
    ["Retained Orb history cannot be verified. No new Orb action was sent."]="orb.runtime.history_unverified",
    ["Retained Orb history cannot be verified. The receipt and its exposure are kept; no result can be attributed."]="orb.runtime.history_unverified_kept",
    [" The record and its spending exposure are kept."]="orb.runtime.kept",
    ["needed target"]="orb.runtime.kind_needed_target",
    ["permitted fallback"]="orb.runtime.kind_permitted_fallback",
    ["permitted recycle"]="orb.runtime.kind_permitted_recycle",
    ["The last Echo action has no confirmed result yet."]="orb.runtime.last_action_unconfirmed",
    ["Last replacement confirmed. This Orb run already ended; no spending restarted. Review current targets before approving a new run."]="orb.runtime.last_replacement_ended",
    ["Limit increased by confirmation. Press Resume explicitly; usage was not reset."]="orb.runtime.limit_increased_resume",
    ["The approved Orb limit was reached."]="orb.runtime.limit_reached",
    ["The active loadout or assigned Wishlist changed. The original operation stays pending; Resume requires settlement and a resolved assignment."]="orb.runtime.loadout_or_wishlist_changed",
    ["The original loadout cannot be verified after a loadout change or an incomplete older receipt. Ownership responses do not identify the original loadout. Pending exposure is retained; no retry is allowed."]="orb.runtime.loadout_unverifiable",
    [" Orbs cannot change the remaining locked targets."]="orb.runtime.locked_targets_unchangeable_tail",
    ["unknown type"]="orb.runtime.marker_type_unknown",
    ["Matching ownership observed under the acknowledged baseline; no server action correlation. Preparing the next approved Orb."]="orb.runtime.matched_preparing_next",
    ["Matching ownership observed under the acknowledged baseline; no server action correlation. Review the new assigned Wishlist before any further approval; usage is unchanged."]="orb.runtime.matched_review_wishlist",
    ["Matching ownership observed under the acknowledged baseline; no server action correlation. No next Orb will be spent until you explicitly continue."]="orb.runtime.matched_wait_continue",
    ["Open"]="orb.runtime.next_step_open",
    ["Stop this Orb run first, then open"]="orb.runtime.next_step_stop_open",
    ["No assigned Wishlist"]="orb.runtime.no_assigned_wishlist",
    ["No authoritative result arrived. Spending is paused; no action will be repeated."]="orb.runtime.no_authoritative_result",
    [" For the original no-choice class, Continue is available only after a reload for a client-observed spend with no usable recorded choice and no open offer, after a read-only check. Separately, a stopped attribution-ambiguous action needs its fresh distinct chosen gain actually owned. Both exits require a quiet read-only check and your confirmation. Open /nexus orbs for this record's eligibility and explanation. Nexus never continues by itself."]="orb.runtime.no_exit",
    ["No Wishlist selected"]="orb.runtime.no_wishlist_selected",
    ["Nothing was changed."]="orb.runtime.nothing_changed",
    ["An Orb offer is shown."]="orb.runtime.orb_offer_shown",
    ["Pause the active run first, then choose a higher whole-number limit. Stopped/completed runs require new approval."]="orb.runtime.pause_before_limit",
    ["Could not preserve Orb preferences/recovery state durably. No new action was sent."]="orb.runtime.preferences_not_durable",
    ["Could not preserve Orb preferences/recovery state. No new action was sent."]="orb.runtime.preferences_not_preserved",
    ["Ownership shows progress, but an earlier unconfirmed attempt could have caused it."]="orb.runtime.progress_attribution_ambiguous",
    ["This Orb receipt cannot reserve its complete bounded exit record. No new Orb action was sent."]="orb.runtime.receipt_exit_unreserved",
    ["The earlier Orb action belongs to another character or an unsupported receipt format."]="orb.runtime.receipt_other_character",
    ["The two automatic Orb recoveries for this approved run are used. The last outcome remains unresolved; its record and exposure are kept. Stop, then use explicit Continue if its observed-gain check is eligible, or reload for passive recovery."]="orb.runtime.recoveries_used",
    ["Checking the current choice before a bounded Orb recovery. The last outcome is unconfirmed; no command is repeated."]="orb.runtime.recovery_checking_choice",
    ["The approved recovery context, balance or locked Echoes changed before the next Orb. Stop and review a new run."]="orb.runtime.recovery_context_changed",
    ["A newer loading epoch invalidated the recovery check."]="orb.runtime.recovery_epoch_invalidated",
    ["Loading invalidated the recovery check before the next Orb. Stop and review a new run."]="orb.runtime.recovery_loading_invalidated",
    ["Recovery needs a fresh empty-choice reply after newer activity. Resolve any open offer in the game, or Stop and approve a new run. No new Orb is sent."]="orb.runtime.recovery_needs_fresh_reply",
    ["Recovery observations were lost before the next Orb. Stop and review a new run."]="orb.runtime.recovery_observations_lost",
    ["Recovery observations are unavailable. Resolve any open offer in the game, or Stop and approve a new run. No new Orb is sent."]="orb.runtime.recovery_observations_unavailable",
    ["A newer choice request or changed observer invalidated the recovery check. Stop and review a new run."]="orb.runtime.recovery_request_invalidated",
    ["Retained without a confirmed result after a bounded recovery."]="orb.runtime.recovery_retained_unconfirmed",
    ["New game state could not preserve the recovery check. Stop and review a new run."]="orb.runtime.recovery_state_unpreserved",
    ["Recovery status unavailable"]="orb.runtime.recovery_status_unavailable",
    ["Recovery observations cannot be classified. Resolve any open offer in the game, or Stop and approve a new run."]="orb.runtime.recovery_unclassified",
    ["Requested an Orb/ownership refresh. No Orb or choice was submitted."]="orb.runtime.refresh_requested",
    ["Matching ownership replacement observed under the acknowledged current-state baseline; no server action correlation."]="orb.runtime.replacement_matched_baseline",
    ["Resuming the approved run without resetting its usage."]="orb.runtime.resuming_without_reset",
    ["Review the increased limit again."]="orb.runtime.review_increased_limit",
    ["Rolled targets are complete; Orbs cannot change the remaining locked targets."]="orb.runtime.rolled_complete_locked_remain",
    ["The observed rolled targets are complete. The last Orb outcome is unresolved; its receipt and exposure are retained. Open Orbs to review whether its explicit checked Continue is eligible. No further Orb will be sent."]="orb.runtime.rolled_complete_unresolved",
    ["An Orb run is already active or unresolved. Stop/settle it before starting another."]="orb.runtime.run_already_active",
    ["The same-ID, same-quality result is indistinguishable from stale ownership data. The client supplies no correlated completion evidence. Pending exposure is retained; no retry is allowed."]="orb.runtime.same_id_indistinguishable",
    ["Local saved data is not ready. No Orb action will be sent."]="orb.runtime.saved_data_not_ready",
    ["Session interrupted. Orb spending will not restart automatically."]="orb.runtime.session_interrupted",
    ["Stop and settle the current Orb operation before changing targets."]="orb.runtime.settle_before_target_change",
    ["Stop and settle the current run first."]="orb.runtime.settle_run_first",
    ["The game refused the Orb spend after the recovery permit was used. Stop and review a new run."]="orb.runtime.spend_refused_after_permit",
    ["not sent"]="orb.runtime.state_not_sent",
    ["A new Orb run"]="orb.runtime.subject_new_run",
    ["Ordinary rolling"]="orb.runtime.subject_ordinary_rolling",
    ["A change of Orb sources"]="orb.runtime.subject_source_change",
    ["A change of Orb targets"]="orb.runtime.subject_target_change",
    ["This action"]="orb.runtime.subject_this_action",
    ["This change"]="orb.runtime.subject_this_change",
    ["The submitted result is unresolved. Wait for its actual result or finish a native offer manually. Stop or reload for passive recovery and its explicit Continue eligibility; no repeat is allowed."]="orb.runtime.submitted_unresolved",
    [" This record contains no retained observation of one Orb fewer with this action's offer. That does not prove that the server spent nothing. Continue does not apply to this record. Start, Resume and reload cannot reconstruct the missing history; Recheck can collect current facts but cannot promise to settle it. Preserve the record; do not repeat the spend or clear its exposure."]="orb.runtime.unobserved",
    ["Waiting for a fresh server response confirming the selected replacement."]="orb.runtime.waiting_fresh_confirmation",
    ["A loading screen is in progress. Wait until the world is ready before Orb spending."]="orb.runtime.world_loading",
    ["The world just loaded. Wait a moment before Orb spending."]="orb.runtime.world_settling",
    ["Local saved data is unavailable (no character container). /reload may restore it."]="orb.runtime.write_container",
    ["Local saved data is unavailable. /reload may restore it."]="orb.runtime.write_database",
    ["Your character identity is not known yet. Wait a moment, then try again."]="orb.runtime.write_identity",
    ["Local saved data could not be verified. /reload may restore it."]="orb.runtime.write_lifecycle",
    ["Local saved data is still loading. Wait a moment, then try again."]="orb.runtime.write_lifecycle_loading",
    ["Saved data carries a storage migration marker this build does not support, so it is kept unchanged and read-only."]="orb.runtime.write_marker",
    ["This character's saved data has an unsupported shape."]="orb.runtime.write_row",
    ["Restoring assigned Wishlist..."]="orb.status.restoring_assignment",
},formats={
    {format="The saved data format marker is not a valid format number (%s%s). This build writes format %s. The data is kept unchanged and read-only.",
        key="orb.runtime.format_marker_invalid", fields={"marker_type", "marker_text", "supported"}, nested={marker_type={["unknown type"]="orb.runtime.marker_type_unknown"}}},
    {format="Saved data format %d did not pass this build's check for format %d data (field: %s). This build writes format %d. The data is kept unchanged and read-only.",
        key="orb.runtime.format_unverified", fields={"saved", "saved_again", "field", "supported"}},
    {format="Saved data format %d is not supported. This build writes format %d and reads formats %d to %d after a check. The data is kept unchanged and read-only.",
        key="orb.runtime.format_unsupported", fields={"saved", "supported", "first", "last"}},
    {format="Local character data is not ready: %s No Orb action will be sent.",
        key="orb.runtime.character_data_not_ready", fields={"reason"}, nested={reason=true}},
    {format="Finished - approved Orb exposure limit reached. %d Orb outcome(s) remain unconfirmed. Start a new run to continue.",
        key="orb.runtime.finished_exposure_unconfirmed", fields={"count"}},
    {format="Finished - limit reached. The approved maximum of %s Orb(s) was used. Start a new run to continue.",
        key="orb.runtime.finished_limit_used", fields={"limit"}},
    {format="A missing target is currently unavailable: %s. %s",
        key="orb.runtime.missing_target_unavailable", fields={"echo", "reason"}, nested={reason=true}},
    {format="Orb mode cannot start yet. %s",
        key="orb.runtime.cannot_start_yet", fields={"causes"}, nested={causes=true}},
    {format="Bounded Orb recovery stopped. %s The outcome is still unconfirmed; its record and exposure are kept. No spend or choice was repeated.",
        key="orb.runtime.bounded_recovery_stopped", fields={"why"}, nested={why=true}},
    {format="Continue with an unconfirmed Orb outcome? The earlier Orb action counts %d of its approved %d Orb(s) as spent. Nexus did not see which Echo, if any, you received, and the game gives no way to check. If you continue: the spent count stays; the original record is saved unchanged; nothing is refunded, repeated or chosen; Nexus stops blocking rolling; a new Orb run needs its own approval and every normal check. Risk you accept: Nexus cannot prove that the server is finished with the old action. Two answers that arrived after Nexus asked do not prove that no older answer is still on its way. A late result would show up as an ordinary change, and Nexus will not link it to the old record.",
        key="orb.continue.confirm", fields={"spent", "limit"}},
    {format="Recovered past %d unconfirmed Orb outcome(s). Earlier results may still arrive. All attempts remain within your approved maximum; completion uses your observed Echoes.",
        key="orb.runtime.recovered_past", fields={"count"}},
    {format="A choice for the earlier Orb action is recorded: %s. The game still reports its Orb offer as open. If you have not chosen in the game's offer window since the reload, choose %s there; a different Echo cannot confirm this action. Nexus then waits, read-only, for the matching result. Nexus will not choose or spend.",
        key="orb.recovery.offer", fields={"echo", "echo_again"}},
    {format="A choice for the earlier Orb action is recorded, but the Orb balance shown is %s and the record requires %s (one Orb less than before the action). Recheck asks the game for the current balance. While the balance differs, Nexus cannot confirm the action. The record and its spending exposure are kept.",
        key="orb.recovery.charges", fields={"observed", "expected"}},
    {format="Your Echoes show the recorded gain, but it cannot be attributed to this action. Continue is unavailable. %s The record and its spending exposure are kept. No spending restarts.",
        key="orb.runtime.gain_unattributable_refusal", fields={"refusal"}, nested={refusal=true}},
    {format="The game is still waiting for its reply to the earlier Orb choice (%s), so its offer window cannot take a choice now. /reload ends that wait. After /reload, if the offer is still open, choose %s in the game's offer window; Nexus then waits for the matching result. A different Echo cannot confirm this action. The record and its spending exposure are kept. Nexus will not choose or spend.",
        key="orb.runtime.held_choice", fields={"echo", "echo_again"}},
    {format="An earlier Orb action is unresolved. The current game state cannot be read yet: %s Nothing will be sent. The record and its spending exposure are kept.",
        key="orb.runtime.earlier_unresolved_unreadable", fields={"error"}, nested={error=true}},
    {format="A required target is no longer available. %s No next Orb will be spent.",
        key="orb.runtime.required_target_unavailable", fields={"reason"}, nested={reason=true}},
    {format="Nexus rejected the current locked Echo data: it lists %d occupied locked records, more than the %d locked slots the game reports.",
        key="orb.adapter.locked_records_over_capacity", fields={"occupied", "capacity"}},
    {format="%s is blocked: the observed gain cannot be attributed to this action. Continue is unavailable. %s The record and its spending exposure are kept.",
        key="orb.runtime.blocked_unattributable_refusal", fields={"subject", "refusal"}, nested={subject={["A change of Orb targets"]="orb.runtime.subject_target_change", ["A change of Orb sources"]="orb.runtime.subject_source_change", ["A new Orb run"]="orb.runtime.subject_new_run", ["This action"]="orb.runtime.subject_this_action", ["Ordinary rolling"]="orb.runtime.subject_ordinary_rolling", ["This change"]="orb.runtime.subject_this_change"}, refusal=true}},
    {format="%s is blocked: the observed gain cannot be attributed to this action. %s /nexus orbs for its explicit checked Continue exit. The record is kept until that check passes and you confirm; no spending restarts.",
        key="orb.runtime.blocked_unattributable_next", fields={"subject", "next_step"}, nested={subject={["A change of Orb targets"]="orb.runtime.subject_target_change", ["A change of Orb sources"]="orb.runtime.subject_source_change", ["A new Orb run"]="orb.runtime.subject_new_run", ["This action"]="orb.runtime.subject_this_action", ["Ordinary rolling"]="orb.runtime.subject_ordinary_rolling", ["This change"]="orb.runtime.subject_this_change"}, next_step={["Stop this Orb run first, then open"]="orb.runtime.next_step_stop_open", ["Open"]="orb.runtime.next_step_open"}}},
    {format="%s is blocked: an earlier Orb action is unresolved after a reload. Nexus only observes it and sends nothing. The block ends when that action is confirmed or, if this record retains an observation of this spend and has no usable recorded choice, and no offer is open, when Continue's read-only check passes and you confirm it. Open /nexus orbs for the current instruction.",
        key="orb.runtime.blocked_observes_after_reload", fields={"subject"}, nested={subject={["A change of Orb targets"]="orb.runtime.subject_target_change", ["A change of Orb sources"]="orb.runtime.subject_source_change", ["A new Orb run"]="orb.runtime.subject_new_run", ["This action"]="orb.runtime.subject_this_action", ["Ordinary rolling"]="orb.runtime.subject_ordinary_rolling", ["This change"]="orb.runtime.subject_this_change"}}},
    {format="%s is blocked: an earlier Orb action cannot be confirmed. If this record retains an observation of this spend and has no usable recorded choice, and no offer is open, Continue in /nexus orbs ends this block after its read-only check passes and your confirmation; Nexus does not clear it by itself. Open /nexus orbs for details.",
        key="orb.runtime.blocked_cannot_confirm", fields={"subject"}, nested={subject={["A change of Orb targets"]="orb.runtime.subject_target_change", ["A change of Orb sources"]="orb.runtime.subject_source_change", ["A new Orb run"]="orb.runtime.subject_new_run", ["This action"]="orb.runtime.subject_this_action", ["Ordinary rolling"]="orb.runtime.subject_ordinary_rolling", ["This change"]="orb.runtime.subject_this_change"}}},
    {format="%s is paused: Orb refinement owns the current action.",
        key="orb.runtime.paused_refinement_owns", fields={"subject"}, nested={subject={["A change of Orb targets"]="orb.runtime.subject_target_change", ["A change of Orb sources"]="orb.runtime.subject_source_change", ["A new Orb run"]="orb.runtime.subject_new_run", ["This action"]="orb.runtime.subject_this_action", ["Ordinary rolling"]="orb.runtime.subject_ordinary_rolling", ["This change"]="orb.runtime.subject_this_change"}}},
    {format="%s is blocked: a submitted Orb action is unresolved. Finish its offer in the game; Nexus confirms it only from the matching result. If it cannot be confirmed, reload the game: Continue in /nexus orbs may then apply.",
        key="orb.runtime.blocked_submitted_unresolved", fields={"subject"}, nested={subject={["A change of Orb targets"]="orb.runtime.subject_target_change", ["A change of Orb sources"]="orb.runtime.subject_source_change", ["A new Orb run"]="orb.runtime.subject_new_run", ["This action"]="orb.runtime.subject_this_action", ["Ordinary rolling"]="orb.runtime.subject_ordinary_rolling", ["This change"]="orb.runtime.subject_this_change"}}},
    {format="%s is blocked: an Orb run is paused. Press Stop in /nexus orbs to end that run.",
        key="orb.runtime.blocked_run_paused", fields={"subject"}, nested={subject={["A change of Orb targets"]="orb.runtime.subject_target_change", ["A change of Orb sources"]="orb.runtime.subject_source_change", ["A new Orb run"]="orb.runtime.subject_new_run", ["This action"]="orb.runtime.subject_this_action", ["Ordinary rolling"]="orb.runtime.subject_ordinary_rolling", ["This change"]="orb.runtime.subject_this_change"}}},
}}
-- ORB-REMAINDER END
UI.RUNTIME_TEXT_KEYS=RUNTIME_TEXT
-- A raw Orb text as this window shows it, and whether it was recognized: an
-- exact text, a producer format, or a text made only of exact sentences
-- (segments), through the seam's display phrasebook. Anything else (player or
-- game data, an unknown text) is shown exactly as the producer wrote it.
local orbBook
-- A runtime text with display facts (core/OrbRuntime.lua M.DisplayFacts:
-- a key, typed values and nested code values): said through its key with
-- those values when every level has a valid candidate; otherwise nil and the
-- book below shows it (the English keeps its exact bytes).
local function typedShown(facts)
    local L=Nexus.Localization
    if type(L)~="table" or type(L.Format)~="function" or type(facts)~="table" or type(facts.args)~="table" then return nil end
    local args={}
    for name,value in pairs(facts.args) do
        if type(value)=="table" then
            value=typedShown(value)
            if value==nil then return nil end
        else
            local map=type(facts.nested)=="table" and facts.nested[name] or nil
            local nestedKey=type(map)=="table" and map[value] or nil
            if nestedKey then
                local text,source=L.Text(nestedKey)
                if source~="unavailable" then value=text end
            end
        end
        args[name]=value
    end
    local text,source=L.Format(facts.key,args)
    if source=="candidate" then return text end
    return nil
end
-- One runtime paragraph said as ordered keyed paragraphs, each within the
-- 1024-byte raw / 2048-byte render contract (the runtime keeps and compares
-- its whole English). Shown joined by one space only when every paragraph
-- has a valid candidate; otherwise the whole exact English.
local SEGMENTED={
    {head="The earlier Orb offer is still open. Before the reload Nexus proposed ", tail=" for it, and that call was refused before it reached the game. Nexus can confirm this action only if you choose that same Echo in the game's offer window. If you choose a different Echo, Nexus cannot confirm the action. The record and its spending exposure are kept. For the original no-choice class, Continue is available only after a reload for a client-observed spend with no usable recorded choice and no open offer, after a read-only check. Separately, a stopped attribution-ambiguous action needs its fresh distinct chosen gain actually owned. Both exits require a quiet read-only check and your confirmation. Open /nexus orbs for this record's eligibility and explanation. Nexus never continues by itself. Nexus will not choose or spend.", slot="echo",
        keys={"orb.recovery.offer_open_proposed","orb.recovery.offer_open_proposed_exits","orb.recovery.offer_open_proposed_route"}},
}
local function segmentedShown(value)
    local L=Nexus.Localization
    if type(L)~="table" or type(L.Format)~="function" then return nil end
    for _,entry in ipairs(SEGMENTED) do
        local head,tail=entry.head,entry.tail
        if #value>=#head+#tail and value:sub(1,#head)==head and value:sub(#value-#tail+1)==tail then
            local slotValue,parts=value:sub(#head+1,#value-#tail),{}
            for i,key in ipairs(entry.keys) do
                local text,source
                if i==1 then text,source=L.Format(key,{[entry.slot]=slotValue}) else text,source=L.Text(key) end
                if source~="candidate" then return value end
                parts[i]=text
            end
            return table.concat(parts," ")
        end
    end
end
local function orbPhrase(value)
    if type(value)~="string" then return value,false end
    local key=OBSOLETE_TEXT[value]
    if key then return T(key),true end
    local L=Nexus.Localization
    local runtime=Nexus.OrbRuntime
    local facts=type(runtime)=="table" and type(runtime.DisplayFacts)=="function" and runtime.DisplayFacts(value) or nil
    local typed=facts and typedShown(facts)
    if typed then return typed,true end
    local segmented=segmentedShown(value)
    if segmented then return segmented,true end
    if type(L)=="table" and type(L.PhraseBook)=="function" and type(L.Phrase)=="function" then
        if not orbBook or orbBook.seam~=L then
            local exact={}
            for raw,k in pairs(RUNTIME_TEXT) do exact[raw]=k end
            for raw,k in pairs(ORB_REMAINDER.exact) do exact[raw]=k end
            orbBook=L.PhraseBook({segments=true,exact=exact,formats=ORB_REMAINDER.formats});orbBook.seam=L
        end
        return L.Phrase(value,orbBook)
    end
    key=RUNTIME_TEXT[value]
    if key then return T(key),true end
    return value,false
end
-- The Orb window's own receivers also say the adapter's identity-found note
-- in its whole form (core/UserText.lua T.IdentityNote); other windows reach
-- orbPhrase as a UserText phrase source and keep UserText's own form.
local function orbShown(value)
    local text=Nexus.UserText and type(Nexus.UserText.IdentityNote)=="function"
        and Nexus.UserText.IdentityNote(value,true) or nil
    if text then return text,true end
    return orbPhrase(value)
end
UI.Phrase=orbShown
-- The book itself (tests read its entries back); nil without the seam.
function UI.PhraseBook()
    orbPhrase("")
    return orbBook
end
-- Orb texts reach other windows through their reasons (a blocked roll or
-- slot change): those windows show them through the same book.
if Nexus.UserText and type(Nexus.UserText.AddPhraseSource)=="function" then
    Nexus.UserText.AddPhraseSource(orbPhrase)
end
local function truthful(value)
    if value==nil then return nil end
    return (orbShown(value))
end
-- Legacy EditBox has no Button Enable/Disable API. Lock both input routes and
-- release focus so an approved maximum cannot remain editable during a run.
local function editLimit(on)
    local e=frame.limit;e.editable=on==true
    e:EnableMouse(e.editable);e:EnableKeyboard(e.editable);e:SetAlpha(e.editable and 1 or .5)
    if not e.editable then e:ClearFocus()end
end
local function inactiveControls()
    editLimit(false)
    if frame.cont then frame.cont:Hide()end
    -- With no run read, Start alone holds its place, disabled like the rest.
    if frame.review then frame.review:Hide();frame.review.drawnKey,frame.review.shownKey,frame.review.shownAction=nil,nil,nil end
    if frame.pause then frame.pause:Hide();frame.resume:Hide();frame.start:Show()end
    for _,b in ipairs(frame.mutations)do b:Disable()end
    -- Start's reason belongs to a run read; without one it is not kept.
    if frame.startWhy then frame.startWhy:SetText("");frame.startWhy._nexusFullText=nil end
    -- The same measured rows as a full read (no fixed 445 with blank bands).
    frame.advanced:Hide()
    if frame.flowBands then frame.flowBands(false) else frame:SetHeight(RUN_H) end
end
-- A recorded name on one line: at most 100 characters, cut on a character
-- boundary (never inside a multi-byte letter or an escaped "||"). whole keeps
-- the complete value for the box's tooltip.
local function name(s,whole)
    local v=tostring(s or ""):gsub("[%c]"," ")
    if not whole then
        if Nexus.LayoutMetrics and Nexus.LayoutMetrics.Truncate then v=Nexus.LayoutMetrics.Truncate(v,100)
        elseif #v>100 then v=v:sub(1,100):gsub("[\192-\255][\128-\191]*$","") end
    end
    return (v:gsub("|","||"))
end
-- Sets a box's text. When a name in it was shortened, its tooltip
-- (LayoutMetrics.FullTextTooltip) carries the complete text.
local function setFull(fs,shown,full)
    fs:SetText(shown);fs._nexusFullText=(full and full~=shown) and full or nil
end
-- OWN_TEXT marks an err that is already this window's own shown text (in
-- the active language): notify shows it as it is.
local OWN_TEXT={}
local function notify(ok,err,own)
    if frame then frame.notice:SetText((own==OWN_TEXT and err) or truthful(err) or (ok and "" or T("orb.status.no_change")))end
    UI.Refresh()
end
-- This window's own refusal or outcome, already in the active language: it
-- is shown as it is, never passed through the runtime-text boundary again.
local function say(shown)
    if frame then frame.notice:SetText(shown)end
    UI.Refresh()
end
-- Deliberate review of a changed Resume target. When a paused run's next
-- Resume would adopt a different ready assignment than the one it started
-- with (OrbRuntime resumeTarget kind "changed"), Resume is offered only in
-- this window and only after Review target for that exact assignment (its
-- key). Memory only: another assignment, leaving that state or closing the
-- window clears it. It writes and sends nothing and can only withhold Resume;
-- Resume itself still makes every runtime check and adopts what it reads.
-- Review target and Cancel review act only on the exact target (key) and the
-- action their button showed at the last refresh (its shownKey and
-- shownAction): a click after the target changed reviews nothing, clears the
-- review and refreshes, so the new target needs its own deliberate review.
local review={key=nil}
local function changedTarget(t) return type(t)=="table" and t.kind=="changed" end
local function reviewHeld(t)
    return changedTarget(t) and not (t.key~=nil and review.key==t.key)
end
local function quotedName(t,whole)
    return t.name~=nil and ("'"..name(t.name,whole).."'") or T("orb.value.unnamed_wishlist")
end
local function reviewRefusal(t)
    if not reviewHeld(t) then return nil end
    -- A target that changed and came back is the run's own one: still
    -- reviewed first, but not called new.
    if t.returned then
        return TF("orb.status.review_back_first",{target=quotedName(t)})
    end
    return TF("orb.status.review_new_first",{target=quotedName(t)})
end
-- A paused run that no longer holds its approval (OrbRuntime resumeTarget
-- reason "authorization"): Resume refuses it whatever the assignment says.
local function lostApproval(t) return type(t)=="table" and t.kind=="blocked" and t.reason=="authorization" end
local LOST_APPROVAL_KEY="orb.status.resume_lost_approval"
-- The legacy one-button entry (Pause while running, Resume while paused). The
-- window no longer shows it during a run; it stays for programmatic callers
-- and takes the same review. Start carries the represented history review.
local function primary(limit,tracked,historyReview)
    local s=Nexus.OrbRuntime.Status()
    if s.running then return Nexus.OrbRuntime.Pause()end
    if s.state=="PAUSED" then
        local held=reviewRefusal(s.resumeTarget)
        if held then return nil,held,OWN_TEXT end
        return Nexus.OrbRuntime.Resume()
    end
    return Nexus.OrbRuntime.Start(limit,tracked,historyReview)
end
-- The maximum box shows the draft; a refresh sets it without counting as
-- typing (OnTextChanged ignores changes made here).
local function showLimit(value)
    local e=frame.limit;e.settingText=true;e:SetText(value);e.settingText=nil;e.shownDraft=value
end
local MAX_TIP_KEY="orb.tooltip.max_follow_balance"
-- Run state -> key of its label. A state without a key shows its raw code.
local phases={IDLE="orb.status.phase_idle",READY="orb.status.phase_ready",WAIT_OFFER="orb.status.phase_wait_offer",
    WAIT_WORLD="orb.status.phase_wait_world",
    WAIT_RESULT="orb.status.phase_wait_result",PAUSED="orb.status.phase_paused",STOPPED="orb.status.phase_stopped",
    COMPLETE="orb.status.phase_complete",
    ROLLED_COMPLETE="orb.status.phase_rolled_complete",LIMIT="orb.status.phase_limit",OUT_OF_ORBS="orb.status.phase_out_of_orbs",
    NO_SOURCES="orb.status.phase_no_sources",RECOVERY="orb.status.phase_recovery",
    FINISHED="orb.status.phase_finished"}
local function phaseLabel(state)
    local key=phases[state]
    if key then return T(key) end
    return state
end
local recoveryPhases={checking="orb.status.recovery_checking",ready="orb.status.recovery_ready",
    held="orb.status.recovery_held",refused="orb.status.recovery_refused"}
local continuePhases={checking="orb.status.continue_checking",ready="orb.status.continue_ready",
    held="orb.status.continue_held",refused="orb.status.continue_refused"}
local function phaseText(s)
    local state=phaseLabel(s.state)
    local recovery=(s.recoveryKind=="manual" and continuePhases or recoveryPhases)[s.recoveryPhase]
    return recovery and (T(recovery).." - "..state) or state
end
-- At FINISHED the primary control is the same button that was Pause while the
-- run was going and Resume while it was paused, and the limit box has just
-- been refilled with the configured maximum. One press there would start a new
-- spending run. The first press only arms it; the second press starts it.
local confirmNewRun=false
-- The maximum shown when the new run was armed. A different amount (for
-- example a tracked balance that changed) needs a new review.
local confirmAmount=nil
-- What an explicit Resume of a paused run would act on (OrbRuntime
-- resumeTarget): the ready assignment it would adopt, or the original
-- operation it would continue. An assignment that is not ready is never named.
-- Assignment state -> the whole "Resume target unknown" sentence for it.
local ASSIGNMENT_STATES={restoring="orb.status.resume_unknown_restoring",loading="orb.status.resume_unknown_loading",
    unavailable="orb.status.resume_unknown_unavailable",unassigned="orb.status.resume_unknown_unassigned"}
local function resumeTargetText(t,whole)
    if type(t)~="table" then return nil end
    local n=quotedName(t,whole)
    if t.kind=="original" then return TF("orb.status.resume_original",{target=n})
    elseif t.kind=="same" then return TF("orb.status.resume_same",{target=n})
    elseif t.kind=="changed" and t.returned then
        if not reviewHeld(t) then return TF("orb.status.resume_back_reviewed",{target=n}) end
        return TF("orb.status.resume_back_held",{target=n})
    elseif t.kind=="changed" then
        local was=t.original~=nil and t.original~=t.name and ("'"..name(t.original,whole).."'") or nil
        if not reviewHeld(t) then
            if was then return TF("orb.status.resume_new_reviewed_instead",{target=n,original=was}) end
            return TF("orb.status.resume_new_reviewed",{target=n})
        end
        if was then return TF("orb.status.resume_new_held_instead",{target=n,original=was}) end
        return TF("orb.status.resume_new_held",{target=n})
    elseif t.kind=="settle" then return T("orb.status.resume_settle")
    elseif t.kind=="unavailable" then
        return T(ASSIGNMENT_STATES[t.assignmentState] or "orb.status.resume_unknown_not_ready")
    elseif lostApproval(t) then return T(LOST_APPROVAL_KEY)
    end
    return nil
end
-- The compact views name the target in two short parts: what (with the raw
-- name; the caller shortens and escapes it) and the instruction.
-- A third value, plain, is true when the instruction is the plain Paused
-- state label itself (so a caller need not compare shown words).
local function compactTarget(t)
    if type(t)~="table" then return nil end
    local n=t.name~=nil and ("'"..tostring(t.name):gsub("%c"," ").."'") or T("orb.value.unnamed_wishlist")
    if t.kind=="original" or t.kind=="same" then return TF("orb.status.compact_resume_uses",{target=n}),T("orb.status.phase_paused"),true
    elseif t.kind=="changed" and t.returned then return TF("orb.status.compact_target_back",{target=n}),T("orb.status.compact_paused_review")
    elseif t.kind=="changed" then return TF("orb.status.compact_target_new",{target=n}),T("orb.status.compact_paused_review")
    elseif t.kind=="settle" then return nil,T("orb.status.compact_paused_settle")
    elseif t.kind=="unavailable" then return T("orb.status.compact_target_unknown"),T("orb.status.compact_paused_not_ready")
    elseif lostApproval(t) then return nil,T("orb.status.compact_paused_lost") end
    return nil
end
-- An unresolved earlier result, in layers: what it blocks, what the player can
-- do now (by the actual Continue state), then the runtime's own reason,
-- unshortened, so recorded Echo names and earlier facts stay exact. A record
-- restored after a reload that keeps the run paused reads in the same layers,
-- under its own label; it stays PAUSED and every gate is unchanged. Where an
-- explicit Continue is offered, settling is not the only way on.
local RECOVERY_HEADLINE="Previous result is unresolved: no new Orb run or ordinary roll until it settles."
local RECOVERY_HEADLINE_CONTINUE="Previous result is unresolved: no new Orb run or ordinary roll until it settles or you continue past it."
local PAUSED_HEADLINE="Paused - a result restored after a reload is unresolved: no new Orb run or ordinary roll until it settles."
local PAUSED_HEADLINE_CONTINUE="Paused - a result restored after a reload is unresolved: no new Orb run or ordinary roll until it settles or you continue past it."
local function continueOffered(cv)
    return type(cv)=="table" and (cv.eligible==true or cv.stage=="checking" or cv.stage=="ready")
end
-- UI.RECOVERY_HEADLINES keeps the English base; the window shows each
-- headline's key in the active language.
local function recoveryHeadline(state,cv)
    local cont=continueOffered(cv)
    if state=="PAUSED" then return T(cont and "orb.status.headline_paused_continue" or "orb.status.headline_paused") end
    return T(cont and "orb.status.headline_recovery_continue" or "orb.status.headline_recovery")
end
UI.RECOVERY_HEADLINES={recovery=RECOVERY_HEADLINE,recoveryContinue=RECOVERY_HEADLINE_CONTINUE,
    paused=PAUSED_HEADLINE,pausedContinue=PAUSED_HEADLINE_CONTINUE}
local function recoveryActions(cv)
    if cv.stage=="checking" or cv.stage=="ready" then
        return T("orb.status.action_finish_check")
    elseif cv.stage=="refused" then return T("orb.status.action_review_check")
    elseif cv.eligible==true then return T("orb.status.action_continue")
    elseif cv.explanation==true then return T("orb.status.action_why_blocked") end
    return T("orb.status.action_follow_details")
end

-- Read-only Orb history page. It renders one fixed row pool, reads only the
-- page it shows plus the operation whose details are open, and performs no Orb
-- action: opening, paging, selecting and copying spend nothing, select nothing
-- and write nothing. All presentation lives in Nexus.OrbHistory, which reads
-- recorded fields only.
local LOG_ROWS=8
-- One column layout for the header AND the body. A heading that keeps its own
-- offsets drifts away from the values it labels the moment either side is
-- touched, so both read these measurements and nothing else. ROW_X is where a
-- row starts inside the page, so the header sits on the same origin.
local LOG_ROW_X,LOG_ROW_W=20,720
local LOG_COLUMNS={
    {key="index",label="#",x=0,w=28},
    {key="source",label="Replaced Echo",text="orb.column.history_replaced",x=52,w=180,iconX=30},
    {key="replacement",label="Replacement",text="orb.column.history_replacement",x=260,w=190,iconX=238},
    {key="reason",label="Why selected",text="orb.column.history_why",x=456,w=150},
    {key="result",label="Result",text="orb.column.history_result",x=612,w=105},
}
-- Vertical bands of the history page, top to bottom, each starting below the
-- previous one: run selector and header, warning, headings, rows, details,
-- footer, note.
local LOG_BANDS={
    header={y=-2,h=50},warning={y=-56,h=20},headings={y=-80,h=18},
    rows={y=-102,h=40},details={y=-428,h=96},footer={y=-530,h=24},
    note={y=-558,h=20},
}
local logFrame,logView,logPage=nil,"current",1
local logSelection=nil
local logCopyFrame=nil
local logCopy={key=nil,text=nil}
local logSeen={}
local logRendered=nil
local ensureLog,refreshLog
-- Labels resolved for the ids this page actually shows. Cleared whenever the
-- history revision changes, so a stale label cannot outlive its page.
local logLabels={key=nil,byId={}}
local function logRunKey(run)
    if not run then return "none" end
    return tostring(run.which).."|"..tostring(run.runId)
end
local function logPageView(page)
    return Nexus.OrbRuntime.RunLog(logView,((page or 1)-1)*LOG_ROWS+1,LOG_ROWS)
end
local function logKey(run)
    if not run then return "none" end
    -- The revision changes on every recorded event, and the live run's usage,
    -- exposure and state are read as they are now (RunLog), so a cached copy
    -- cannot outlive the history it was made from.
    return table.concat({tostring(run.which),tostring(run.runId),
        tostring(run.revision),tostring(run.total),tostring(run.spent),tostring(run.reserved),
        tostring(run.liveState)},"|")
end
-- One lookup of ONE recorded id, at most once per distinct id on the page:
-- the addon's shared catalog accessor, then the client's own spell info. It
-- indexes the catalog by that exact id and never iterates it; the accessor
-- itself may refresh its own cache when the client's data changed, which is
-- the same shared call every other view makes. It sends no request, reads no
-- gameplay state, and writes nothing back into the run, the log or the
-- profile.
local function logResolve(spellId)
    local found=logLabels.byId[spellId]
    if found~=nil then return found.label,found.icon end
    local label,icon
    local adapter=Nexus.GameAdapter
    local catalog=adapter and adapter.Catalog and adapter.Catalog()
    local rows=catalog and (catalog.rows or catalog)
    local row=type(rows)=="table" and rows[spellId] or nil
    if type(row)=="table" and row.name and row.name~="" then label=row.name end
    if type(GetSpellInfo)=="function" then
        local ok,spellName,_,texture=pcall(GetSpellInfo,spellId)
        if ok then
            if not label and spellName and spellName~="" then label=spellName end
            if texture and texture~="" then icon=texture end
        end
    end
    logLabels.byId[spellId]={label=label,icon=icon}
    return label,icon
end
local function logHistory() return assert(Nexus.OrbHistory,"Orb history projection unavailable") end
-- Pages share the one window. Only frames are shown and hidden here.
local function showPage(name)
    if page==name then return end
    page=name
    local onRun=name=="run"
    for _,w in ipairs(frame.runWidgets)do if onRun then w:Show()else w:Hide()end end
    selected(frame.runTab,onRun);selected(frame.historyTab,not onRun)
    pinTopLeft(frame)
    if onRun then
        if logFrame then logFrame:Hide()end
        frame:SetWidth(RUN_W)
        if frame.flowBands then frame.flowBands(advanced) else frame:SetHeight(advanced and RUN_H_ADVANCED or RUN_H) end
    else
        -- A hidden box must not keep the keyboard. Typed text is already the
        -- runtime's draft, so nothing is lost.
        frame.limit:ClearFocus()
        ensureLog()
        frame:SetWidth(LOG_W);frame:SetHeight(LOG_TOP+LOG_H)
        logFrame:Show()
    end
    fitWindow()
end
-- The adapter's balance state code -> its word in the balance line. An
-- unlisted code is shown as the raw code.
local BALANCE_STATES={unknown="orb.value.balance_unknown",loading="orb.value.balance_loading",
    unsupported="orb.value.balance_unsupported"}
local function balanceWord(state)
    local key=BALANCE_STATES[state or "unknown"]
    return key and T(key) or tostring(state)
end
local function refresh()
    if not frame or not frame:IsShown()then return end
    -- The history page is read-only and reads its own data; the run controls
    -- are hidden, so they are not rendered.
    if page~="run" then return end
    local ready=Nexus.StartupStatus and Nexus.StartupStatus()
    if not ready or not ready.coreReady then
        setFull(frame.plan,T("orb.status.restoring_assignment"))
        setFull(frame.status,T("orb.status.reading_saved_data"))
        frame.balance:SetText(T("orb.status.balance_loading"))
        frame.targets:SetText("");frame.permanent:SetText("");frame.usage:SetText("")
        inactiveControls()
        -- No run can be read yet, so the compact status is not offered either.
        frame.miniPanel:Disable()
        return
    end
    frame.miniPanel:Enable()
    -- One display read per refresh; the source list is prepared only for Advanced.
    -- The snapshot authorizes nothing: Start, Resume and every spend read again.
    local s=Nexus.OrbRuntime.Status(advanced);frame.snapshot=s
    frame.historyReview=s.historyReview
    local consent=T("orb.body.start_approval")
    local consentFull
    if s.historyCount and s.historyCount>0 then
        consent=TF("orb.body.start_approval_history",{count=N(s.historyCount)})
        consentFull=TF("orb.body.start_approval_history_full",{count=N(s.historyCount),risk=truthful(s.historyRisk) or ""})
    end
    setFull(frame.approval,consent,consentFull)
    local a=s.assignment or {};local busy=s.running or s.pending or s.state=="PAUSED" or s.state=="LIMIT"
    -- A review belongs to the exact changed target it was made for.
    local target=s.state=="PAUSED" and s.resumeTarget or nil
    if not (changedTarget(target) and target.key~=nil and target.key==review.key) then review.key=nil end
    if a.state=="restoring" then setFull(frame.plan,T("orb.status.restoring_assignment"))
    elseif not a.name then setFull(frame.plan,T("orb.status.assigned_none"))
    else setFull(frame.plan,TF("orb.status.assigned_wishlist",{name=name(a.name)}),TF("orb.status.assigned_wishlist",{name=name(a.name,true)})) end
    -- A ready assignment whose read was refused is still assigned: its progress
    -- is unavailable (the reason is in the status line), not unassigned.
    local targets
    if s.progress then targets=TF("orb.status.rolled_missing",{count=N(s.progress.rolledMissing)})
    elseif a.state=="ready" then
        -- The note is the adapter's raw English, said through the Orb book.
        targets=a.note and (T("orb.label.progress_unavailable").." "..tostring(truthful(a.note))) or T("orb.status.progress_unavailable")
    else targets=truthful(a.note) or T("orb.status.assign_to_begin") end
    frame.targets:SetText(targets)
    local permanent=s.progress and s.progress.permanentMissing
    frame.permanent:SetText(permanent and permanent>0 and TF("orb.status.locked_copies_remain",{count=N(permanent)})or "")
    local d=s.limitDraft or {}
    local mode=""
    if not busy then
        if d.tracking then
            mode=d.value~=nil and ("\n"..TF("orb.status.max_follows_balance",{count=N(d.cap or 1000)}))
                or ("\n"..T("orb.status.max_follows_unconfirmed"))
        elseif d.text~=nil and d.value==nil then
            mode="\n"..T("orb.status.enter_whole_maximum")
        end
    end
    frame.balance:SetText((s.charges~=nil and TF("orb.status.balance_confirmed",{count=N(s.charges)})
        or TF("orb.status.balance_state",{state=balanceWord(s.balanceState),reason=truthful(s.balanceReason) or ""}))..mode)
    if s.state~="FINISHED" then confirmNewRun=false;confirmAmount=nil end
    editLimit(not busy)
    local shown
    if busy then shown=tostring(s.limit)
    elseif d.text~=nil then shown=d.text
    else shown=d.value~=nil and tostring(d.value) or "" end
    if not frame.limit:HasFocus() and frame.limit:GetText()~=shown then showLimit(shown) end
    -- Max: only an editable draft with a confirmed balance above zero. The
    -- click checks again.
    enable(frame.max,not busy and (tonumber(s.charges) or 0)>0 and s.balanceState=="confirmed")
    if confirmNewRun and confirmAmount~=nil and frame.limit:GetText()~=confirmAmount then
        confirmNewRun=false;confirmAmount=nil
        frame.notice:SetText(T("orb.status.max_changed_review"))
    end
    frame.start:SetText(T(s.running and "orb.button.pause" or (s.state=="PAUSED" and "orb.button.resume"
        or (s.state=="FINISHED" and (confirmNewRun and "orb.button.confirm_new_run" or "orb.button.start_new_run") or "orb.button.start"))))
    -- During a run, separate fixed Pause and Resume: a repeated press of one
    -- never becomes the other. Otherwise Start (also the two-step new run).
    if busy then frame.start:Hide();frame.pause:Show();frame.resume:Show()
    else frame.pause:Hide();frame.resume:Hide();frame.start:Show() end
    -- One usage form on every surface: Orbs used against the approved maximum;
    -- a requested Orb whose spend is not confirmed is pending. Before a run,
    -- the maximum shown is the draft, not yet approved.
    -- A restored receipt without its approved maximum keeps the configured
    -- fallback as its gate, but that number is not shown as approved.
    -- Unknown spend exposure, unconfirmed outcomes and unknown earlier history
    -- stay disclosed beside it, apart from the observed usage.
    local approved=s.limitKnown==false and T("orb.value.max_not_recorded") or TF("orb.value.limit_approved",{count=N(s.limit)})
    frame.usage:SetText(TF("orb.status.usage_head",{spent=N(s.spent),limit=(busy or s.limit>0)and approved or (shown~="" and shown or "-")})
        ..(s.reserved>0 and ("; "..TF(s.reserved==1 and "orb.status.usage_pending_one" or "orb.status.usage_pending_many",{count=N(s.reserved)}))or "")
        ..((s.uncertain or 0)>0 and ("; "..TF("orb.status.segment_unknown_exposure",{value=tostring(s.uncertain)})) or "")
        ..((s.unconfirmedResults or 0)>0 and ("; "..TF("orb.status.segment_unconfirmed_outcomes",{value=tostring(s.unconfirmedResults)})) or "")
        ..(s.historyKnown==false and ("; "..T("orb.status.segment_history_reload")) or ""))
    local reason=(s.running or s.pending or s.state=="PAUSED")and s.reason or (s.startReason or s.reason)
    local detail=truthful(reason) or s.error or ""
    local cv=Nexus.OrbRuntime.ContinueView()
    local shownStatus,fullStatus
    -- s.recovery is present only for a receipt restored after a reload. A
    -- pending, nonrunning record whose Continue view offers its explanation
    -- (restored, or an explicit attribution exit) reads in the same layers.
    if s.state=="RECOVERY" or (s.state=="PAUSED" and s.recovery~=nil)
        or (s.pending and not s.running and cv.explanation==true) then
        -- Only a restored record that stays PAUSED takes the paused label;
        -- any other held record keeps the generic unresolved headline.
        local restoredPaused=s.state=="PAUSED" and s.recovery~=nil
        local headline=recoveryHeadline(restoredPaused and "PAUSED" or "RECOVERY",cv)
        -- A live automatic recovery check keeps its owned phase first; a
        -- restored record keeps its layered headline (Continue is its action line).
        if s.recoveryKind=="automatic" and recoveryPhases[s.recoveryPhase] then
            headline=T(recoveryPhases[s.recoveryPhase]).." - "..headline
        end
        shownStatus=headline.."\n"..recoveryActions(cv).."\n"..T("orb.label.details").." "..detail
        if s.recoveryNotice and reason~=s.recoveryNotice then shownStatus=shownStatus.."\n"..s.recoveryNotice end
        fullStatus=shownStatus
    else
        local phase=phaseText(s)
        local line,whole=resumeTargetText(target,false),resumeTargetText(target,true)
        shownStatus=phase..(line and ("\n"..line) or "").."\n"..detail
        fullStatus=phase..(whole and ("\n"..whole) or "").."\n"..detail
        if s.recoveryNotice and reason~=s.recoveryNotice then
            shownStatus,fullStatus=shownStatus.."\n"..s.recoveryNotice,fullStatus.."\n"..s.recoveryNotice
        end
    end
    if confirmNewRun and s.state=="FINISHED" then
        local tail="\n"..TF("orb.status.confirm_new_run_tail",{amount=tostring(frame.limit:GetText())})
        shownStatus,fullStatus=shownStatus..tail,fullStatus..tail
    end
    if s.targetChanged then
        shownStatus=shownStatus.."\n"..TF("orb.status.original_operation",{name=name(s.operationName)})
        fullStatus=fullStatus.."\n"..TF("orb.status.original_operation",{name=name(s.operationName,true)})
    end
    setFull(frame.status,shownStatus,fullStatus)
    -- Start's own reason, beside it: only while Start (not Pause or Resume)
    -- shows and the runtime says it cannot start; the same words as the status.
    if frame.startWhy then
        local why=(not busy and s.state~="PAUSED" and s.canStart==false) and truthful(s.startReason) or nil
        why=why and tostring(why) or ""
        local line=why:match("^[^\n]*") or ""
        local label=T("orb.label.start_reason")
        setFull(frame.startWhy,line~="" and (label.." "..line) or "",why~="" and (label.." "..why) or nil)
    end
    frame.assignmentNote:SetText(truthful(a.mirrorNote) or "")
    if advanced then
        local rows=s.sources or {};sourcePage=math.max(1,math.min(sourcePage,math.max(1,math.ceil(#rows/4))))
        for i,r in ipairs(frame.sourceRows)do
            local v=rows[(sourcePage-1)*4+i];r.key=v and v.key
            setFull(r.label,v and TF("orb.label.source_row",{name=name(v.name),quality=N(v.quality),count=N(v.excess)}) or "",
                v and TF("orb.label.source_row",{name=name(v.name,true),quality=N(v.quality),count=N(v.excess)}))
            enable(r.exclude,v~=nil and not busy)
        end
        enable(frame.clearExclusions,not busy)
        frame.sourcePage:SetText(TF("orb.label.sources_page",{page=N(sourcePage),pages=N(math.max(1,math.ceil(#rows/4)))}))
    end
    local held=reviewHeld(target)
    enable(frame.start,s.running or (s.canResume and not held) or s.canStart);enable(frame.stop,busy);enable(frame.assigned,not busy)
    enable(frame.pause,s.running);enable(frame.resume,not s.running and s.canResume and not held)
    do
        local stage=cv.stage
        frame.cont:SetText(T(stage=="done" and "orb.button.review_outcome"
            or stage=="refused" and "orb.button.review_check"
            or stage=="checking" and "orb.button.check_progress" or (stage=="ready" or cv.eligible==true) and "orb.button.continue_open" or "orb.button.why_blocked"))
        if not cv.liveRecovery and (cv.explanation==true or cv.eligible==true or stage=="checking" or stage=="ready" or stage=="refused" or stage=="done") then frame.cont:Show()else frame.cont:Hide()end
    end
    -- Review target shares Continue's place and is never shown with it.
    -- The button acts only on the exact target it was drawn for and the
    -- action it showed (drawnKey, shownKey, shownAction): a click after the
    -- target or its review changed underneath it reviews and cancels nothing
    -- (see the handler).
    if changedTarget(target) and target.key~=nil and not frame.cont:IsShown() then
        frame.review.drawnKey=target.key
        frame.review:SetText(T(held and "orb.button.review_target" or "orb.button.cancel_review"));frame.review:Show();frame.review:Enable()
        frame.review.shownKey,frame.review.shownAction=target.key,held and "review" or "cancel"
    else frame.review:Hide();frame.review.drawnKey,frame.review.shownKey,frame.review.shownAction=nil,nil,nil end
    if advanced then frame.advanced:Show()else frame.advanced:Hide()end
    selected(frame.advancedToggle,advanced)
    -- Measured rows (flowBands sets the height; a new one keeps the top-left).
    if frame.flowBands then frame.flowBands(advanced) else frame:SetHeight(advanced and RUN_H_ADVANCED or RUN_H) end
    return true -- A complete run-status read/render, not a history/loading pass.
end
function UI.Refresh()
    if not frame or not frame:IsShown()then return end
    local ok,err=pcall(refresh)
    if not ok then
        inactiveControls()
        setFull(frame.status,T("orb.status.refresh_failed"))
        -- Keep controls unavailable on every failed read, but report only the
        -- first error in an episode. A successful read permits a new report.
        if refreshFailing then return end
        refreshFailing=true
        error(err,0)
    end
    if err==true then refreshFailing=false end
    -- Advanced, a page change or a new UI scale or screen size.
    fitWindow()
end
local function ensure()
    if frame then return end
    frame=CreateFrame("Frame","NexusOrbPanel",UIParent);frame:Hide();frame:SetSize(RUN_W,RUN_H);frame:SetPoint("CENTER",UIParent,"CENTER",0,0)
    frame:SetFrameStrata("DIALOG");frame:SetFrameLevel(30);frame:EnableMouse(true);frame:SetMovable(true);frame:SetClampedToScreen(true)
    frame:RegisterForDrag("LeftButton");frame:SetScript("OnDragStart",function(self)self:StartMoving()end)
    frame:SetScript("OnDragStop",function(self)self:StopMovingOrSizing()end)
    frame:SetBackdrop({bgFile="Interface\\Buttons\\WHITE8X8",edgeFile="Interface\\Tooltips\\UI-Tooltip-Border",edgeSize=14,insets={left=4,right=4,top=4,bottom=4}})
    frame:SetBackdropColor(.035,.04,.05,1)
    frame.plan=text(frame,20,-48,440,32)
    frame.assigned=button(frame,469,-48,130,T("orb.button.my_builds"),function()
        if Nexus.JournalTab and Nexus.JournalTab.OpenBuilds then Nexus.JournalTab.OpenBuilds()
        elseif Nexus.WishlistEditor then Nexus.WishlistEditor.Show()end
    end)
    frame.targets=text(frame,20,-82,580,26);frame.permanent=text(frame,20,-112,580,28);frame.balance=text(frame,20,-144,580,34)
    frame.limitLabel=text(frame,20,-190,170,24,T("orb.label.maximum_this_run"))
    frame.limit=CreateFrame("EditBox",nil,frame,"InputBoxTemplate");frame.limit:SetSize(65,25);frame.limit:SetPoint("TOPLEFT",196,-188)
    if Nexus.Theme and Nexus.Theme.StyleInput then Nexus.Theme.StyleInput(frame.limit) end
    frame.limit:SetFrameLevel(32);frame.limit:SetAutoFocus(false);frame.limit:SetNumeric(true);frame.limit:SetMaxLetters(5)
    frame.limit:SetScript("OnEditFocusGained",function(self)if not self.editable or not frame:IsShown()then self:ClearFocus()end end)
    frame.limit:SetScript("OnEnterPressed",function(self)
        if not self.editable then self:ClearFocus();return end
        local ok,err=Nexus.OrbRuntime.SetLimit(tonumber(self:GetText()));self:ClearFocus();notify(ok,err)
    end)
    frame.limit:SetScript("OnEscapePressed",function(self)Nexus.OrbRuntime.CancelLimitEdit();self:ClearFocus();UI.Refresh()end)
    -- Typing (also the same number, a partial or an empty text) is the
    -- player's own amount. A refresh setting the box, or focus alone, is not.
    frame.limit:SetScript("OnTextChanged",function(self,userInput)
        if self.settingText or not self.editable then return end
        if userInput==true or self:HasFocus() then Nexus.OrbRuntime.EditLimitText(self:GetText()) end
    end)
    -- A button click does not take keyboard focus from the box: release it
    -- first, so the refresh shows the tracked amount instead of old typing.
    frame.max=button(frame,268,-188,48,T("orb.button.max"),function()frame.limit:ClearFocus();notify(Nexus.OrbRuntime.TrackBalance())end)
    frame.max:SetScript("OnEnter",function(self)
        if GameTooltip then GameTooltip:SetOwner(self,"ANCHOR_TOP");GameTooltip:SetText(T(MAX_TIP_KEY),1,1,1,1,true);GameTooltip:Show()end
    end)
    frame.max:SetScript("OnLeave",function()if GameTooltip then GameTooltip:Hide()end end)
    frame.max.tooltip=T(MAX_TIP_KEY)
    -- While a run is busy, Pause and Resume are separate buttons in Start's
    -- place, each with one fixed meaning: a repeated press of Pause can never
    -- become Resume. Each acts only when a fresh read offers it; the runtime
    -- then applies its own checks.
    frame.pause=button(frame,334,-188,58,T("orb.button.pause"),function()
        if not Nexus.OrbRuntime.Status().running then say(T("orb.status.not_paused_not_running"));return end
        notify(Nexus.OrbRuntime.Pause())
    end)
    frame.resume=button(frame,398,-188,62,T("orb.button.resume"),function()
        local s=Nexus.OrbRuntime.Status()
        if s.running then say(T("orb.status.not_resumed_running"));return end
        if not s.canResume then
            local t=s.state=="PAUSED" and s.resumeTarget or nil
            say(T(t and t.kind=="settle" and "orb.status.not_resumed_settle"
                or t and t.kind=="unavailable" and "orb.status.not_resumed_not_ready"
                or lostApproval(t) and "orb.status.not_resumed_lost_approval"
                or "orb.status.not_resumed_not_offered"))
            return
        end
        local held=reviewRefusal(s.resumeTarget)
        if held then say(held);return end
        notify(Nexus.OrbRuntime.Resume())
    end)
    frame.pause:Hide();frame.resume:Hide()
    frame.start=button(frame,334,-188,126,T("orb.button.start"),function()
        local s=Nexus.OrbRuntime.Status()
        if s.state=="FINISHED" and not confirmNewRun then
            -- The explicit preparation of a new run: its draft follows the
            -- confirmed balance again; the amount is shown for review.
            -- A refusal (for example a balance that became unknown after the
            -- render) arms nothing and changes nothing.
            frame.limit:ClearFocus()
            local prepared,why=Nexus.OrbRuntime.NewRunDraft()
            if not prepared then notify(nil,why);return end
            UI.Refresh()
            local amount=frame.limit:GetText();local v=tonumber(amount)
            if v==nil or v<1 or v>10000 or v~=math.floor(v) then
                -- A draft that follows the balance has no amount of its own:
                -- name the balance, not typing or Max.
                local d=Nexus.OrbRuntime.LimitDraft()
                local why="orb.status.start_needs_whole_maximum"
                if d.tracking and d.text==nil then
                    why=d.value==0 and "orb.status.start_balance_zero"
                        or "orb.status.start_balance_unavailable"
                end
                say(T(why))
                return
            end
            confirmNewRun=true;confirmAmount=amount;UI.Refresh();return
        end
        -- The Confirm click checks the reviewed amount itself: an amount
        -- changed since the review (typed, or not yet refreshed) needs a new
        -- review, whatever the refresh timing.
        if confirmNewRun and frame.limit:GetText()~=confirmAmount then
            confirmNewRun=false;confirmAmount=nil
            say(T("orb.status.max_changed_review"))
            return
        end
        confirmNewRun=false;confirmAmount=nil
        if s.running or s.state=="PAUSED" then notify(primary(nil));return end
        -- Start uses the amount shown, never a newer balance read at the click.
        local d=s.limitDraft or {}
        local shown=frame.limit:GetText()
        local n=tonumber(shown)
        if n==nil or n<1 or n~=math.floor(n) then
            say(T(d.tracking and "orb.status.start_balance_unavailable"
                or "orb.status.start_needs_whole_maximum"))
            return
        end
        -- Still the tracked amount this window showed: approve it as shown.
        -- Any other text is the player's own amount (the existing path).
        notify(primary(n,d.tracking and d.text==nil and shown==frame.limit.shownDraft,frame.historyReview))
    end)
    frame.stop=button(frame,470,-188,120,T("orb.button.stop"),function()notify(Nexus.OrbRuntime.Stop())end)
    -- Why Start would not start now, on the line right under the Start row
    -- (one line; the whole reason on hover). The click still checks again.
    frame.startWhy=text(frame,20,-213,580,12)
    frame.approval=text(frame,20,-227,580,34,T("orb.body.start_approval"))
    frame.usage=text(frame,20,-263,580,22);frame.status=text(frame,20,-289,580,74);frame.notice=text(frame,20,-364,440,24)
    -- Fixed boxes; a status or refusal longer than its box is complete in a tooltip.
    if Nexus.LayoutMetrics then
        frame.approvalHit=Nexus.LayoutMetrics.FullTextTooltip(frame.approval,frame)
        frame.startWhyHit=Nexus.LayoutMetrics.FullTextTooltip(frame.startWhy,frame)
        frame.usageHit=Nexus.LayoutMetrics.FullTextTooltip(frame.usage,frame)
        frame.statusHit=Nexus.LayoutMetrics.FullTextTooltip(frame.status,frame)
        frame.noticeHit=Nexus.LayoutMetrics.FullTextTooltip(frame.notice,frame)
        frame.balanceHit=Nexus.LayoutMetrics.FullTextTooltip(frame.balance,frame)
        frame.targetsHit=Nexus.LayoutMetrics.FullTextTooltip(frame.targets,frame)
        frame.planHit=Nexus.LayoutMetrics.FullTextTooltip(frame.plan,frame)
    end
    -- The same read-only explanation also serves ineligible restored receipts.
    frame.cont=button(frame,470,-364,130,T("orb.button.continue_open"),function()UI.ShowContinue()end)
    frame.cont:Hide()
    -- The deliberate review of a changed Resume target (see `review`). Review
    -- and Cancel review only record or clear it: nothing is resumed or spent.
    -- A click acts only on the exact target and action this button showed;
    -- a target that changed since the last refresh is never reviewed by it.
    frame.review=button(frame,470,-364,130,T("orb.button.review_target"),function()
        local shownKey,shownAction=frame.review.shownKey,frame.review.shownAction
        local t=Nexus.OrbRuntime.Status().resumeTarget
        local drawn=frame.review.drawnKey
        if not (changedTarget(t) and t.key~=nil) then
            review.key=nil;frame.notice:SetText(T("orb.status.review_none"))
        elseif drawn==nil or shownKey==nil or drawn~=t.key or shownKey~=t.key then
            -- The fresh target is not the one this button was drawn and shown
            -- for: neither review nor cancel it unseen. Withholding stays.
            review.key=nil
            frame.notice:SetText(T("orb.status.review_target_changed"))
        elseif not ((shownAction=="review" and reviewHeld(t)) or (shownAction=="cancel" and review.key==t.key)) then
            -- The action shown no longer matches the fresh review state: a
            -- stale Cancel review never becomes a review, nor the reverse.
            -- The review is left as it is.
            frame.notice:SetText(T("orb.status.review_state_changed"))
        elseif shownAction=="review" then
            review.key=t.key
            frame.notice:SetText(TF("orb.status.review_done",{target=quotedName(t)}))
        else
            review.key=nil;frame.notice:SetText(T("orb.status.review_cancelled"))
        end
        UI.Refresh()
    end)
    frame.review:Hide()
    frame.closeNotice=text(frame,20,-393,580,20,T("orb.note.close_keeps_run"))
    -- Help is the guided setup coach (Help.OpenHelp; native QA test.163008),
    -- which opens in this window's place: closing this window does not stop
    -- an approved run. Reference is the manual's Orbs page, above this window
    -- (Help's 40-42 band over this 30-33 one), which stays shown. Neither
    -- spends, starts or changes anything.
    frame.help=button(frame,20,-414,85,T("orb.button.help"),function()
        Nexus.Help.OpenHelp("orbs",function(opened)if opened then frame:Hide()end end)
    end)
    frame.reference=button(frame,340,-414,95,T("orb.button.reference"),function()Nexus.Help.OpenReference("orbs")end)
    frame.advancedToggle=button(frame,115,-414,95,T("orb.button.advanced"),function()
        advanced=not advanced;pinTopLeft(frame);UI.Refresh()
    end)
    -- Appearance is one shared choice (ui/Theme.lua: the same saved style and
    -- colour for the Nexus panel and these windows). It is chosen from the
    -- Nexus panel's Options > Appearance (design/current "Nexus Main Panel -
    -- Compact Redesign"), so this window no longer repeats it.
    -- The optional compact status (UI.ShowMini). It only shows that panel:
    -- this window stays as it is, and nothing is started or changed.
    frame.miniPanel=button(frame,220,-414,110,T("orb.button.mini_panel"),function()UI.ShowMini()end)
    frame.miniPanel:SetScript("OnEnter",function(self)
        if not GameTooltip then return end
        GameTooltip:SetOwner(self,"ANCHOR_TOP");GameTooltip:SetText(T("orb.tooltip.mini_panel_open"),1,1,1,1,true);GameTooltip:Show()
    end)
    frame.miniPanel:SetScript("OnLeave",function()if GameTooltip then GameTooltip:Hide()end end)
    frame.closeButton=button(frame,515,-414,85,T("orb.button.close"),function()frame:Hide()end)
    frame.advanced=CreateFrame("Frame",nil,frame);frame.advanced:Hide();frame.advanced:SetSize(590,205);frame.advanced:SetPoint("TOPLEFT",15,-446);frame.advanced:SetFrameLevel(31)
    -- Every row from the targets line down takes the room its text needs, so
    -- no fixed blank band stays: the targets, the locked-targets line only
    -- while it has words, and the balance (with its draft line) as measured
    -- (at most their former boxes; a longer text is whole on hover); then the
    -- Start row; Start's reason only while there is one (right under the
    -- Start row), the approval text at its full 34 units always, the usage
    -- and status as measured, the notice row only with a notice or its
    -- button, then the close notice, the button row and Advanced. With every
    -- box full this is the former 620 x 445 layout. Returns the window
    -- height. Only places and heights change; no text, control or action does.
    frame.flowBands=function(isAdvanced)
        local LM=Nexus.LayoutMetrics
        local function place(region,x,y) region:ClearAllPoints();region:SetPoint("TOPLEFT",frame,"TOPLEFT",x,-y) end
        local function measured(fs,width,low,high)
            if (fs:GetText() or "")=="" then fs:SetHeight(1);return 0 end
            if not (LM and LM.WrapHeight) then fs:SetHeight(high);return high end
            return (LM.WrapHeight(fs,width,low,high))
        end
        -- Under the Wishlist row (its text and My Builds end by y 80).
        local y=82
        place(frame.targets,20,y)
        local h=measured(frame.targets,580,12,26)
        if h>0 then y=y+h+4 end
        place(frame.permanent,20,y)
        h=measured(frame.permanent,580,12,28)
        if h>0 then y=y+h+4 end
        place(frame.balance,20,y)
        y=y+measured(frame.balance,580,12,34)+10
        -- The Start row: the maximum, Max, Start (or Pause and Resume) and Stop.
        place(frame.limitLabel,20,y+2);place(frame.limit,196,y);place(frame.max,268,y)
        place(frame.pause,334,y);place(frame.resume,398,y);place(frame.start,334,y);place(frame.stop,470,y)
        y=y+25
        place(frame.startWhy,20,y)
        local why=measured(frame.startWhy,580,12,12)
        if why>0 then y=y+12+2 end
        place(frame.approval,20,y);frame.approval:SetHeight(34);y=y+34+2
        place(frame.usage,20,y);y=y+measured(frame.usage,580,12,22)+4
        place(frame.status,20,y);y=y+measured(frame.status,580,12,74)+1
        local noticeH=measured(frame.notice,440,12,24)
        if frame.cont:IsShown() or frame.review:IsShown() then noticeH=math.max(noticeH,24) end
        place(frame.notice,20,y);place(frame.cont,470,y);place(frame.review,470,y)
        if noticeH>0 then y=y+noticeH+5 end
        place(frame.closeNotice,20,y);y=y+20+1
        for _,b in ipairs({{frame.help,20},{frame.advancedToggle,115},{frame.miniPanel,220},
            {frame.reference,340},{frame.closeButton,515}}) do place(b[1],b[2],y) end
        y=y+24
        if isAdvanced then place(frame.advanced,15,y+8);y=y+8+205 end
        frame._bandsBottom=y
        local height=y+9
        if math.abs((tonumber(frame:GetHeight()) or 0)-height)>0.5 then pinTopLeft(frame);frame:SetHeight(height) end
        return height
    end
    local af=frame.advanced
    button(af,5,-4,100,T("orb.button.recheck"),function()notify(Nexus.OrbRuntime.Recheck())end)
    frame.clearExclusions=button(af,116,-4,195,T("orb.button.clear_exclusions"),function()notify(Nexus.OrbRuntime.ClearExclusions())end)
    frame.sourceRows={}
    for i=1,4 do
        local r={};r.label=text(af,5,-38-(i-1)*28,455,25)
        if Nexus.LayoutMetrics then r.hit=Nexus.LayoutMetrics.FullTextTooltip(r.label,af) end
        r.exclude=button(af,468,-35-(i-1)*28,100,T("orb.button.exclude"),function()if r.key then notify(Nexus.OrbRuntime.Exclude(r.key,true))end end)
        frame.sourceRows[i]=r
    end
    frame.sourcePage=text(af,5,-151,250,23)
    button(af,285,-151,85,T("orb.button.page_previous"),function()sourcePage=math.max(1,sourcePage-1);UI.Refresh()end)
    button(af,380,-151,85,T("orb.button.page_next"),function()sourcePage=sourcePage+1;UI.Refresh()end)
    frame.assignmentNote=text(af,5,-180,565,31)
    frame.mutations={frame.start,frame.stop,frame.assigned,frame.clearExclusions,frame.max,frame.pause,frame.resume,frame.review}
    for _,r in ipairs(frame.sourceRows)do frame.mutations[#frame.mutations+1]=r.exclude end
    -- Only the run text and child controls belong to this page. Root Texture
    -- regions can be window backdrop/decorative artwork and must remain shown
    -- on history. The title, tabs and history are created after this capture.
    frame.runWidgets={}
    do
        local seen={}
        for _,list in ipairs({{frame:GetRegions()},{frame:GetChildren()}})do
            for _,w in ipairs(list)do
                if not seen[w] and (w:GetObjectType()~="Texture") then
                    seen[w]=true;frame.runWidgets[#frame.runWidgets+1]=w
                end
            end
        end
    end
    frame.title=frame:CreateFontString(nil,"OVERLAY","GameFontNormal")
    frame.title:SetPoint("TOPLEFT",20,-17);frame.title:SetSize(320,20);frame.title:SetJustifyH("LEFT")
    frame.title:SetText(T("orb.title.window"))
    frame.runTab=button(frame,352,-12,116,T("orb.tab.run_controls"),function()showPage("run");UI.Refresh()end)
    frame.historyTab=button(frame,474,-12,110,T("orb.tab.run_history"),function()UI.ShowLog()end)
    selected(frame.runTab,true)
    inactiveControls()
    frame:SetScript("OnShow",function()UI.Refresh()end)
    -- Closing the window is the one place an armed review is cancelled; it
    -- also closes the history page and its copy view, and clears a target
    -- review.
    frame:SetScript("OnHide",function()
        editLimit(false);confirmNewRun=false;confirmAmount=nil;review.key=nil
        frame.review.shownKey,frame.review.shownAction=nil,nil
        if logFrame then logFrame:Hide()end
    end)
    local elapsed=0;frame:SetScript("OnUpdate",function(_,dt)elapsed=elapsed+(dt or 0);if elapsed>=.25 then elapsed=0;UI.Refresh()end end)
    styled(frame,0.96)
    frame:Hide();UISpecialFrames=UISpecialFrames or {};UISpecialFrames[#UISpecialFrames+1]="NexusOrbPanel"
end
local RESULT_TONE={Confirmed={.55,.85,.55},["Not sent"]={.95,.5,.45},
    Unconfirmed={.95,.78,.35},Paused={.95,.78,.35}}
local function logRowTone(result)
    if result.confirmed then return RESULT_TONE.Confirmed end
    if result.refused then return RESULT_TONE["Not sent"] end
    if result.unresolved then return RESULT_TONE.Unconfirmed end
    return {.82,.84,.88}
end
-- Display boundary of the history projection (ui/OrbHistory.lua): its
-- labels stay English for the copied report; each code-owned one carries the
-- key of its meaning, said here in the active language. Recorded names and
-- recorded reasons are data and are shown as recorded.
local function resultText(result)
    local keys=Nexus.OrbHistory and Nexus.OrbHistory.RESULT_KEYS
    local key=keys and result and keys[result.status]
    if key then return T(key) end
    if result and result.label~=nil then return tostring(result.label) end
    return T("orb.value.result_unconfirmed")
end
local function rarityText(rarity)
    if rarity and rarity.labelKey then return T(rarity.labelKey) end
    return rarity and rarity.label or ""
end
-- The complete name of an Echo cell (escaped as the projection escapes it).
local function echoName(cell)
    local shown
    if cell.textKey then shown=T(cell.textKey)
    elseif cell.unknownId~=nil then shown=TF("orb.value.echo_unknown",{id=tostring(cell.unknownId)})
    else
        local whole=cell.fullName or cell.full
        return cell.proposed and TF("orb.value.echo_proposed",{name=whole}) or whole
    end
    return cell.proposed and TF("orb.value.echo_proposed",{name=shown}) or shown
end
local function withRarity(echo,rarity)
    return TF("orb.value.echo_with_rarity",{name=echo,rarity=rarityText(rarity)})
end
local function reasonFull(reason)
    if reason.textKey then return T(reason.textKey) end
    return reason.full
end
local function reasonCell(reason)
    if reason.textKey then return T(reason.textKey) end
    return reason.label
end
local function reasonDetail(reason)
    if reason.detailKey then return T(reason.detailKey) end
    return reason.detail
end
local function logResultCell(result)
    local parts=Nexus.Readout and Nexus.Readout.StatusParts
        and Nexus.Readout.StatusParts(result.status) or nil
    local glyph=parts and (parts.glyph.." ") or ""
    local label=resultText(result)
    -- The result column is only 105 units wide. Keep long words complete and
    -- on two lines instead of clipping the status at enlarged UI scale.
    if #label>13 then
        local first,rest=label:match("^(%S+)%s+(.+)$")
        if first then return glyph..first.."\n"..rest end
    end
    return glyph..label
end
local function logCell(fs,label,color)
    fs:SetText(label or "")
    if color then pcall(fs.SetTextColor,fs,color[1],color[2],color[3]) end
end
-- Character-safe shortening, so a cut never splits a multi-byte letter.
local function shorten(value,limit)
    if Nexus.LayoutMetrics and Nexus.LayoutMetrics.Truncate then
        return Nexus.LayoutMetrics.Truncate(value,limit)
    end
    return (Nexus.OrbHistory.Ellipsis(value,limit))
end
-- Two lines per Echo cell: the name, then the rarity word. The colour repeats
-- the rarity; it is never the only cue. A proposed replacement keeps its
-- marker on the rarity line, so shortening a long name cannot drop it. The
-- name is cut from the unescaped recorded text and its pipes are doubled
-- after the cut, so the cut never splits a letter or an escaped "||".
local CELL_LETTERS=30
local function logEchoText(cell)
    if not cell then return "" end
    local base=cell.text
    if cell.textKey then base=T(cell.textKey)
    elseif cell.unknownId~=nil then base=TF("orb.value.echo_unknown",{id=tostring(cell.unknownId)}) end
    local shown=(shorten(tostring(base or ""),CELL_LETTERS):gsub("|","||"))
    if cell.recorded==false then return shown end
    local rarity=rarityText(cell.rarity)
    return shown.."\n"..(cell.proposed and TF("orb.value.rarity_proposed",{rarity=rarity}) or rarity)
end
local function logDetailText(details,history)
    if not details then return T("orb.body.history_select_operation") end
    local lines={}
    local function add(text) lines[#lines+1]=text end
    add(TF("orb.body.history_operation",{number=tostring(details.ordinal),result=resultText(details.result)}))
    add(T("orb.heading.history_timeline"))
    for _,stage in ipairs(details.timeline or {}) do
        local said=stage.textKey and T(stage.textKey) or stage.text
        local line=Nexus.Readout and Nexus.Readout.StatusText
            and Nexus.Readout.StatusText(stage.kind,said) or said
        add("  "..line)
    end
    if details.offers then
        local parts={}
        for _,offer in ipairs(details.offers) do
            local echo=withRarity(echoName(offer),offer.rarity)
            parts[#parts+1]=offer.confirmed and TF("orb.value.offer_received",{echo=echo})
                or (offer.selected and TF("orb.value.offer_selected",{echo=echo}) or echo)
        end
        add(T("orb.label.history_offered").." "..table.concat(parts,"   "))
    else
        add(T("orb.label.history_offered").." "..(details.offersNote~=nil and T("orb.value.offer_not_recorded") or tostring(details.offersNote)))
    end
    local detail=reasonDetail(details.reason)
    add(T("orb.label.history_why").." "..reasonFull(details.reason)..(detail and (" - "..detail) or ""))
    if details.proposedSource then
        add(TF("orb.body.history_proposed_source",{echo=withRarity(echoName(details.proposedSource),details.proposedSource.rarity)}))
    elseif details.consumed then
        add(TF("orb.body.history_consumed_source",{echo=withRarity(echoName(details.consumed),details.consumed.rarity)}))
    end
    if details.eligibleSurplus~=nil then
        add(TF("orb.body.history_eligible_surplus",{value=tostring(details.eligibleSurplus)}))
    end
    if details.recycled then add(T("orb.body.history_recycle_candidate")) end
    if details.note then
        -- A note the runtime recorded: its raw text says the meaning it maps to.
        local raw=details.technical and details.technical.reason
        local shown,known=orbPhrase(raw)
        add(T("orb.label.recorded_note").." "..(known and shown or details.note))
    end
    local t=details.technical
    add(TF("orb.body.history_technical",{serial=tostring(t.serial or details.serial),state=tostring(t.state),
        source=tostring(t.sourceKey),selected=tostring(t.selectedKey),kind=tostring(t.selectionKind),
        obtained=tostring(t.obtained)})
        ..(details.sinceStart and ("; "..TF("orb.body.history_since_start",{seconds=string.format("%.1f",details.sinceStart)})) or ""))
    return table.concat(lines,"\n")
end
-- The whole recorded row for its tooltip: complete names, the proposed
-- marker, the reason with its explanation, the result and any recorded note.
local function logRowTip(model,history)
    local lines={}
    local replacement=model.replacement
    lines[#lines+1]=TF("orb.tooltip.history_replaced",{echo=withRarity(echoName(model.source),model.source.rarity)})
    if replacement.recorded~=false then
        local echo=withRarity(echoName(replacement),replacement.rarity)
        lines[#lines+1]=replacement.proposed and TF("orb.tooltip.history_replacement_proposed",{echo=echo})
            or TF("orb.tooltip.history_replacement",{echo=echo})
    else
        lines[#lines+1]=TF("orb.tooltip.history_replacement",{echo=echoName(replacement)})
    end
    lines[#lines+1]=T("orb.label.history_why_selected").." "..reasonFull(model.reason)
    local detail=reasonDetail(model.reason)
    if detail then lines[#lines+1]=detail end
    lines[#lines+1]=TF("orb.tooltip.history_result",{result=resultText(model.result)})
    local note=model.entry and model.entry.reason
    if note then
        local shown,known=orbPhrase(note)
        lines[#lines+1]=T("orb.label.recorded_note").." "..(known and shown or history.Display(note))
    end
    return lines
end
function refreshLog(force)
    if not logFrame or not logFrame:IsShown() then return end
    local history=logHistory()
    local run=logPageView(logPage)
    local key=logKey(run)
    local runKey=logRunKey(run)
    if logLabels.key~=runKey then logLabels.key,logLabels.byId=runKey,{} end
    local total=run and run.total or 0
    local pages=history.Pages(total,LOG_ROWS)
    if logPage>pages then
        logPage=pages;logSelection=nil;run=logPageView(logPage);key=logKey(run)
    end
    local header=history.Header(run)
    -- The header in the active language, from the same recorded fields the
    -- projection's English header reads (history.Header keeps the English).
    local stateKeys=history.RUN_STATE_KEYS or {}
    local function stateLabel(state)
        if stateKeys[state] then return T(stateKeys[state]) end
        if state==nil then return T("orb.value.state_unknown") end
        return tostring(state)
    end
    -- A shortened Wishlist name is complete in the header's tooltip.
    local function headerText(wishlist)
        local recorded=stateLabel(run.state)
        local status=recorded
        if run.liveState~=nil and run.liveState~=run.state then
            status=TF("orb.status.history_now",{now=stateLabel(run.liveState),recorded=recorded})
        end
        local spent,limit=tonumber(run.spent) or 0,tonumber(run.limit) or 0
        local usage=TF("orb.status.usage_head",{spent=N(spent),limit=TF("orb.value.limit_approved",{count=N(limit)})})
            ..((tonumber(run.uncertain) or 0)>0 and ("; "..TF("orb.status.segment_unknown_exposure",{value=tostring(run.uncertain)})) or "")
            ..((tonumber(run.unconfirmedResults) or 0)>0 and ("; "..TF("orb.status.segment_unconfirmed_outcomes",{value=tostring(run.unconfirmedResults)})) or "")
        return TF("orb.label.history_run",{id=tostring(run.runId)}).." - "..wishlist.."\n"..status.."\n"..usage
            ..(header.increased and (" "..T("orb.status.history_max_increased")) or "")
    end
    if header.empty then setFull(logFrame.header,T("orb.status.history_none_started"))
    elseif run.wishlist==nil then
        local none=T("orb.value.wishlist_none")
        setFull(logFrame.header,headerText(none),headerText(none))
    else setFull(logFrame.header,headerText(header.wishlist),headerText(header.wishlistFull)) end
    local warnings={}
    if header.pending then
        local reserved=tonumber(run.reserved) or 0
        warnings[#warnings+1]=TF(reserved==1 and "orb.status.history_pending_one" or "orb.status.history_pending_many",{count=N(reserved)})
    end
    if header.truncated then warnings[#warnings+1]=T("orb.status.history_truncated") end
    logFrame.warning:SetText(table.concat(warnings,"  "))
    -- The run shown is marked by a bar as well as by its disabled button.
    enable(logFrame.current,logView~="current")
    enable(logFrame.previous,logView~="previous" and header.hasPrevious)
    selected(logFrame.current,logView=="current");selected(logFrame.previous,logView=="previous")
    local rows=history.Rows(run,logResolve)
    local selectedModel=nil
    for index,row in ipairs(logFrame.rows) do
        local model=rows[index]
        row.serial=model and model.serial or nil
        if model then
            row:Show()
            logCell(row.index,tostring(model.ordinal)..".")
            logCell(row.source,logEchoText(model.source),model.source.rarity.color)
            logCell(row.replacement,logEchoText(model.replacement),model.replacement.rarity.color)
            logCell(row.reason,reasonCell(model.reason))
            logCell(row.result,logResultCell(model.result),logRowTone(model.result))
            row.detail=reasonDetail(model.reason)
            row.full=withRarity(echoName(model.source),model.source.rarity)
                .."  ->  "..(model.replacement.recorded~=false
                    and withRarity(echoName(model.replacement),model.replacement.rarity) or echoName(model.replacement))
            row.tip=logRowTip(model,history)
            row.icon:SetTexture(model.source.icon or "")
            row.resultIcon:SetTexture(model.replacement.icon or "")
            if logSelection and model.serial==logSelection then
                selectedModel=model;row.highlight:Show()
            else row.highlight:Hide() end
        else
            row:Hide();row.highlight:Hide();row.detail=nil;row.full=nil;row.tip=nil
            logCell(row.index,"");logCell(row.source,"");logCell(row.replacement,"")
            logCell(row.reason,"");logCell(row.result,"")
        end
    end
    if logSelection and not selectedModel then logSelection=nil end
    local details=selectedModel and history.Details(selectedModel.entry,logResolve,run and run.startedAt) or nil
    logFrame.details:SetText(logDetailText(details,history))
    -- The scrolled child is as tall as the measured details, and the footer
    -- sits below the viewport, so every line of a long operation is reachable.
    if Nexus.LayoutMetrics then
        logFrame.detailChild:SetHeight(Nexus.LayoutMetrics.WrapHeight(logFrame.details,680,LOG_BANDS.details.h))
    end
    do
        -- history.PageLabel's meaning in the active language.
        local bounded=(run and run.truncated) and (" "..T("orb.status.history_page_bounded")) or ""
        if total==0 then logFrame.page:SetText(T("orb.status.history_page_none")..bounded)
        else
            local first=(math.max(1,logPage)-1)*LOG_ROWS+1
            logFrame.page:SetText(TF("orb.status.history_page_range",{first=N(first),
                last=N(math.min(total,first+LOG_ROWS-1)),total=N(total)})..bounded)
        end
    end
    enable(logFrame.prev,logPage>1)
    enable(logFrame.next,logPage<pages)
    -- The page the player is reading stays where it is; new operations are
    -- announced instead of moving them.
    local seen=logSeen[tostring(logView)..":"..tostring(run and run.runId)]
    if seen and total>seen and logPage<pages then
        logFrame.note:SetText(TF("orb.status.history_new_operations",{count=N(total-seen)}))
    else
        logFrame.note:SetText(T("orb.note.history_session"))
    end
    logSeen[tostring(logView)..":"..tostring(run and run.runId)]=total
    logRendered=key
end
-- Cheap bounded check: one header read with a single entry, never the whole
-- run. It re-renders only when the shown history actually changed.
local function logVisibleCheck()
    if not logFrame or not logFrame:IsShown() then return end
    local probe=Nexus.OrbRuntime.RunLog(logView,1,1)
    if logKey(probe)~=logRendered then refreshLog() end
end
local function logReportText(technical)
    local run=Nexus.OrbRuntime.RunLog(logView)
    local key=logKey(run)..(technical and "|tech" or "|plain")
    if logCopy.key~=key or not logCopy.text then
        -- The whole selected run is serialized only here, for the text the
        -- player asked for, and only when it changed since the last request.
        logCopy.key,logCopy.text=key,logHistory().Report(run,logResolve,technical)
    end
    return logCopy.text
end
-- The copy view is a panel over the history page of the same window. It
-- closes with that page and with the window.
local function ensureCopyView()
    if logCopyFrame then return logCopyFrame end
    local f=CreateFrame("Frame","NexusOrbHistoryCopy",logFrame);f:Hide()
    logCopyFrame=f
    f:SetSize(640,460);f:SetPoint("CENTER",logFrame,"CENTER",0,0)
    f:SetFrameLevel(logFrame:GetFrameLevel()+20);f:EnableMouse(true)
    f:SetBackdrop({bgFile="Interface\\Buttons\\WHITE8X8",edgeFile="Interface\\Tooltips\\UI-Tooltip-Border",edgeSize=14,insets={left=4,right=4,top=4,bottom=4}})
    f:SetBackdropColor(.035,.04,.05,1)
    text(f,20,-14,600,22,T("orb.heading.copy_report"))
    text(f,20,-36,600,32,T("orb.body.copy_report_help"))
    f.check=CreateFrame("CheckButton","NexusOrbHistoryTechnical",f,"UICheckButtonTemplate")
    f.check:SetSize(22,22);f.check:SetPoint("TOPLEFT",20,-68)
    f.checkLabel=text(f,46,-72,400,20,T("orb.label.include_technical"))
    f.check:SetScript("OnClick",function(self)
        -- GetChecked answers 1 or nil on this client, never a boolean.
        f.editBox:SetText(logReportText(self:GetChecked() and true or false))
        f.editBox:SetCursorPosition(0)
    end)
    f.scroll=CreateFrame("ScrollFrame","NexusOrbHistoryCopyScroll",f,"UIPanelScrollFrameTemplate")
    f.scroll:SetPoint("TOPLEFT",20,-96);f.scroll:SetSize(580,300)
    f.editBox=CreateFrame("EditBox",nil,f.scroll)
    f.editBox:SetMultiLine(true)
    -- The dedicated copy field is sized for the whole report: no name-limited
    -- popup, and nothing is silently cut.
    f.editBox:SetMaxLetters(0)
    f.editBox:SetAutoFocus(false)
    f.editBox:SetFontObject(ChatFontNormal)
    f.editBox:SetWidth(566)
    f.editBox:SetScript("OnEscapePressed",function(self)self:ClearFocus()end)
    f.scroll:SetScrollChild(f.editBox)
    button(f,20,-410,110,T("orb.button.select_all"),function()f.editBox:SetFocus();f.editBox:HighlightText()end)
    button(f,140,-410,110,T("orb.button.clear_focus"),function()f.editBox:ClearFocus()end)
    button(f,515,-410,85,T("orb.button.close"),function()f:Hide()end)
    f:SetScript("OnHide",function()f.editBox:ClearFocus()end)
    styled(f,0.98)
    return f
end
function ensureLog()
    if logFrame then return end
    logFrame=CreateFrame("Frame","NexusOrbRunLog",frame);logFrame:Hide()
    logFrame:SetSize(LOG_W,LOG_H);logFrame:SetPoint("TOPLEFT",frame,"TOPLEFT",0,-LOG_TOP)
    logFrame:SetFrameLevel(frame:GetFrameLevel()+1);logFrame:EnableMouse(true)
    logFrame.current=button(logFrame,20,-4,120,T("orb.button.history_current"),function()
        if logView=="current" then return end
        logView="current";logPage=1;logSelection=nil;refreshLog()
    end)
    logFrame.previous=button(logFrame,146,-4,120,T("orb.button.history_previous"),function()
        if logView=="previous" then return end
        logView="previous";logPage=1;logSelection=nil;refreshLog()
    end)
    logFrame.header=text(logFrame,280,LOG_BANDS.header.y,460,LOG_BANDS.header.h)
    logFrame.warning=text(logFrame,20,LOG_BANDS.warning.y,720,LOG_BANDS.warning.h)
    if Nexus.LayoutMetrics then
        logFrame.headerHit=Nexus.LayoutMetrics.FullTextTooltip(logFrame.header,logFrame)
        logFrame.warningHit=Nexus.LayoutMetrics.FullTextTooltip(logFrame.warning,logFrame)
    end
    -- The heading row is a frame on the row origin, and each heading is one
    -- font string at its own column's x and width. Same numbers, one source.
    logFrame.columns=CreateFrame("Frame",nil,logFrame)
    logFrame.columns:SetSize(LOG_ROW_W,LOG_BANDS.headings.h)
    logFrame.columns:SetPoint("TOPLEFT",LOG_ROW_X,LOG_BANDS.headings.y)
    logFrame.columnHeadings={}
    for _,column in ipairs(LOG_COLUMNS) do
        local heading=text(logFrame.columns,column.x,0,column.w,LOG_BANDS.headings.h,
            column.text and T(column.text) or column.label)
        heading:SetJustifyV("MIDDLE")
        logFrame.columnHeadings[column.key]=heading
    end
    logFrame.rows={}
    local rowH=LOG_BANDS.rows.h
    for i=1,LOG_ROWS do
        local row=CreateFrame("Button",nil,logFrame)
        row:SetSize(LOG_ROW_W,rowH);row:SetPoint("TOPLEFT",LOG_ROW_X,LOG_BANDS.rows.y-(i-1)*rowH)
        row:SetFrameLevel(logFrame:GetFrameLevel()+1)
        row.highlight=row:CreateTexture(nil,"BACKGROUND")
        row.highlight:SetTexture("Interface\\Buttons\\WHITE8X8")
        row.highlight:SetAllPoints(row);row.highlight:SetVertexColor(.16,.24,.29,.5)
        row.highlight:Hide()
        -- Pointer feedback: the client shows this layer only under the mouse.
        row.hover=row:CreateTexture(nil,"HIGHLIGHT")
        row.hover:SetTexture("Interface\\Buttons\\WHITE8X8")
        row.hover:SetAllPoints(row);row.hover:SetVertexColor(.30,.40,.52,.18)
        row.separator=row:CreateTexture(nil,"BACKGROUND")
        row.separator:SetTexture("Interface\\Buttons\\WHITE8X8")
        row.separator:SetSize(LOG_ROW_W,1);row.separator:SetPoint("BOTTOMLEFT",0,0)
        row.separator:SetVertexColor(.22,.24,.28,.55)
        local columns={}
        for _,column in ipairs(LOG_COLUMNS) do columns[column.key]=column end
        row.index=text(row,columns.index.x,-4,columns.index.w,18)
        row.icon=row:CreateTexture(nil,"ARTWORK");row.icon:SetSize(18,18)
        row.icon:SetPoint("TOPLEFT",columns.source.iconX,-4)
        row.source=text(row,columns.source.x,-4,columns.source.w,34)
        row.resultIcon=row:CreateTexture(nil,"ARTWORK");row.resultIcon:SetSize(18,18)
        row.resultIcon:SetPoint("TOPLEFT",columns.replacement.iconX,-4)
        row.replacement=text(row,columns.replacement.x,-4,columns.replacement.w,34)
        row.reason=text(row,columns.reason.x,-4,columns.reason.w,34)
        row.result=text(row,columns.result.x,-4,columns.result.w,34)
        row:SetScript("OnClick",function(self)
            -- Reading only: this selects a row for display and nothing else.
            if logSelection==self.serial then logSelection=nil
            else logSelection=self.serial end
            refreshLog()
        end)
        row:SetScript("OnEnter",function(self)
            -- A shortened cell keeps its whole recorded value here, wrapped.
            if not GameTooltip or (not self.detail and not self.full) then return end
            GameTooltip:SetOwner(self,"ANCHOR_TOP")
            local lines=self.tip
            if lines and lines[1] then
                GameTooltip:SetText(lines[1],1,1,1,1,true)
                for index=2,#lines do GameTooltip:AddLine(lines[index],.9,.9,.9,true) end
            else
                GameTooltip:SetText(self.full or T("orb.tooltip.history_why_fallback"),1,1,1,1,true)
                if self.detail then GameTooltip:AddLine(self.detail,1,1,1,true) end
            end
            GameTooltip:Show()
        end)
        row:SetScript("OnLeave",function() if GameTooltip then GameTooltip:Hide() end end)
        row:Hide()
        logFrame.rows[i]=row
    end
    logFrame.detailScroll=CreateFrame("ScrollFrame","NexusOrbHistoryDetailScroll",
        logFrame,"UIPanelScrollFrameTemplate")
    logFrame.detailScroll:SetPoint("TOPLEFT",20,LOG_BANDS.details.y)
    logFrame.detailScroll:SetSize(700,LOG_BANDS.details.h)
    logFrame.detailChild=CreateFrame("Frame",nil,logFrame.detailScroll)
    logFrame.detailChild:SetSize(680,LOG_BANDS.details.h)
    logFrame.details=text(logFrame.detailChild,0,0,680,400)
    logFrame.detailScroll:SetScrollChild(logFrame.detailChild)
    local footerY=LOG_BANDS.footer.y
    logFrame.page=text(logFrame,20,footerY-2,300,22)
    logFrame.prev=button(logFrame,320,footerY,85,T("orb.button.page_previous"),function()
        if logPage<=1 then return end
        logPage=logPage-1;logSelection=nil;refreshLog()
    end)
    logFrame.next=button(logFrame,410,footerY,85,T("orb.button.page_next"),function()
        logPage=logPage+1;logSelection=nil;refreshLog()
    end)
    button(logFrame,500,footerY,115,T("orb.button.copy_report"),function()
        local view=ensureCopyView()
        view:Show()
        view.editBox:SetText(logReportText(view.check:GetChecked() and true or false))
        view.editBox:SetCursorPosition(0)
    end)
    -- Close closes the whole Orb window, like Escape.
    button(logFrame,625,footerY,95,T("orb.button.close"),function()frame:Hide()end)
    logFrame.note=text(logFrame,20,LOG_BANDS.note.y,720,LOG_BANDS.note.h,Nexus.OrbHistory and T("orb.note.history_session") or "")
    logFrame:SetScript("OnShow",function()refreshLog()end)
    logFrame:SetScript("OnHide",function() if logCopyFrame then logCopyFrame:Hide() end end)
    local elapsed=0
    logFrame:SetScript("OnUpdate",function(_,dt)
        -- Nothing runs while hidden; visible, this is one bounded header read.
        elapsed=elapsed+(dt or 0);if elapsed>=.5 then elapsed=0;logVisibleCheck() end
    end)
    if Nexus.Theme and Nexus.Theme.StyleTree then Nexus.Theme.StyleTree(logFrame) end
end
UI.LOG_BANDS,UI.LOG_SIZE,UI.RUN_SIZE={},{w=LOG_W,h=LOG_H,top=LOG_TOP},{w=RUN_W,h=RUN_H,advanced=RUN_H_ADVANCED}
for key,band in pairs(LOG_BANDS)do UI.LOG_BANDS[key]={y=band.y,h=band.h}end
-- The page shown now: "run" or "history".
function UI.Page() return page end
-- Opens the window on its history page. Reading only.
function UI.ShowLog()
    ensure();showPage("history");frame:Show();logFrame:Show();refreshLog();return logFrame
end

-- 035: Continue with an unconfirmed outcome. Reading and opening this window send nothing.
-- Check starts the strict read-only check; Continue, enabled only for the current ready token,
-- is the player's explicit confirmation; Cancel and closing the window cancel a check. The
-- text is the runtime's own (what was observed, what Continue does, what stays uncertain).
local contFrame
local function contRefresh()
    if not contFrame or not contFrame:IsShown()then return end
    local v=Nexus.OrbRuntime.ContinueView()
    contFrame.title:SetText(T((v.eligible==true or v.stage=="checking" or v.stage=="ready")
        and "orb.title.continue_unconfirmed" or "orb.title.unresolved_action"))
    contFrame.token=v.token
    contFrame.body:SetText(truthful(v.text) or "")
    local idle=v.stage=="idle" or v.stage=="refused" or v.stage=="held"
    local active=v.stage=="checking" or v.stage=="ready"
    enable(contFrame.check,v.eligible==true and idle)
    enable(contFrame.go,v.stage=="ready" and v.token~=nil)
    enable(contFrame.cancel,active)
    contFrame.state:SetText(T(v.stage=="ready" and "orb.status.continue_state_ready"
        or v.stage=="checking" and "orb.status.continue_state_checking"
        or v.stage=="done" and "orb.status.continue_state_done"
        or v.stage=="refused" and "orb.status.continue_state_refused"
        or (v.eligible and "orb.status.continue_state_unchecked" or "orb.status.continue_state_unavailable")))
    -- A record restored after a reload: its saved facts are kept, but this
    -- session's history has none of the steps before the reload. Said only
    -- when the session history really is empty (a bounded header read).
    local log=v.explanation==true and Nexus.OrbRuntime.RunLog("current",1,0) or nil
    contFrame.history:SetText(log and log.runId==nil and Nexus.OrbHistory and T("orb.note.history_reload_cleared") or "")
end
local function ensureContinue()
    if contFrame then return end
    local f=CreateFrame("Frame","NexusOrbContinue",UIParent);contFrame=f;f:Hide()
    f:SetSize(580,330);f:SetPoint("CENTER",UIParent,"CENTER",30,10)
    f:SetFrameStrata("DIALOG");f:SetFrameLevel(50);f:EnableMouse(true);f:SetMovable(true);f:SetClampedToScreen(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart",function(self)self:StartMoving()end)
    f:SetScript("OnDragStop",function(self)self:StopMovingOrSizing()end)
    f:SetBackdrop({bgFile="Interface\\Buttons\\WHITE8X8",edgeFile="Interface\\Tooltips\\UI-Tooltip-Border",edgeSize=14,insets={left=4,right=4,top=4,bottom=4}})
    f:SetBackdropColor(.035,.04,.05,1)
    f.title=text(f,20,-14,540,22,T("orb.title.unresolved_action"))
    f.state=text(f,20,-40,540,20)
    f.body=text(f,20,-66,540,170)
    f.notice=text(f,20,-240,540,22)
    -- Fixed boxes; text longer than its box is complete in a tooltip.
    if Nexus.LayoutMetrics then
        f.bodyHit=Nexus.LayoutMetrics.FullTextTooltip(f.body,f)
        f.noticeHit=Nexus.LayoutMetrics.FullTextTooltip(f.notice,f)
    end
    f.check=button(f,20,-282,150,T("orb.button.continue_check"),function()
        local ok,why=Nexus.OrbRuntime.ContinueBegin()
        f.notice:SetText(ok and "" or truthful(Nexus.OrbRuntime.ContinueReason(why)))
        contRefresh()
    end)
    f.go=button(f,180,-282,130,T("orb.button.continue_confirm"),function()
        -- The token this window showed, never a newer one: a stale click is refused.
        local ok,why=Nexus.OrbRuntime.ContinueConfirm(f.token)
        f.notice:SetText(ok and "" or truthful(Nexus.OrbRuntime.ContinueReason(why)))
        UI.Refresh();contRefresh()
    end)
    f.cancel=button(f,320,-282,90,T("orb.button.continue_cancel"),function()
        Nexus.OrbRuntime.ContinueCancel();f.notice:SetText("");contRefresh()
    end)
    button(f,480,-282,80,T("orb.button.close"),function()f:Hide()end)
    f.history=text(f,20,-308,540,18)
    if Nexus.LayoutMetrics then f.historyHit=Nexus.LayoutMetrics.FullTextTooltip(f.history,f) end
    f:SetScript("OnShow",function()contRefresh()end)
    -- Closing the window (also with Escape) cancels a check: no token outlives its window.
    f:SetScript("OnHide",function()
        local v=Nexus.OrbRuntime.ContinueView()
        if v.stage=="checking" or v.stage=="ready" then Nexus.OrbRuntime.ContinueCancel()end
    end)
    local elapsed=0
    f:SetScript("OnUpdate",function(_,dt)elapsed=elapsed+(dt or 0);if elapsed>=.25 then elapsed=0;contRefresh()end end)
    styled(f,0.96)
    UISpecialFrames=UISpecialFrames or {};UISpecialFrames[#UISpecialFrames+1]="NexusOrbContinue"
end
function UI.ShowContinue()
    if Nexus.OrbRuntime.ContinueView().liveRecovery then return nil end
    ensureContinue();contFrame:Show();contRefresh();return contFrame
end
do
    local refreshPanel=UI.Refresh
    function UI.Refresh(...)
        local perf=Nexus.Performance
        if perf and type(perf.MeasureDiagnostic)=="function" then return perf.MeasureDiagnostic("orb.panel",refreshPanel,...) end
        return refreshPanel(...)
    end
end
-- Opens the window on its run page.
function UI.Show()ensure();showPage("run");frame:Show();UI.Refresh();return frame end
function UI.Hide()if frame then frame:Hide()end end

-- Compact main-panel controls remain usable when the detailed window is hidden.
-- The ticker reads compact state only. It never advances an operation.
function UI.AttachMainPanel(parent)
    if parent._orbControls then return parent._orbControls end
    local f=CreateFrame("Frame",nil,parent);parent._orbControls=f
    f:SetPoint("TOPLEFT",parent,"BOTTOMLEFT",0,-2);f:SetSize(parent:GetWidth(),100);f:SetFrameLevel(parent:GetFrameLevel()+3)
    f:SetBackdrop({bgFile="Interface\\Buttons\\WHITE8X8"});f:SetBackdropColor(.035,.04,.05,.95)
    f.summary=text(f,8,-6,252,52)
    -- This strip is a child of the main panel and shown with it, so it is part
    -- of that panel's text: its words take the panel's own secondary role (11
    -- units on the native reference, LayoutMetrics "secondary") on this label
    -- only. No shared font object and no font of the Orb window is changed.
    if Nexus.LayoutMetrics and Nexus.LayoutMetrics.FontObject then
        pcall(f.summary.SetFontObject,f.summary,Nexus.LayoutMetrics.FontObject("secondary"))
    end
    -- The strip's words carry no count (f.refresh); the run's complete
    -- numbered text is on this hover.
    if Nexus.LayoutMetrics then f.summaryHit=Nexus.LayoutMetrics.FullTextTooltip(f.summary,f) end
    -- The legacy one-button entry (Pause while running, Resume while paused):
    -- hidden, so it cannot be clicked, and kept for programmatic callers with
    -- the same gates as the fixed buttons below.
    f.primary=button(f,8,-65,87,"",function()
        local s=Nexus.OrbRuntime.CompactStatus()
        if s and s.running then Nexus.OrbRuntime.Pause()
        elseif s and s.canResume and not changedTarget(s.resumeTarget) then Nexus.OrbRuntime.Resume()end
        f.refresh()
    end)
    f.primary:Hide()
    -- Separate fixed Pause and Resume, as in the mini panel: a repeated press
    -- of one never becomes the other. A changed target resumes only after the
    -- review in the Orb window (Details).
    f.pause=button(f,8,-65,55,"",function()
        local s=Nexus.OrbRuntime.CompactStatus()
        if s and s.running then Nexus.OrbRuntime.Pause()end
        f.refresh()
    end)
    f.resume=button(f,69,-65,62,"",function()
        local s=Nexus.OrbRuntime.CompactStatus()
        if s and not s.running and s.canResume and not changedTarget(s.resumeTarget) then Nexus.OrbRuntime.Resume()end
        f.refresh()
    end)
    f.stop=button(f,137,-65,48,"",function()Nexus.OrbRuntime.Stop();f.refresh()end)
    f.details=button(f,191,-65,69,"",function()UI.Show()end)
    -- Hide for a settled, ended run only (issue #167). Presentation only: it
    -- hides this strip, not Nexus, and spends, chooses, saves, releases or
    -- resets nothing. It is remembered in memory only, for that one run of the
    -- current runtime: a reload forgets it, and a new run (even with the same
    -- numbers) or any active, pending, paused or recovery state is shown.
    -- The run's identity is the runtime's own live run log; a run without one
    -- (one restored after a reload) stays shown. Unknown exposure or an
    -- unconfirmed outcome also keeps it shown. While offered, it takes the
    -- place of Pause, Resume and Stop, which such a run disables anyway.
    local SETTLED={FINISHED=true,COMPLETE=true,ROLLED_COMPLETE=true,STOPPED=true,OUT_OF_ORBS=true,NO_SOURCES=true}
    local function settledRun(s)
        if not (s and SETTLED[s.state] and not s.running and not s.pending and (s.reserved or 0)==0
            and not s.canResume and s.recoveryPhase==nil and (s.uncertain or 0)==0
            and (s.unconfirmedResults or 0)==0 and s.historyKnown and s.limitKnown~=false) then return nil end
        local R=Nexus.OrbRuntime
        local log=type(R.RunLog)=="function" and R.RunLog("current",1,0)
        if not (log and log.runId~=nil and log.liveState==s.state) then return nil end
        return {runtime=R,runId=log.runId,startedAt=log.startedAt}
    end
    local function sameRun(a,b)
        return a~=nil and b~=nil and a.runtime==b.runtime and a.runId==b.runId and a.startedAt==b.startedAt
    end
    f.dismiss=button(f,8,-65,177,"",function()
        -- Only the run this strip showed, read again at the click: a click
        -- that arrives after a new run began hides nothing.
        local now=settledRun(Nexus.OrbRuntime.CompactStatus())
        if sameRun(now,f.shownRun) then f.dismissed=now end
        f.refresh()
    end)
    f.dismiss:Hide()
    -- The controls and their fixed x: one row under the words, which moves
    -- down with the strip's bottom when the words need more than their 52
    -- units (f.refresh). Nothing else about a control changes.
    local ROW={{f.primary,8},{f.pause,8},{f.resume,69},{f.stop,137},{f.details,191},{f.dismiss,8}}
    -- Pipes are doubled so a name shows as written.
    local function piped(v) return (v:gsub("|","||")) end
    f.refresh=function()
        local s=Nexus.OrbRuntime.CompactStatus()
        if not s then f.dismissed,f.shownRun=nil,nil;f:Hide();return end
        local settled=settledRun(s)
        if f.dismissed then
            if sameRun(settled,f.dismissed) then f.shownRun=nil;f:Hide();return end
            f.dismissed=nil
        end
        f.shownRun=settled
        f:Show()
        -- The strip is shown only for a known run: its fixed labels are said
        -- the first time it shows (a hidden strip resolves no text).
        if not f.labelled then
            f.labelled=true
            f.pause:SetText(T("orb.button.pause"));f.resume:SetText(T("orb.button.resume"))
            f.stop:SetText(T("orb.button.stop"));f.details:SetText(T("orb.button.details"))
            f.dismiss:SetText(T("orb.button.hide_until_next_run"))
        end
        local usage=s.limitKnown==false and TF("orb.status.strip_usage_no_max",{spent=N(s.spent)})
            or TF("orb.status.usage_head",{spent=N(s.spent),limit=TF("orb.value.limit_approved",{count=N(s.limit)})})
        -- Exposure stays beside the observed usage, never folded into it.
        usage=usage..((s.uncertain or 0)>0 and ("; "..TF("orb.status.segment_unknown_exposure",{value=tostring(s.uncertain)})) or "")
            ..((s.unconfirmedResults or 0)>0 and ("; "..TF("orb.status.segment_unconfirmed_outcomes",{value=tostring(s.unconfirmedResults)})) or "")
            ..(s.historyKnown==false and ("; "..T("orb.status.segment_history_reload")) or "")
        local second=s.reserved>0 and TF(s.reserved==1 and "orb.status.strip_pending_one" or "orb.status.strip_pending_many",{count=N(s.reserved)})
            or (s.pending and T("orb.status.strip_not_settled"))
            or (s.remaining~=nil and TF("orb.status.strip_copies_remaining",{count=N(s.remaining)}) or T("orb.status.strip_target_unavailable"))
        local third=phaseLabel(s.state)
        -- plainThird: the third line is still the plain state label (or the
        -- plain Paused instruction), decided from states, never from words.
        local plainThird=true
        local pausedLabel=s.state=="PAUSED"
        local what,instruction,plain
        if s.state=="PAUSED" then what,instruction,plain=compactTarget(s.resumeTarget) end
        if instruction then third=instruction;plainThird=plain==true;pausedLabel=plain==true end
        -- CompactStatus has no restored/Continue stage. State the block only;
        -- Details reads the exact explanation and action in the full window.
        if s.state=="PAUSED" and s.pending and not s.canResume and not instruction then
            third=T("orb.status.compact_paused_result");plainThird=false;pausedLabel=false
        end
        -- The strip's own state words, before a count is put into them for
        -- the hover below.
        local stateWords,plainWords=third,plainThird
        -- The complete numbered text (usage, exposure, the pending or
        -- remaining count, a paused target's caption and the state): the
        -- strip's hover. It is not drawn on the strip.
        local full=piped(second)
        if what then
            full=piped(what).."\n"..full
            if s.reserved>0 and pausedLabel then
                third=TF(s.reserved==1 and "orb.status.compact_paused_pending_one" or "orb.status.compact_paused_pending_many",{count=N(s.reserved)})
                plainThird=false
            end
        end
        local whole=usage.."\n"..full
        -- An owned recovery phase comes first, before the exposure totals; it
        -- already names the state, so a plain state line is not repeated.
        if recoveryPhases[s.recoveryPhase] then
            whole=phaseText(s).."\n"..whole
            if not plainThird then whole=whole.."\n"..third end
        else
            whole=whole.."\n"..third
        end
        -- What the strip draws. Approved panel cleanup: a run's counts (Orbs
        -- used and approved, pending, target copies remaining, exposure and
        -- unconfirmed outcomes) are drawn only inside the main panel's open
        -- Details, never on a surface the panel owns outside it, and this
        -- strip is one. It keeps its words, each an existing whole label
        -- chosen by the same conditions as before: an owned recovery phase;
        -- an unknown spend or a history that a reload lost; what the run
        -- waits on (a requested Orb, or the last action not settled); while
        -- paused, the Resume target's whole name and its kind (a digit in a
        -- name is the name's own and stays); then the state or its
        -- instruction. No text is shortened: the words wrap in their box.
        local drawn={}
        if recoveryPhases[s.recoveryPhase] then drawn[#drawn+1]=phaseText(s) end
        local unknown=((s.uncertain or 0)>0 or (s.unconfirmedResults or 0)>0) and T("orb.status.line_spend_unconfirmed") or nil
        if s.historyKnown==false then unknown=(unknown and (unknown.."; ") or "")..T("orb.status.segment_history_reload") end
        if unknown then drawn[#drawn+1]=unknown end
        local awaiting=s.reserved>0 and T("orb.status.segment_awaiting_result") or nil
        if what then
            local t=s.resumeTarget
            local named=what
            if t.kind~="unavailable" then
                named=(t.name~=nil and ("'"..tostring(t.name):gsub("%c"," ").."'") or T("orb.value.unnamed_wishlist")).." "
                    ..T(t.kind=="changed" and (t.returned and "orb.value.target_tag_back" or "orb.value.target_tag_new") or "orb.value.target_tag_same")
            end
            local fact=awaiting or (s.pending and T("orb.status.fact_not_settled")) or nil
            drawn[#drawn+1]=piped((fact and (fact.."; ") or "")..named)
        else
            local waits=awaiting or (s.pending and T("orb.status.strip_not_settled"))
                or (s.remaining==nil and T("orb.status.strip_target_unavailable")) or nil
            if waits then drawn[#drawn+1]=waits end
        end
        if not (recoveryPhases[s.recoveryPhase] and plainWords) then drawn[#drawn+1]=stateWords end
        local words=table.concat(drawn,"\n")
        setFull(f.summary,words,whole)
        -- The words wrap at the label's width and the label is as tall as
        -- they measure, at least its 52 units; the strip and its row of
        -- controls move down by what the words need beyond that. Measured
        -- only when the words, the font scale or the face changed, on the
        -- strip's existing refresh (no timer of its own).
        local LM,need=Nexus.LayoutMetrics,52
        if LM and LM.WrapHeight then
            local revision=LM.RuntimeMetrics and select(3,LM.RuntimeMetrics()) or 0
            local key=words.."\031"..tostring(revision)
            if f.wordsKey~=key or not rawequal(f.wordsFace,f.summary.GetFont) then
                f.wordsKey,f.wordsFace=key,f.summary.GetFont
                f.wordsH=LM.WrapHeight(f.summary,252,52)
            end
            need=f.wordsH or 52
        end
        local extra=math.max(0,need-52)
        if f.extra~=extra then
            f.extra=extra
            f:SetHeight(100+extra)
            for _,item in ipairs(ROW) do
                item[1]:ClearAllPoints();item[1]:SetPoint("TOPLEFT",item[2],-65-extra)
            end
        end
        local resumable=not s.running and s.canResume and not changedTarget(s.resumeTarget)
        f.primary:SetText(T(s.running and "orb.button.pause" or "orb.button.resume"));enable(f.primary,s.running or resumable)
        enable(f.pause,s.running);enable(f.resume,resumable)
        enable(f.stop,s.running or s.pending or s.state=="PAUSED"or s.state=="LIMIT")
        if settled then f.pause:Hide();f.resume:Hide();f.stop:Hide();f.dismiss:Show()
        else f.pause:Show();f.resume:Show();f.stop:Show();f.dismiss:Hide() end
    end
    local elapsed=0
    parent:HookScript("OnUpdate",function(_,dt)elapsed=elapsed+(dt or 0);if elapsed>=.25 then elapsed=0;f.refresh()end end)
    f.refresh();return f
end

-- Optional compact run status. NexusOrbMini is a small movable window that
-- only the player opens (UI.ShowMini, or Mini panel on the run page). It is
-- created on first use, is hidden in every new session and keeps its place
-- until a reload; nothing about it is saved. While it is shown its only run
-- read is OrbRuntime.CompactStatus, four times a second, made only once local
-- saved data is restored (the run page's own Restoring check); hidden, it
-- does no work. Its actions are Pause, Resume and Stop, each gated again on a
-- fresh read at the click (the runtime keeps its own final checks), and Open
-- Orbs, which is UI.Show. It never starts, prepares, confirms, changes a
-- maximum or advances a run. Close and Escape only hide it: an approved run
-- keeps running.
local mini,miniRefresh
local miniBusy,miniFailing=false,false
-- The outcome of the panel's last action and the state it was shown for.
local miniNotice={}
local miniSeen={}
local MINI_W,MINI_H,MINI_PAD,MINI_LINE=356,196,12,17
local MINI_TEXT_W=MINI_W-2*MINI_PAD
-- A shown line holds at most this many characters: one line of the
-- conservative 7 px model (docs/UI_TEXT_LAYOUT.md). A longer value is cut on
-- a character boundary and is complete in the line's tooltip.
local MINI_CHARS=math.floor(MINI_TEXT_W/7)
-- Line tops, top to bottom; every line is one MINI_LINE box.
local MINI_Y={state=-30,reason=-48,usage=-68,pending=-86,missing=-104,notice=-124,note=-142}
local MINI_BUTTON_Y=-164
-- Counts are whole numbers from 0 to the runtime's own bound (the default of
-- its integer()); anything else is unavailable, never 0.
local MINI_MAX_COUNT=1000000
-- Runtime function names (identifiers, never shown).
local MINI_ACTIONS={pause="Pause",resume="Resume",stop="Stop"}
-- The whole "<action> failed" sentence of each action.
local MINI_FAILED={pause="orb.status.mini_pause_failed",resume="orb.status.mini_resume_failed",
    stop="orb.status.mini_stop_failed"}
local MINI_UNREAD={missing="orb.status.mini_unread_missing",error="orb.status.mini_unread_error",
    malformed="orb.status.mini_unread_malformed"}
local MINI_UNREAD_KEY="orb.status.mini_unread"
local function miniCount(v)
    if type(v)=="number" and v>=0 and v<=MINI_MAX_COUNT and v==math.floor(v) then return v==0 and 0 or v end
    return nil
end
local function miniNumber(v) return string.format("%d",v) end
-- One line of display text: control characters become spaces, a value longer
-- than the line is cut on a character boundary ("..." included), and pipes
-- are doubled after the cut so they show as written. Returns the shown text
-- and the complete text.
local function miniText(value)
    local v=tostring(value or ""):gsub("%c"," ")
    local cut=v
    if Nexus.LayoutMetrics and Nexus.LayoutMetrics.Truncate then cut=Nexus.LayoutMetrics.Truncate(v,MINI_CHARS)
    elseif #v>MINI_CHARS then cut=v:sub(1,MINI_CHARS-3):gsub("[\192-\255][\128-\191]*$","").."..." end
    return (cut:gsub("|","||")),(v:gsub("|","||"))
end
-- One compact read: what the panel shows and offers. kind is "run" (a
-- well-formed status), "none" (no run was approved in this session),
-- "loading" (local saved data is not restored yet), "missing" (no runtime),
-- "error" (the read failed) or "malformed". A run needs a text state, boolean
-- flags and whole-number counts; remaining (the rolled target copies still
-- missing) and the reason may be absent.
local function miniView()
    -- Before saved data is restored the runtime cannot know of a run or of a
    -- result restored from it, so it is not asked and nothing reads "none".
    -- This is the run page's Restoring check: a scalar read that pumps and
    -- admits nothing.
    local okReady,ready=true,nil
    if type(Nexus.StartupStatus)=="function" then okReady,ready=pcall(Nexus.StartupStatus) end
    if not okReady then return {kind="error",error=ready} end
    if type(ready)~="table" or not ready.coreReady then return {kind="loading"} end
    local runtime=Nexus.OrbRuntime
    if type(runtime)~="table" or type(runtime.CompactStatus)~="function" then return {kind="missing"} end
    local ok,s=pcall(runtime.CompactStatus)
    if not ok then return {kind="error",error=s} end
    if s==nil then return {kind="none"} end
    if type(s)~="table" then return {kind="malformed"} end
    local v={kind="run",spent=miniCount(s.spent),limit=miniCount(s.limit),reserved=miniCount(s.reserved),
        uncertain=miniCount(s.uncertain),unconfirmedResults=miniCount(s.unconfirmedResults),
        historyKnown=s.historyKnown,recoveryPhase=s.recoveryPhase,recoveryKind=s.recoveryKind,
        remaining=miniCount(s.remaining),state=type(s.state)=="string" and s.state or nil,
        reason=type(s.reason)=="string" and s.reason or nil}
    for _,key in ipairs({"running","pending","canResume","limitKnown"}) do
        if type(s[key])=="boolean" then v[key]=s[key] end
    end
    -- What a Resume would act on (optional; absent offers no extra gate).
    local t=s.resumeTarget
    if type(t)=="table" and type(t.kind)=="string" then
        v.target={kind=t.kind,name=type(t.name)=="string" and t.name or nil,
            reason=type(t.reason)=="string" and t.reason or nil,returned=t.returned==true or nil}
    end
    if not (v.state and v.spent and v.limit and v.reserved) or v.running==nil or v.pending==nil
        or v.canResume==nil then v.kind="malformed" end
    if (s.historyKnown~=nil and type(s.historyKnown)~="boolean")
        or (s.uncertain~=nil and v.uncertain==nil) or (s.unconfirmedResults~=nil and v.unconfirmedResults==nil)
        or (s.recoveryKind~=nil and s.recoveryKind~="manual" and s.recoveryKind~="automatic")
        or (s.recoveryPhase~=nil and not recoveryPhases[s.recoveryPhase]) then v.kind="malformed" end
    return v
end
-- Pause while running; Resume only for a paused run the runtime offers to
-- resume (an unknown state never offers it) and never for a changed target,
-- which is reviewed and resumed in the Orb window; Stop as the main panel
-- offers it. Anything that is not a well-formed run offers nothing.
local function miniGates(v)
    if v.kind~="run" then return false,false,false end
    return v.running,v.state=="PAUSED" and v.canResume and not v.running and not changedTarget(v.target),
        v.running or v.pending or v.state=="PAUSED" or v.state=="LIMIT"
end
local function miniStateText(v)
    if v.kind=="none" then return T("orb.status.mini_no_run") end
    if v.kind=="loading" then return T("orb.status.mini_loading") end
    if v.kind~="run" then return T("orb.status.mini_unavailable") end
    local label=phases[v.state] and T(phases[v.state]) or TF("orb.status.mini_unknown_state",{state=v.state})
    if recoveryPhases[v.recoveryPhase] then return phaseText(v) end
    if v.running then return TF("orb.status.mini_running",{state=label}) end
    if v.state=="PAUSED" and changedTarget(v.target) and v.target.returned then return T("orb.status.mini_paused_review_back") end
    if v.state=="PAUSED" and changedTarget(v.target) then return T("orb.status.mini_paused_review_new") end
    if v.state=="PAUSED" and v.target and v.target.kind=="unavailable" then return T("orb.status.mini_paused_not_ready") end
    if v.state=="PAUSED" and lostApproval(v.target) then return T("orb.status.compact_paused_lost") end
    -- Paused, and Resume is not offered: an earlier submitted action (restored
    -- after a reload, already chosen, or for a changed assignment) must settle.
    if v.state=="PAUSED" and not v.canResume then return T("orb.status.mini_paused_settle") end
    return label
end
local function miniReason(v)
    if v.kind=="none" then return miniText(T("orb.status.mini_open_to_start")) end
    if v.kind=="loading" then return miniText(T("orb.status.mini_reading_saved")) end
    if v.kind~="run" then
        -- The read error itself is diagnostic text and stays as raised.
        local _,detail=miniText(T(MINI_UNREAD[v.kind])..(v.error~=nil and (" "..tostring(v.error)) or ""))
        local unread=T(MINI_UNREAD_KEY)
        return unread,unread.." "..detail
    end
    -- The run's current reason, as the runtime reports it (absent shows
    -- nothing). A paused run's Resume target is named on the missing line.
    return miniText(truthful(v.reason))
end
-- compact: the Nexus panel's short form ("Used ..." instead of "Orbs used:
-- ..."), its own whole label per case (no rewrite of a shown text).
local function miniUsage(v,compact)
    if v.kind=="none" then return T("orb.status.mini_usage_none") end
    local spent,limit=v.spent and miniNumber(v.spent),v.limit and miniNumber(v.limit)
    -- A restored receipt without its approved maximum: the fallback gates the
    -- run but is not shown as approved.
    if spent and v.limitKnown==false then return TF(compact and "orb.status.line_usage_no_max" or "orb.status.mini_usage_no_max",{spent=spent}) end
    if spent and limit then return TF(compact and "orb.status.line_usage_of" or "orb.status.mini_usage_of",{spent=spent,limit=limit}) end
    if limit then return TF(compact and "orb.status.line_usage_spent_unknown" or "orb.status.mini_usage_spent_unknown",{limit=limit}) end
    if spent then return TF(compact and "orb.status.line_usage_limit_unknown" or "orb.status.mini_usage_limit_unknown",{spent=spent}) end
    return T("orb.status.mini_usage_unavailable")
end
local function miniPending(v)
    if v.kind=="none" then return T("orb.status.mini_pending_none") end
    if v.reserved==nil or v.pending==nil then return T("orb.status.mini_pending_unavailable") end
    if v.uncertain==nil or v.unconfirmedResults==nil or v.historyKnown~=true
        or v.uncertain>0 or v.unconfirmedResults>0 then
        local unavailable=T("orb.value.unavailable")
        return (v.pending and (T("orb.status.segment_result_not_settled").."; ") or "")
            ..TF("orb.status.segment_unknown_spend",{value=v.uncertain~=nil and miniNumber(v.uncertain) or unavailable})
            .."; "..TF("orb.status.segment_current_exposure",{value=miniNumber(v.reserved)})
            ..(v.historyKnown~=true and ("; "..T(v.historyKnown==false and "orb.status.segment_history_reload" or "orb.status.segment_history_unavailable"))
                or ("; "..TF("orb.status.segment_unconfirmed_outcomes",{value=v.unconfirmedResults~=nil and miniNumber(v.unconfirmedResults) or unavailable})))
            ..(v.pending and ("; "..T("orb.status.segment_awaiting_result")) or "")
    end
    if v.reserved>0 then
        return TF(v.reserved==1 and "orb.status.mini_pending_one" or "orb.status.mini_pending_many",{count=miniNumber(v.reserved)})
    end
    return v.pending and T("orb.status.mini_result_not_settled") or T("orb.status.mini_pending_none")
end
local function miniPendingLine(v)
    local shown,full=miniText(miniPending(v))
    if v.kind=="run" and v.reserved~=nil and v.pending~=nil
        and (v.uncertain==nil or v.unconfirmedResults==nil or v.historyKnown~=true
            or v.uncertain>0 or v.unconfirmedResults>0) then
        -- Keep all three distinct counts visible inside the existing line;
        -- its hover retains the complete pending/history explanation.
        shown=miniText(TF("orb.status.mini_pending_counts",{unknown=N(v.uncertain),reserved=N(v.reserved),
            outcomes=N(v.historyKnown==true and v.unconfirmedResults or nil)}))
    end
    return shown,full
end
-- Copies, not families: CompactStatus.remaining is the run's rolled target
-- copies still missing at its latest check. Absent is unavailable, never 0.
local function miniMissing(v)
    return TF("orb.status.mini_rolled_missing",{value=v.remaining and miniNumber(v.remaining) or T("orb.value.unavailable")})
end
-- The missing line. While paused, when compactTarget names what Resume would
-- act on, the line shows the rolled copies count first ("?" is unavailable,
-- never 0), then the target's name in quotes, "(unnamed)" for a nameless
-- Wishlist or "target ?" while the target is unknown. It is kept to 30
-- columns (the 332 px line at the offline doubled-font model's 11 px per
-- character, not a native measurement): a longer name is cut on a character
-- boundary inside its quotes. The hover keeps the complete count, the
-- complete target with its kind and the line's meaning.
local function miniMissingLine(v)
    local shown,full=miniText(miniMissing(v))
    local what=v.kind=="run" and v.state=="PAUSED" and compactTarget(v.target) or nil
    if not what then return shown,full end
    local _,target=miniText(what)
    local t,tail=v.target,T("orb.value.target_unknown_short")
    shown=TF("orb.status.mini_rolled_missing_short",{count=N(v.remaining)}).."; "
    if t.kind~="unavailable" then
        tail=T("orb.value.unnamed_short")
        if t.name~=nil then
            local name=(tostring(t.name):gsub("%c"," "))
            local room=math.max(4,math.floor(MINI_TEXT_W/11)-#shown-2)
            if Nexus.LayoutMetrics and Nexus.LayoutMetrics.Truncate then name=Nexus.LayoutMetrics.Truncate(name,room)
            elseif #name>room then name=name:sub(1,room-3):gsub("[\192-\255][\128-\191]*$","").."..." end
            tail="'"..name:gsub("|","||").."'"
        end
    end
    shown=shown..tail
    return shown,full..". "..target
end
-- The Nexus panel's one-line Orb run status (Claude Design full UI, "Main
-- panel (Play)": "Orb run", its usage, what awaits a result, Open). From the
-- same compact read as the mini panel (miniView): the run's state, Orbs used
-- of the approved maximum, and a requested Orb or an unsettled result named as
-- a wait, never as spent. Returns shown, full (the hover), or nil while no run
-- is known: none approved this session, local saved data still loading or no
-- runtime. A read that fails or is malformed says so. Reads only; it pumps,
-- starts, resumes and spends nothing.
-- A third value, words (approved panel cleanup: the run's numbers are drawn
-- only inside the panel's open Details): the same state words as `shown`,
-- whole, and the same wait behind the same mark, said without a count
-- ("awaiting Orb result" where `shown` counts the Orbs), and no usage. It has
-- no number by construction: the state words carry none and the three wait
-- texts are existing whole labels. The first two values are unchanged.
function UI.PanelRunLine()
    local okView,v=pcall(miniView)
    if not okView or type(v)~="table" then v={kind="error"} end
    if v.kind=="none" or v.kind=="loading" or v.kind=="missing" then return nil end
    if v.kind~="run" then
        local unread=TF("orb.status.line_run",{status=T(MINI_UNREAD_KEY)})
        return unread,unread,unread
    end
    local state,usage=miniStateText(v),miniUsage(v,true)
    local wait,waitWords
    if v.reserved==nil or v.pending==nil or v.uncertain==nil or v.unconfirmedResults==nil
        or v.historyKnown~=true or v.uncertain>0 or v.unconfirmedResults>0 then
        wait="? "..T("orb.status.line_spend_unconfirmed")
        waitWords=wait
    elseif v.reserved>0 then
        wait="... "..TF("orb.status.line_awaiting_result",{count=N(v.reserved)})
        waitWords="... "..T("orb.status.segment_awaiting_result")
    elseif v.pending then
        wait="... "..T("orb.status.line_result_not_settled")
        waitWords=wait
    end
    local shown=TF("orb.status.line_run",{status=state.."; "..usage..(wait and ("; "..wait) or "")})
    local full=TF("orb.status.line_run",{status=state..". "..miniUsage(v)..". "..miniPending(v)..". "..miniMissing(v).."."})
    local reason=v.reason and truthful(v.reason) or nil
    if type(reason)=="string" and reason~="" then full=full.." "..reason end
    local words=TF("orb.status.line_run",{status=state..(waitWords and ("; "..waitWords) or "")})
    return (shown:gsub("|","||")),(full:gsub("|","||")),(words:gsub("|","||"))
end
local function miniKey(v)
    return table.concat({v.kind,tostring(v.state),tostring(v.running),tostring(v.pending),tostring(v.canResume),
        tostring(v.recoveryPhase),tostring(v.recoveryKind),tostring(v.target and v.target.kind)},"|")
end
-- A new UI size moves the panel back inside the UI. The panel is smaller
-- than any UI this client supports (FitToScreen treats less than 640x480 as
-- implausible), so it keeps its scale; the client's own clamping keeps a drag
-- on screen. Two size reads per refresh; nothing moves otherwise.
local function clampMini()
    if not UIParent then return end
    local sw,sh=tonumber(UIParent:GetWidth()),tonumber(UIParent:GetHeight())
    if not (sw and sh) or (miniSeen.sw==sw and miniSeen.sh==sh) then return end
    local left,top=mini:GetLeft(),mini:GetTop()
    local w,h=tonumber(mini:GetWidth()),tonumber(mini:GetHeight())
    if not (left and top and w and h) then return end
    miniSeen.sw,miniSeen.sh=sw,sh
    local s=tonumber(mini:GetScale()) or 1
    local x,y=left*s,top*s
    local cx=math.max(0,math.min(x,sw-w*s))
    local cy=math.min(sh,math.max(y,h*s))
    if math.abs(cx-x)>0.5 or math.abs(cy-y)>0.5 then
        mini:ClearAllPoints();mini:SetPoint("TOPLEFT",UIParent,"BOTTOMLEFT",cx/s,cy/s)
    end
end
-- Returns the read error, if the read failed, so it can be reported once.
local function miniRender()
    local v=miniView()
    setFull(mini.state,miniText(miniStateText(v)))
    setFull(mini.reason,miniReason(v))
    setFull(mini.usage,miniText(miniUsage(v)))
    setFull(mini.pending,miniPendingLine(v))
    setFull(mini.missing,miniMissingLine(v))
    -- An outcome belongs to the state it was shown for; a later change of that
    -- state retires it, so it never describes a newer state.
    local key=miniKey(v)
    if miniNotice.text~=nil then
        if miniNotice.key==nil then miniNotice.key=key
        elseif miniNotice.key~=key then miniNotice.text,miniNotice.key=nil,nil end
    end
    setFull(mini.notice,miniText(miniNotice.text))
    local pause,resume,stop=miniGates(v)
    enable(mini.pause,pause and not miniBusy);enable(mini.resume,resume and not miniBusy)
    enable(mini.stop,stop and not miniBusy)
    clampMini()
    if v.kind=="error" then return tostring(v.error) end
end
-- A failure goes to the client's error handler, which may itself raise.
local function miniReport(failure)
    local handler=type(geterrorhandler)=="function" and geterrorhandler() or nil
    if type(handler)=="function" then pcall(handler,failure) end
end
miniRefresh=function()
    if not (mini and mini:IsShown()) then return end
    local ok,failure=pcall(miniRender)
    if ok and failure==nil then miniFailing=false;return end
    if not ok then
        -- Fail closed: nothing shown or offered may rest on an earlier read.
        enable(mini.pause,false);enable(mini.resume,false);enable(mini.stop,false)
        local _,detail=miniText(failure)
        local unread=T(MINI_UNREAD_KEY)
        setFull(mini.state,T("orb.status.mini_unavailable"))
        setFull(mini.reason,unread,unread.." "..detail)
        setFull(mini.usage,T("orb.status.mini_usage_unavailable"))
        setFull(mini.pending,T("orb.status.mini_pending_unavailable"))
        setFull(mini.missing,TF("orb.status.mini_rolled_missing",{value=T("orb.value.unavailable")}))
    end
    -- Reported once per failure, not four times a second.
    if miniFailing then return end
    miniFailing=true
    miniReport(failure)
end
-- key, when given, is the state the outcome was worded from; otherwise the
-- next refresh binds it to the state it shows.
local function miniSay(message,key) miniNotice.text,miniNotice.key=message,key end
local function miniRefusal(kind,v)
    local unread=v.kind~="run" and v.kind~="none"
    if kind=="pause" then
        return T(unread and "orb.status.mini_not_paused_unread" or "orb.status.not_paused_not_running")
    elseif kind=="resume" then
        if unread then return T("orb.status.mini_not_resumed_unread") end
        if v.kind=="none" then return T("orb.status.mini_not_resumed_no_run") end
        if v.running then return T("orb.status.not_resumed_running") end
        -- One whole mini line (MINI_CHARS): the reason and the button to use.
        if v.state=="PAUSED" and changedTarget(v.target) and v.target.returned then return T("orb.status.mini_not_resumed_review_back") end
        if v.state=="PAUSED" and changedTarget(v.target) then return T("orb.status.mini_not_resumed_review_new") end
        if v.state=="PAUSED" and v.target and v.target.kind=="unavailable" then return T("orb.status.mini_not_resumed_not_ready") end
        if v.state=="PAUSED" and lostApproval(v.target) then return T("orb.status.mini_not_resumed_lost") end
        if v.state=="PAUSED" then return T("orb.status.mini_not_resumed_settle") end
        return T("orb.status.mini_not_resumed_not_paused")
    end
    if unread then return T("orb.status.mini_not_stopped_unread") end
    if v.kind=="none" then return T("orb.status.mini_not_stopped_no_run") end
    return T("orb.status.mini_not_stopped_inactive")
end
-- Resume answers true even when its own first step at once paused or ended
-- the run again (an Echo board open, no Orbs left), so its success is worded
-- from the read taken after it (after): "Resumed" only for a running run.
local function miniOutcome(kind,done,why,after)
    if kind=="pause" then return T(done and "orb.status.mini_paused" or "orb.status.mini_not_paused_was_not_running") end
    if not done then
        -- The runtime's reason is said through the display boundary.
        return TF(kind=="resume" and "orb.status.mini_not_resumed_reason" or "orb.status.mini_not_stopped_reason",
            {reason=truthful(why) or T("orb.status.mini_refused")})
    end
    if kind=="stop" then return T("orb.status.mini_stopped") end
    if not (after and after.kind=="run") then return T("orb.status.mini_resume_accepted") end
    return T(after.running and "orb.status.mini_resumed" or "orb.status.mini_resume_not_running")
end
-- One action at a time. The click reads again and acts only if that read
-- offers the action; the runtime then applies its own final checks.
local function miniAct(kind)
    if miniBusy or not mini then return end
    miniBusy=true
    -- While it runs no control reads as available, so a nested click or
    -- refresh cannot act on the read taken before it.
    enable(mini.pause,false);enable(mini.resume,false);enable(mini.stop,false)
    local ok,err=pcall(function()
        local v=miniView()
        local pause,resume,stop=miniGates(v)
        local allowed=(kind=="pause" and pause) or (kind=="resume" and resume) or (kind=="stop" and stop)
        if not allowed then miniSay(miniRefusal(kind,v));return end
        local done,why=Nexus.OrbRuntime[MINI_ACTIONS[kind]]()
        -- An accepted Resume is worded from a fresh read and belongs to the
        -- state that read shows.
        local after=kind=="resume" and done and miniView() or nil
        miniSay(miniOutcome(kind,done,why,after),after and miniKey(after))
    end)
    miniBusy=false
    -- A short notice here; the error itself goes to the error handler, once
    -- for this action. The refresh then offers only what a new read allows.
    if not ok then miniSay(T(MINI_FAILED[kind])) end
    miniRefresh()
    if not ok then miniReport(err) end
end
local function miniTip(widget,tip)
    widget:SetScript("OnEnter",function(self)
        if not GameTooltip then return end
        GameTooltip:SetOwner(self,"ANCHOR_TOP");GameTooltip:SetText(tip,1,1,1,1,true);GameTooltip:Show()
    end)
    widget:SetScript("OnLeave",function()if GameTooltip then GameTooltip:Hide()end end)
end
-- One line and its hover area. The line never wraps: text the client draws
-- wider than the box, even within MINI_CHARS, is shortened there instead of
-- spilling out of its MINI_LINE box. Hovering a line that holds text always
-- shows its complete text (flattened and escaped, as shown) and, when given,
-- what the line means.
local function miniLine(f,key,about)
    local fs=text(f,MINI_PAD,MINI_Y[key],MINI_TEXT_W,MINI_LINE)
    if Nexus.LayoutMetrics then Nexus.LayoutMetrics.OneLineLabel(fs,nil,MINI_LINE) end
    local hit=CreateFrame("Frame",nil,f);hit:SetAllPoints(fs);hit:EnableMouse(true)
    hit:SetScript("OnEnter",function(self)
        local full=fs._nexusFullText or fs:GetText() or ""
        if not (GameTooltip and (full~="" or about)) then return end
        GameTooltip:SetOwner(self,"ANCHOR_TOP")
        GameTooltip:SetText(full,1,1,1,1,true)
        if about then GameTooltip:AddLine(about,.9,.9,.9,true) end
        GameTooltip:Show()
    end)
    hit:SetScript("OnLeave",function()if GameTooltip then GameTooltip:Hide()end end)
    f[key],f[key.."Hit"]=fs,hit
end
local function ensureMini()
    if mini then return mini end
    local f=CreateFrame("Frame","NexusOrbMini",UIParent);f:Hide()
    f:SetSize(MINI_W,MINI_H);f:SetPoint("TOPLEFT",UIParent,"TOPLEFT",16,-150)
    -- Below the Orb window and Help (DIALOG): a status panel, not a dialog.
    f:SetFrameStrata("HIGH");f:SetFrameLevel(20);f:EnableMouse(true);f:SetMovable(true);f:SetClampedToScreen(true)
    f:SetBackdrop({bgFile="Interface\\Buttons\\WHITE8X8",edgeFile="Interface\\Tooltips\\UI-Tooltip-Border",edgeSize=14,insets={left=4,right=4,top=4,bottom=4}})
    f:SetBackdropColor(.035,.04,.05,1)
    f.title=f:CreateFontString(nil,"OVERLAY","GameFontNormal")
    f.title:SetPoint("TOPLEFT",MINI_PAD,-9);f.title:SetSize(262,18);f.title:SetJustifyH("LEFT")
    f.title:SetText(T("orb.title.mini"))
    -- The title bar moves the panel. Its place lasts for this session only:
    -- the client is asked not to keep it in its layout cache.
    f.drag=CreateFrame("Frame",nil,f);f.drag:SetPoint("TOPLEFT",6,-4);f.drag:SetSize(274,24)
    f.drag:SetFrameLevel(f:GetFrameLevel()+1);f.drag:EnableMouse(true);f.drag:RegisterForDrag("LeftButton")
    f.drag:SetScript("OnDragStart",function()f:StartMoving()end)
    f.drag:SetScript("OnDragStop",function()
        f:StopMovingOrSizing()
        if f.SetUserPlaced then pcall(f.SetUserPlaced,f,false) end
    end)
    miniTip(f.drag,T("orb.tooltip.mini_drag"))
    f.close=button(f,MINI_W-MINI_PAD-58,-7,58,T("orb.button.close"),function()f:Hide()end);f.close:SetHeight(20)
    miniTip(f.close,T("orb.tooltip.mini_close"))
    miniLine(f,"state");miniLine(f,"reason")
    miniLine(f,"usage",T("orb.tooltip.mini_usage"))
    miniLine(f,"pending",T("orb.tooltip.mini_pending"))
    miniLine(f,"missing",T("orb.tooltip.mini_missing"))
    miniLine(f,"notice");miniLine(f,"note")
    f.note:SetText(T("orb.note.mini_close_keeps_run"))
    -- Pause and Resume are separate buttons in fixed places, so a repeated
    -- press of one can never become the other.
    f.pause=button(f,MINI_PAD,MINI_BUTTON_Y,66,T("orb.button.pause"),function()miniAct("pause")end)
    f.resume=button(f,MINI_PAD+72,MINI_BUTTON_Y,74,T("orb.button.resume"),function()miniAct("resume")end)
    f.stop=button(f,MINI_PAD+152,MINI_BUTTON_Y,60,T("orb.button.stop"),function()miniAct("stop")end)
    f.open=button(f,MINI_W-MINI_PAD-96,MINI_BUTTON_Y,96,T("orb.button.open_orbs"),function()UI.Show()end)
    miniTip(f.pause,T("orb.tooltip.mini_pause"))
    miniTip(f.resume,T("orb.tooltip.mini_resume"))
    miniTip(f.stop,T("orb.tooltip.mini_stop"))
    miniTip(f.open,T("orb.tooltip.mini_open"))
    f.pause:Disable();f.resume:Disable();f.stop:Disable()
    local elapsed=0
    f:SetScript("OnShow",function()elapsed=0;miniRefresh()end)
    -- An outcome is not carried into the next opening.
    f:SetScript("OnHide",function()miniNotice.text,miniNotice.key=nil,nil end)
    f:SetScript("OnUpdate",function(_,dt)elapsed=elapsed+(dt or 0);if elapsed>=.25 then elapsed=0;miniRefresh()end end)
    styled(f,0.94)
    UISpecialFrames=UISpecialFrames or {};UISpecialFrames[#UISpecialFrames+1]="NexusOrbMini"
    mini=f
    return f
end
-- Shows the compact run status. Reading only; repeated calls reuse it.
function UI.ShowMini()
    ensureMini()
    if mini:IsShown() then miniRefresh() else mini:Show() end
    return mini
end
-- Hides it, as Close and Escape do. An approved run keeps running.
function UI.HideMini() if mini then mini:Hide() end end
function UI.MiniShown() return mini~=nil and mini:IsShown() and true or false end
