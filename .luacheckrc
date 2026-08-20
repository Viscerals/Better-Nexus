std = "lua51"
max_line_length = false
codes = true
color = false
globals = {
  "Nexus", "UIParent", "GameTooltip", "DEFAULT_CHAT_FRAME", "SlashCmdList",
  "CreateFrame", "StaticPopupDialogs", "StaticPopup_Show", "GetTime", "GetSpellInfo",
  "GetItemInfo", "GetItemIcon", "GetRealmName", "UnitName", "UnitGUID", "UnitClass",
  "UnitExists", "UnitIsPlayer", "UnitIsConnected", "UnitIsDeadOrGhost", "UnitAffectingCombat",
  "GetNumGroupMembers", "GetNumRaidMembers", "GetNumPartyMembers", "IsInRaid", "IsInGroup",
  "SendAddonMessage", "RegisterAddonMessagePrefix", "C_ChatInfo", "ChatThrottleLib",
  "LibStub", "Details", "date", "time", "wipe", "bit", "strsplit", "tContains"
}
exclude_files = { "node_modules/**", ".tools/**", "build/**" }
