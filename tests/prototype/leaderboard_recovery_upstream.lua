-- Leaderboard recovery at an upstream-shaped size, above the old shared
-- 2048-key budget. Synthetic data only; no player data.
--
-- The shape follows the saved maps an older retention owner (upstream Good
-- Enough Nexus 1.96.6) produced after four weeks: about 760 builds, 224
-- removal markers and 1620 numeric retention markers. Here: 707 builds,
-- 225 removal markers and 1621 retention markers, 2553 identities, in the
-- legacy saved locations. The code that shares one 2048-key budget refuses
-- this data at start-up; capacity envelope V2 admits it.
--
-- leaderboard_recovery_rows.lua runs unchanged at this size, with its
-- optional 30-day step: the harness clock moves 31 days forward and a real
-- start-up expires every retention marker, while removal markers, builds,
-- saved scores and every rendered Leaderboard row stay exactly as they were.
-- settleSeconds bounds the post-start-up background work at this size
-- (first-start evidence compaction; see the test header).
LEADERBOARD_RECOVERY_SIZE={
 extraBuilds=700,removalMarkers=224,retentionMarkers=1620,
 keyBudget=6144,minDistinctKeys=2049,markerShape='legacy',
 settleSeconds=1500,expireAfterDays=31,
}
dofile('tests/prototype/leaderboard_recovery_rows.lua')
