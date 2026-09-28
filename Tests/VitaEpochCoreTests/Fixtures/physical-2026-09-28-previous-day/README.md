# Previous-day movement evidence — 28 Sep 2026

Source: `prompts/CODEX_X6_PREVIOUS_DAY_MOVEMENT_ADDENDUM.md`, reporting nRF requests/replies on the physical X6, serial EDA75689, firmware MOY-I4E3-1.1.6. This is a physical-capture **document transcription**, not a downloaded nRF log.

`frames-verbatim.txt` and `capture.json` preserve the two complete 188-byte frames exactly: `0213 0100` and `0213 0107`, each with 180 raw positions. `manifest.json` records the prompt hash, frame hashes/lengths, exact reported requests, device identity, mapping and limits. The fixture uses deterministic packet IDs. No packet bytes were padded or repaired, and no values are constructed.

The capture date is 28 Sep in Asia/Amman. Exact notification times were not supplied; 12:03 +03:00 is an explicit analysis anchor only. Mapping to the previous calendar day uses the known local date, not the invented precision of an exact receipt time. No TX timestamps were fabricated; the two reported requests are preserved in the manifest.

- `0100`: 27 Sep 00:00–02:59. Its 180 payload bytes match the prior 27 Sep `0000` capture exactly.
- `0107`: 27 Sep 21:00–23:59. Only the last 30 positions, 23:30–23:59, intersect the second-night reference window.

`DDPP` with DD 0/1 and PP 0–7 is strongly supported. Only previous-day pages 0 and 7 were physically observed in this session. The six middle previous-day pages, offsets above 1, retention depth and exact amplitude meaning are not physically validated. No sleep stage is encoded or inferred here.

The old current-day fixture remains unchanged. Combine it with this evidence using the analysis CLI's `--movement-evidence` argument. Alignment is bounded to the supplied reference window; page 0100 contributes no rows to the second-night analysis.
