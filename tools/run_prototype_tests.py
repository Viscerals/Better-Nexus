#!/usr/bin/env python3
"""Run only the prototype-specific checks. Never represents the upstream full suite.
Python 3.9+. Native LuaJIT is preferred if installed; the local Lua 5.4 fallback
is explicitly labelled and requires liblua5.4. No network or game access.
"""
from __future__ import annotations
import argparse, ctypes.util, hashlib, json, os, pathlib, shutil, subprocess, sys, time
ROOT=pathlib.Path(__file__).resolve().parents[1]
NAMES=['parse','boot','wishlist','lock_evidence','ownership','typed_hash','transport','automation','manual_sync','diagnostics','features','echoweaver_planner','startup','startup_evidence','startup_failure','startup_validation','startup_drift','startup_budget','startup_persistence','startup_source_change','role_selection','role_boundaries','role_persistence','role_export','current_locks','loading_status','loading_local','current_locks_reload','current_locks_exact','orbs','orbs_controls','orbs_ambiguity','orbs_same_echo','orbs_prerequisites','orbs_reload','echoweaver_orb_policy','orbs_ui','orbs_context','orbs_permanent','orbs_loading','help','terminology']
NAMES += ['support_tome_permission']
NAMES += ['tome_late_discovery']
NAMES += ['tome_observation_workflow','tome_observation_gates','tome_observation_bounds','tome_observation_parity']
NAMES += ['catalog_admission_origin','catalog_admission_limits','catalog_admission_rollback','catalog_admission_inbound','catalog_admission_legacy_field']
NAMES += ['catalog_admission_bare','catalog_admission_bare_wire','catalog_admission_semantics']
NAMES += ['catalog_admission_retained']
NAMES += ['tome_pause_visibility', 'tome_pause_observation']
NAMES += ['sync_replacement_budget', 'sync_replacement_budget_caller', 'sync_replacement_role_overlap', 'sync_replacement_roles_public', 'sync_replacement_roles_lifecycle']
NAMES += ['wishlist_locked_design_save', 'orb_assignment_invalid_status', 'orb_resume_assignment_gate', 'orb_resume_context_gate', 'orb_resume_assignment_adoption', 'orb_resume_original_assignment_restore', 'orb_resume_compact_read_cost', 'orb_resume_nil_slot_pending', 'orb_resume_nil_slot_settled']
# Accepted Claude tome regression fixtures (support is a dofile dependency only).
NAMES += ['approved_tome_state_contract','approved_tome_rows_refresh']

NAMES += ['native_wishlist_tome_sequence', 'progress_tome_refresh', 'progress_tome_refresh_controls', 'progress_owned_tooltips']
NAMES += ['policy_lab','search_order_sim']  # retained repository-only experiments
NAMES += ['orbs_review_sources','orbs_review_lifecycle','orbs_review_same_id','orbs_review_recheck','orbs_review_availability','orbs_review_ordering','orbs_review_disclosure','orbs_review_recovery','terminology_consumers']
NAMES += ['select_recovery_provenance', 'select_recovery_transition']
NAMES += ['select_recovery_controls']
NAMES += ['select_followup_effective','select_followup_heading','select_followup_admission','select_followup_lifecycle','select_followup_controls']
NAMES += ['select_followup_wording']
NAMES += ['select_review_lows']
NAMES += ['select_final_capacity']
NAMES += ['orbs_review_rejected_selection','orbs_review_catalog','orbs_review_catalog_grouping']
NAMES += ['orbs_assigned','help_layout','assignment_restore','orbs_target_changes','orbs_assigned_protection','orbs_main_controls','session_permissions','orbs_assignment_races','orbs_assigned_resources','assignment_identity','orbs_loadout_change']
NAMES += ['assignment_distinct_designs','orbs_loadout_result_alias']
NAMES += ['assignment_design_lifecycle']
NAMES += ['orbs_loadout_early_change']
NAMES += ['assignment_journal_picker','assignment_editing_menu']
NAMES += ['assignment_journal_controls']
NAMES += ['orbs_legacy_editbox_idle','orbs_legacy_editbox_busy','orbs_legacy_editbox_loading']
NAMES += ['orbs_help_layers']
NAMES += ['assignment_first_run_edit']
NAMES += ['assignment_first_run_unassign']
NAMES += ['assignment_first_run_reselect','assignment_first_run_handoff']
NAMES += ['journal_picker_layers','wishlist_editor_context_label']
NAMES += ['assignment_equal_content_picker']
NAMES += ['share_catalog_contention','share_catalog_lifecycle','share_inbound_listing']
NAMES += ['share_send_liveness','share_send_guards','share_transport_prepared']
NAMES += ['share_edit_liveness','share_edit_guards']
NAMES += ['share_terminal_cleanup']
NAMES += ['stop_sharing_refusal','stop_sharing_pending','stop_sharing_outcomes']
NAMES += ['stop_sharing_layers','stop_sharing_layer_lifecycle']
NAMES += ['sync_deferred_admission','sync_deferred_transfer','sync_withdrawal_guards','sync_deferred_scope','sync_deferred_fairness','sync_multichunk_pressure','sync_request_readiness','sync_request_full_record']
NAMES += ['sync_responder_turn','sync_responder_aged','sync_responder_inflight','sync_responder_recovery']
NAMES += ['rolling_no_guarantee','rolling_no_guarantee_runtime','policy_compare']
NAMES += ['diagnostics_gate_status']
NAMES += ['sync_channel_late_join']
NAMES += ['sync_dps_native_channel_owner']
NAMES += ['sync_dps_native_realm_shim']
NAMES += ['sync_dps_current_native_owner']
NAMES += ['sync_dps_native_bucket_claim','sync_dps_native_claim_reconciler','sync_dps_native_claim_wire']
NAMES += ['sync_dps_native_claim_inflight_wire']
NAMES += ['sync_dps_correlation_wire','sync_correlation_limits','sync_claim_correlation']
NAMES += ['sync_requester_filter']
NAMES += ['sync_dps_bare_native_context','sync_dps_bare_native_paced']
NAMES += ['sync_dps_bare_requester_route']
NAMES += ['startup_build_identity']
NAMES += ['community_cursor_readers','sync_locked_roles_request','leaderboard_roles_names']
NAMES += ['sync_dps_native_relay_scan']
NAMES += ['update_notices']
NAMES += ['update_peer_provenance']
NAMES += ['sync_request_size']
NAMES += ['orb_panel_idle_work','orb_readiness_persistence','orb_stacked_copies']
NAMES += ['share_role_preservation']
NAMES += ['share_pending_status']
NAMES += ['share_plan_design_roles']
NAMES += ['advisor_attachment']
NAMES += ['rolling_review_unknown_orb_state']
NAMES += ['orb_review_reload_unobservable','orb_review_reload_manual_choice','orb_review_reload_offer_after_reload']
NAMES += ['orb_review_reload_offer_mismatch','orb_review_reload_no_observer','orb_review_reload_rejected_selection']
NAMES += ['rolling_review_reroll_outstanding']
NAMES += ['rolling_review_freeze_surplus']
NAMES += ['orb_review_reload_other_loadout','orb_review_reload_choice_between_reads']
NAMES += ['rolling_review_orb_state_recompute']
NAMES += ['orb_review_reload_early_ownership','orb_review_reload_early_ownership_inexact','orb_review_reload_slow_cadence']
NAMES += ['orb_review_reload_choice_event_guards','orb_review_reload_truthful_blocks']
NAMES += ['rolling_review_policy_flags']
NAMES += ['orb_review_reload_refused_first_choice','orb_review_reload_balance_guard']
NAMES += ['rolling_review_automatic_paths_orb_state']
NAMES += ['loading_step_progress','loading_step_source_change']
NAMES += ['format5_known_transition','format5_ownership','format5_protection']
NAMES += ['format_marker_malformed']
NAMES += ['sync_saved_mode_off','sync_saved_mode_manual','sync_saved_mode_controls','sync_saved_mode_share_retry']
NAMES += ['startup_failure_causes','format5_bundle_placeholder']
NAMES += ['catalog_root_capacity']
NAMES += ['catalog_capacity_local_ready']
NAMES += ['changelog_seen_guard']
NAMES += ['update_keys_read_only']
NAMES += ['quickstart_seen_guard']
NAMES += ['sync_admission_batch']
NAMES += ['sync_admission_traffic_acceptance']
NAMES += ['orb_finished_run_log']
NAMES += ['wishlist_import_paste_path']
NAMES += ['wishlist_export_copy_field']
NAMES += ['orb_finished_new_run_confirm']
NAMES += ['orb_history_view']
NAMES += ['dps_capture_envelope']
NAMES += ['support_report']
NAMES += ['sync_phase_attribution']
NAMES += ['sync_admission_restore']
NAMES += ['update_public_test_hints']
NAMES += ['startup_attempt_key_width']
NAMES += ['wishlist_switch_recovery']
NAMES += ['server_hud_handoff']
NAMES += ['first_hud_display']
NAMES += ['select_intent_ownership']
NAMES += ['catalog_capacity_envelope','catalog_marker_expiry','catalog_saturation','catalog_saturation_order']
NAMES += ['hash_cache_source_coalescing']
NAMES += ['catalog_dependency_reads']
NAMES += ['leaderboard_recovery_rows','leaderboard_recovery_upstream']
NAMES += ['retention_ranked_marker_pass']
NAMES += ['rival_picker_detection']
NAMES += ['retention_busy_retry_bound']
NAMES += ['share_source_drift_order']
NAMES += ['compaction_rebind_release']
NAMES += ['dps_compaction_preservation']
NAMES += ['dps_evidence_open_candidate']
NAMES += ['retention_ranked_dps_preservation']
NAMES += ['retention_ranked_guard_identity']
NAMES += ['automation_world_transition','auto_port_notice',
          'auto_port_recovery','auto_port_review_edges']
NAMES += ['readonly_profile_preservation','readonly_saved_dps_visibility']
NAMES += ['autosave_overwrite_warning','autosave_assignment_recheck']
NAMES += ['hud_prepare_reuse']
NAMES += ['quickstart_layout_fit']
NAMES += ['assignment_picker_selected_marker']
NAMES += ['support_report_errors']
NAMES += ['orb_recovery_slot_and_gate']
NAMES += ['journal_selector_tooltip_visibility']
NAMES += ['legacy_repair_progress_fairness','legacy_repair_boot_cases']
NAMES += ['dps_sync_digest_bounded']
NAMES += ['dps_locked_history_preserved']
NAMES += ['dps_receive_envelope']
NAMES += ['community_card_dps_pair']
NAMES += ['server_status_click_and_hook']
NAMES += ['view_refresh_refusal_once']
NAMES += ['utf8_safe_truncation']
NAMES += ['hud_quality_labels']
NAMES += ['wishlist_scroll_clamp', 'wishlist_footer_layout']
NAMES += ['role_save_keeps_explicit_ordinary']
NAMES += ['automation_role_deficit']
NAMES += ['automation_tier_annotation']
NAMES += ['orb_guidance_navigation','orb_guidance_passive_open']
NAMES += ['orb_draft_approval_preserved','orb_guidance_geometry']
NAMES += ['orb_budget_draft']
NAMES += ['community_dps_filter']
NAMES += ['sync_locked_roles_wire','sync_locked_roles_payload','community_update_roles']
NAMES += ['sync_owner_promotion_receive']
NAMES += ['sync_native_channel_owner']
NAMES += ['public_label_presentation']
NAMES += ['hud_roll_footprint']
NAMES += ['help_action_first']
NAMES += ['orb_rdf_balance_drift']
NAMES += ['orb_rdf_recovery_followups']
NAMES += ['orb_read_signature_cost','catalog_budget_exhausted']
NAMES += ['hud_assignment_reads','poll_tome_pending_idle','catalog_idle_frames']
NAMES += ['assignment_context_merge','assignment_detail_timing']
NAMES += ['orb_recovery_guidance_diag','orb_boundary_diagnostics',
          'stutter_diagnostic_spans','stutter_diagnostic_integration',
          'support_targeted_diagnostics']
NAMES += ['perf_lifecycle_phases']
NAMES += ['lifecycle_counter_accounting']
NAMES += ['sync_scalar_root_reject','tome_toggle_snapshot_isolation','startup_identity_repair_noop','panel_annotation_labels','help_decision_order']
NAMES += ['orb_live_balance_drift','wishlist_save_slot_safety']
NAMES += ['wishlist_editor_binding']
NAMES += ['wishlist_assignment_action_token']
NAMES += ['catalog_verdict_reuse','catalog_verdict_reuse_differential']
NAMES += ['legacy_recovery_flow','legacy_recovery_guards','legacy_recovery_unchanged']
NAMES += ['adaptive_policy_rules','adaptive_policy_parity','roll_recorder_unit','roll_recorder_runtime','roll_recorder_freeze_observation']
NAMES += ['rolling_latency']
NAMES += ['lock_bucket_growth']
NAMES += ['auto_lock_absent_empty_bucket']
NAMES += ['empty_saved_build_save']
NAMES += ['empty_saved_build_assignment_status']
NAMES += ['empty_saved_build_journal_text']
NAMES += ['stale_server_slot_save']
NAMES += ['stale_server_slot_open','stale_server_slot_roles']
NAMES += ['legacy_assignment_snapshot']
NAMES += ['leaderboard_arithmetic_cases']
NAMES += ['wishlist_loadout_selector_slots']
NAMES += ['wishlist_overlay_locked_targets']
NAMES += ['wishlist_overlay_legacy_design_refresh']
NAMES += ['lock_design_legacy_preservation']
NAMES += ['sync_realm_syntax']
NAMES += ['orb_loadout_hold_repro','orb_loadout_hold_shape','orb_loadout_hold_cause','orb_loadout_hold_history']
NAMES += ['orb_pick_evidence','orb_transport_observer','orb_recovery_continue','orb_recovery_refusals','orb_recovery_store_compat','orb_recovery_ui','orb_recovery_after']
NAMES += ['community_detail_layout','leaderboard_detail_layout','wishlist_menu_label_layout','text_overflow_policy']
NAMES += ['automation_refused_freeze','dps_build_link_index','dps_board_cursor_source','catalog_tombstone_unknown_evidence']
NAMES += ['catalog_tombstone_readers','dps_capture_readonly_note','tombstone_retirement_policy','dps_build_link_bounded']
NAMES += ['sync_received_dps_egress','hash_cache_warm_budget','summary_cursor_named_readers','sync_hot_build_expiry']
NAMES += ['journal_association_lazy_candidates','dps_index_summary_rows']
NAMES += ['hash_cache_collision_budget','hash_cache_identity_fail_closed','sync_hot_build_release']
NAMES += ['hash_cache_source_refusal']
NAMES += ['echo_snapshot_rejected_field','fallback_static_invalidation']
NAMES += ['echo_raw_shape_bounds']
NAMES += ['orb_panel_assignment_failure_text','orb_passive_readiness_report','orb_readiness_collection_pure']
NAMES += ['orb_choice_observation', 'choice_presence_diagnostics', 'orb_diagnostic_lifecycle_freshness']
NAMES += ['ownership_passive_diagnostics']
NAMES += ['locked_shape_capture','locked_shape_bounds','locked_shape_report','locked_shape_correlation']
NAMES += ['legacy_dps_conversion_served','legacy_dps_conversion_recovery','legacy_dps_conversion_refusals']
NAMES += ['orb_count_refusal_truthful','orb_count_refusal_fallbacks']
NAMES += ['legacy_dps_conversion_interrupted','legacy_dps_conversion_unsupported']
NAMES += ['community_pending_marker_counts','saved_mirror_assigned_description','tooltip_rank_presented_board']
NAMES += ['leaderboard_selection_publication','leaderboard_empty_detail_text','leaderboard_class_menu_close','community_link_draft_refresh']
NAMES += ['tooltip_marker_name_guild','wishlist_selector_truthful_context','wishlist_manage_menu_close','hud_quickstart_restore']
NAMES += ['peer_log_page_keep']
NAMES += ['saved_mirror_owner_description_reimport']
NAMES += ['legacy_dps_recovery_nonbest_personal','saved_mirror_link_only_description']
NAMES += ['saved_mirror_title_only_description','wishlist_unassigned_selector_context']
NAMES += ['saved_mirror_description_provenance']
NAMES += ['long_description_boundary_probe']
NAMES += ['saved_mirror_pipe_resubmit']
NAMES += ['saved_mirror_pipe_controls']
# Ten-group repair batch regressions (SETUP/EXPECT/GUARD; EXPECT fails at 8c by design).
NAMES += ['batch_class_capture_publication','batch_class_saved_import']
NAMES += ['batch_description_unseeded_edit']
NAMES += ['batch_locked_units_trust','batch_locked_units_envelopes','batch_locked_units_autolock']
NAMES += ['batch_locked_units_autolock_gates','batch_locked_units_display']
NAMES += ['batch_intensity_constants']
NAMES += ['batch_design_reassignment']
NAMES += ['batch_orb_spend_wording']
NAMES += ['batch_feedback_event_wiring']
NAMES += ['batch_hud_named_fields']
NAMES += ['batch_saved_locked_mirror']
NAMES += ['batch_journal_fallback_argument','batch_low_score_display','batch_slot_range_observation']
# Supplement r2: dynamic capacity, record partitions, locked partial target, wire records, restored Orb wording.
NAMES += ['batch_locked_capacity_trust','batch_locked_capacity_autolock','batch_locked_capacity_display']
NAMES += ['batch_autolock_locked_partial_target','batch_locked_wire_records','batch_orb_restored_wording']
# Issue #25 refused copy page (SETUP/EXPECT/GUARD; EXPECT fails at 8eb6a3a by design). Parent #25 stays open.
NAMES += ['triage_copy_refusal']

# Issue #29 triage regression (SETUP/EXPECT/GUARD; EXPECT fails at 8eb6a3a by design).
NAMES += ['triage_locked_diagnostics']

# Selectable appearance, the embedded Orb history page and the Build Progress presentation.
NAMES += ['ui_theme_appearance','orb_history_embedded','advisor_build_progress','advisor_build_progress_runtime']
NAMES += ['orb_mini_panel']
NAMES += ['hud_orb_mini_access']
NAMES += ['ui_theme_native_templates']
NAMES += ['ui_theme_setup_dialogs']
NAMES += ['help_theme_appearance']
NAMES += ['log_viewer_theme_appearance']
NAMES += ['overwrite_warning']
NAMES += ['overwrite_warning_template_init']
NAMES += ['tome_wishlist_revisit']
NAMES += ['tome_wishlist_priority']
NAMES += ['tome_state_journal','tome_state_observation']
NAMES += ['tome_state_rows']
NAMES += ['overwrite_auto_gate']
NAMES += ['overwrite_warning_lifecycle']
NAMES += ['overwrite_warning_clock']
NAMES += ['server_status_reload_consumer']
NAMES += ['share_preparation_read_reuse','orb_panel_refresh_failure']
NAMES += ['orb_continue_affordance']
NAMES += ['overwrite_warning_welcome']

# Offline-peer lifetime and exact attribution regressions (actual modules, synthetic APIs).
NAMES += ['offline_peer_owner','offline_peer_lifecycle','offline_peer_notices','offline_peer_reentrancy']
NAMES += ['offline_peer_callbacks','offline_peer_scope_boundaries']
NAMES += ['offline_peer_legacy_dps']
NAMES += ['offline_peer_status_probe']
NAMES += ['startup_legacy_relay_pair_width']

# NX-03 slot projection catalog work (BOUND fails at 3d52b0e by design) and its semantic controls.
NAMES += ['stutter_slot_projection','stutter_catalog_semantics']
# NX-02 Orb display reconciliation work (BOUND fails at 3d52b0e by design) and its semantic controls.
NAMES += ['stutter_orb_display','stutter_orb_authority']
# NX-01 scheduled Echo catalog check work (BOUND fails at 3d52b0e by design) and its lifecycle controls.
NAMES += ['stutter_catalog_budget','stutter_catalog_lifecycle']
# CX-04 Orb run pump assignment reads (BOUND fails before the CX-04 fix by design) and its semantic controls.
NAMES += ['stutter_orb_pump','stutter_orb_pump_authority']
# NX-02 Orb display reuse expiry with display-only reads, backward clock and exact opt-ins (review B1).
NAMES += ['stutter_orb_display_expiry']
NAMES += ['dps_sync_digest_publication']  # DPS digest across an in-window catalog publication (public route).
# Nexus Saved Build selection across native Wishlist changes (Journal picker/gear destinations) and its boundaries.
NAMES += ['saved_build_wishlist_transition','saved_build_wishlist_destination_guards']
# AutoLock: a native Wishlist row is neither ownership evidence nor an unlock context (review 03 B1).
NAMES += ['saved_build_wishlist_autolock_guard']
# Wishlist Editor entries follow the Nexus Saved Build selection; never a native Wishlist index (review 03 N1-N3).
NAMES += ['saved_build_wishlist_editor_context']
# Evidence-pending role picker: assignment follows the Nexus selection; an unknown native read refuses (review 07 R1, U).
NAMES += ['saved_build_wishlist_evidence_picker']
# Build Progress details: a validated Pending list is not drawn twice; unknown summaries keep raw lines (approved cleanup).
NAMES += ['journal_pending_summary_dedup']
# UX M1: persistent truthful save/assignment result and captured-destination confirmations (EXPECT fails at 84de977 by design).
NAMES += ['ux_save_assignment_result','ux_captured_destination_labels']
# UX M2: replayable setup, manual recommendation marker/charges consumer, direct Help pages and chooser routes (EXPECT fails on accepted M1 by design).
NAMES += ['ux_setup_replay','ux_manual_recommendation','ux_help_navigation']
# Priority user bug: one logical Wishlist Create uploads once; new same-name Wishlists get copy names (EXPECT fails on delivered1704 and pre-fix current by design).
NAMES += ['wishlist_create_once','wishlist_unique_names']
NAMES += ['manual_external_orb_refresh']
NAMES += ['manual_refresh_projection_consistency']
# UX M3: Save changes vs Save & assign intents, bound destinations, truthful partial/unconfirmed results, Auto consent and scope (EXPECT fails on accepted ea3268a8 by design).
NAMES += ['ux_save_intents','ux_auto_assignment_consent','ux_automation_scope']
# UX M3 review repair: a spaced Save changes keeps its bound confirmation; every Auto-ON assignment route asks before any role or assignment write (EXPECT fails on combined-03 2594d591 by design).
NAMES += ['ux_save_retry_intent','ux_assignment_consent_routes']
# UX M4: captured destination presentation, one qualified count vocabulary, record scope/detail and terminology lint (EXPECT fails on accepted M3 ab3cb307 by design).
NAMES += ['ux_destination_context','ux_qualified_counts','ux_record_scope_terms']

# Wall-clock limit for one test process. It is a runner limit only: no test, timer or budget reads it.
DEFAULT_TIMEOUT_SECONDS=45
# Exact test names with a larger limit; every other test gets DEFAULT_TIMEOUT_SECONDS. No patterns.
# Through a local LuaJIT bridge they passed in 42-43 s and 58-61 s; hosted CI run 36000257959
# (ubuntu-latest, apt luajit) stopped both at 45 s.
# main() refuses a name here that is not in NAMES, so a misspelt name cannot silently get 45 s.
TEST_TIMEOUT_SECONDS={'catalog_root_capacity':120,'sync_admission_traffic_acceptance':120}

# Issue #132: an accepted Wishlist upload stays bound to the editor/Create context and draft that
# authorized it (SETUP/EXPECT/GUARD; EXPECT fails at 791cdcc by design: equal-content context-less
# replacement and the partial notice that names the uploaded Wishlist).
NAMES += ['wishlist_upload_context']

def timeout_for(name:str)->int:
    return TEST_TIMEOUT_SECONDS.get(name,DEFAULT_TIMEOUT_SECONDS)

def main() -> int:
    ap=argparse.ArgumentParser()
    ap.add_argument('--runtime',choices=['auto','luajit','lua54'],default='auto')
    ap.add_argument('--output',type=pathlib.Path,default=pathlib.Path('prototype-test-results.json'))
    ap.add_argument('--only',help='Comma-separated existing test names for a bounded shard; omitted runs every test')
    ns=ap.parse_args()
    unlisted=sorted(set(TEST_TIMEOUT_SECONDS)-set(NAMES))
    if unlisted: ap.error('TEST_TIMEOUT_SECONDS names a test that is not listed: '+', '.join(unlisted))
    names=ns.only.split(',') if ns.only else NAMES
    if len(names)!=len(set(names)) or any(n not in NAMES for n in names): ap.error('Unknown or duplicate --only test')
    native=shutil.which('luajit')
    if ns.runtime=='luajit' and not native: ap.error('LuaJIT requested but not installed')
    if native and ns.runtime!='lua54': command=[native]; runtime='LuaJIT'
    else:
        if not ctypes.util.find_library('lua5.4'): ap.error('Neither requested LuaJIT nor liblua5.4 is available')
        command=[sys.executable,str(ROOT/'tools/prototype_lua54.py')]
        runtime='Lua 5.4 with test-only compatibility shims; NOT LuaJIT/Lua 5.1/WoW'
    env=os.environ.copy()
    results=[]
    # Every listed test runs; none needs a separate checkout or archive.
    for name in names:
        # 'seconds' is the measured elapsed time, also for TIMEOUT; 'timeout_seconds' is the configured limit.
        timeout=timeout_for(name);start=time.monotonic()
        try:
            p=subprocess.run(command+[f'tests/prototype/{name}.lua'],cwd=ROOT,env=env,text=True,capture_output=True,timeout=timeout)
            row={'test':name,'status':'PASS' if p.returncode==0 else 'FAIL','exit':p.returncode,
                 'seconds':round(time.monotonic()-start,6),'timeout_seconds':timeout,'stdout':p.stdout,'stderr':p.stderr}
        except subprocess.TimeoutExpired as exc:
            row={'test':name,'status':'TIMEOUT','seconds':round(time.monotonic()-start,6),'timeout_seconds':timeout,
                 'stdout':str(exc.stdout or ''),'stderr':str(exc.stderr or '')}
        results.append(row);print(name,row['status']);print(row.get('stdout','').rstrip());print(row.get('stderr','').rstrip())
    runtime_files=[]
    for line in (ROOT/'Nexus.toc').read_text().splitlines():
        if line.strip() and not line.startswith('#'):
            p=ROOT/line.replace('\\','/');runtime_files.append({'path':str(p.relative_to(ROOT)).replace('\\','/'),'sha256':hashlib.sha256(p.read_bytes()).hexdigest()})
    report={'schema':'nexus-prototype-tests/1','runtime':runtime,'selected_tests':names,'complete_inventory':NAMES,'source_runtime_files':runtime_files,
            'scope':'Prototype-specific synthetic offline tests, not the original 245-runner suite or native WoW validation',
            'results':results,'passed':sum(r['status']=='PASS' for r in results),
            'failed':sum(r['status'] in ('FAIL','TIMEOUT') for r in results),'not_run':sum(r['status']=='NOT_RUN' for r in results)}
    out=ns.output.resolve();out.parent.mkdir(parents=True,exist_ok=True);out.write_text(json.dumps(report,indent=2),encoding='utf-8')
    print('REPORT',out);return 1 if report['failed'] or report['not_run'] else 0
if __name__=='__main__': raise SystemExit(main())
