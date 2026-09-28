# Physical evidence transcribed from the 27 Sep handoff

Source: `prompts/CODEX_X6_PHYSICAL_EVIDENCE_SLEEP_PASS.md`. This is a transcription of the supplied document, not a newly downloaded iPhone/nRF archive. The source bytes are unchanged; `manifest.json` records frame sizes and SHA-256 hashes. `frames-verbatim.txt` preserves the complete frame lines as supplied.

`capture.json` uses explicit capture provenance and the known serial/firmware. It does not invent BLE device-information notifications. The 18:58 +03:00 receipt anchor is approximate, supplied for current-day alignment; it is not an exact per-notification timestamp. The movement request time 18:57:57 comes from the document. Other attempt times are not supplied.

- `020B`: complete physical frame, four independently matched vendor timestamps on 26 Sep.
- `0210`: complete physical page 0000, twelve nonzero readings. Later pages are described in prose but their bytes are not supplied.
- `0213`: pages 0000–0005 are complete, 188 bytes each. Pages 0006 and 0007 each contain only 186 bytes while declaring 188. They are retained and rejected without padding or borrowing bytes from the next frame.
- `0216`: only the four word excerpts are supplied. They are stored as excerpts, never made into a purported physical frame. Full-frame temperature tests are explicitly constructed.
- `020E`: the three reported no-response attempts are preserved as negative evidence. They are not added to the command list.
- `0212`: incomplete header excerpts remain uninterpreted. They do not establish a sleep duration.

`sleep-reference.json` contains the 47 vendor-labeled intervals, used only by the offline research utility. These labels are not independently validated clinical ground truth and are never ingested as app sleep results.

Constructed edge cases live in `PhysicalEvidenceTests.swift`, separately from these physical bytes. The app's own continuation and radio behavior still require physical revalidation.
