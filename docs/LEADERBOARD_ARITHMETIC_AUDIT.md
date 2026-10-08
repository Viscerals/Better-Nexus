# Leaderboard arithmetic and selection: the seven L-gap cases

Status: audit with one bounded fix. Offline evidence only; no native test. The test is
`tests/prototype/leaderboard_arithmetic_cases.lua` (real boot, saved-data admission, board, pairing
and window; synthetic players).

## Contract (from the code and the UI text, not invented)

- A record counts when its session length meets the category minimum (`MIN_SESSION_SECS`: Training
  Dummy 30 s, Lich King 20 s; `DpsCapture.IsDurationEligible`: finite and `>=` the minimum; an unknown
  category has none) and its score is positive. The board shows the integer floor of the score.
- A category tab ranks by score (highest first), then earlier record time, then player name, then
  public identity.
- "Both records" needs ONE character's own Training Dummy and Lich King record on the same ordinary
  evidence and the same exact locked combat identity (spell, quality, copy total), owner proved
  (`CandidateEvidence.PairIdentity`). It ranks by the HIGHEST single eligible result; the average,
  (dummy + Lich King) / 2, is display-only and is shown with the fraction dropped (`DpsText`). Window
  text: "ranked by strongest single DPS ... the displayed average does not set the rank".
- Pair ties (`PairBefore`): best score, then identity, then the tie key. Window ties
  (`LeaderboardBefore`): best score, then player name, then public identity.

## Result by case

| # | Case | Hand-worked oracle (examples) | Result |
|---|---|---|---|
| 1 | Eligibility and ordering | Dummy: 29.999 s out, 30 s and 30.001 s in; Lich King: 19.999 s out, 20 s and 20.001 s in; 25 s is out for Dummy and in for Lich King; NaN, inf, -inf, nil, "abc", 0, negative durations out; unknown category lists nothing. Dummy board 810 700 510 150 100 80; Lich King board 820 600 520 420 120 100 1 | agrees |
| 1 | Score admission | 150.9 -> 150; 1.9 -> 1; 0, -5 out. **inf and nan were admitted, 0.5 was listed as 0** | **fixed** (below) |
| 2 | Highest single vs average | 100/100 -> avg 100, best 100; 150/1 -> avg 75.5 (shown 75), best 150; 80/120 -> avg 100, best 120. Order 150, 120, 100 although 150's average is lowest | agrees |
| 3 | Several records per identity | pair of maxima 120/110 -> avg 115; winners removed -> 100/90 avg 95; a duplicate counts once (both sources kept) | agrees |
| 4 | Ties | best 100 three ways with averages 70, 80, 100 -> Alpha, Bravo, Charlie (identity at pair level, name in the window); reversed input unchanged; board ties: earlier record, then name | agrees |
| 5 | Missing counterpart | Dummy-only and Lich King-only characters stay on their tab, no combined row, no zero row; adding the counterpart gives exactly one pair (700/200 -> best 700, avg 450) | agrees |
| 6 | Owner and combat | another proved owner with the same name and ordinary evidence, an unproved owner, a different locked spell, a different locked copy total, different ordinary evidence: none pair; the matching owner pairs | agrees |
| 7 | Filter, detail, display | class filter keeps order and renumbers; the detail text equals the row (`Strongest 520 DPS / Average 515 ...`); 75.5 is displayed 75 and the row keeps 75.5; flooring at the board seam: 150.9 and 1.9 pair as 150 and 1, average 75.5 | agrees |

## The one discrepancy and its fix

`DpsCapture.DpsBoardEntry` admitted any score above 0. A non-finite saved score (inf, nan) therefore ranked
on the Training Dummy and Lich King tabs (inf first, nan out of order) while `CandidateEvidence.PositiveFiniteDps`
already refused it in the pair arithmetic, and a score below 1 was listed as score 0. Admission now requires a
finite score whose floor is at least 1. Such rows could appear in the Leaderboard from saved data. The known
writers make them unlikely (receive requires a finite score of at least 1000; the local writer floors the score),
but a non-finite score from Details! is a theoretical local source, so they are not claimed impossible. The
check applies to what the Training Dummy and Lich King tabs list; other readers of saved scores (nameplate rank,
qualification summaries, retention ranking) are unchanged. Rows with a valid score behave exactly as before.

## Not changed, recorded

- `DPS.GetCharacterBest`, `DPS.GetPlayerInfo` (nameplate rank, which counts strictly higher raw scores and so
  does not follow the board's tie-break), the qualification summaries and `DataRetention` still use raw
  scores above 0; they are not leaderboard arithmetic and were not audited further.
- The pair tie key writes numbers as a length prefix plus text, so among equal-score, equal-authority rows of
  different duration the chosen row is deterministic but not always the numerically smaller duration for
  fractions. It is not a ranking input; the test asserts order independence only.
- Scores of 1000 and above display as `k`/`M` text; the fixtures are below 1000.
