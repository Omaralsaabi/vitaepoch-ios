# First X6 validation session

Use the current device firmware from the handoff. The following steps require a physical iPhone and the user's band; simulator checks do not establish BLE compatibility.

1. Build and install using the owner's signing team. Open Device, scan, and select X6.
2. Verify firmware, manufacturer, serial, and battery match the band. Confirm FDD3 subscriptions complete before the first history query.
3. Allow one sync to finish. Check the raw log for the seven expected query features. A missing response should produce a partial-sync state rather than a successful timestamp.
4. Compare manual HR, SpO₂, stress, steps, distance, and calories against known Da Halo values. Preserve the raw evidence for discrepancies.
5. Check HR slots at 00:00/12:00 and HRV/temperature page boundaries in local time. Confirm day-offset interpretation against a known previous-day capture, including a DST transition if relevant.
6. Start and stop one heart-rate measurement. Confirm both TX commands and a fresh 2A37 result. A timeout must leave the app responsive.
7. Move out of range, return, and verify reconnect attempts are bounded. Turn Bluetooth off and on. Deny permission in Settings and confirm saved data remains visible.
8. Relaunch the app and resync. Confirm identical history readings do not duplicate. Daily FDD1 and 020D totals must be treated as alternative snapshots, never summed.
9. Inspect unknown or malformed responses in diagnostics. They must survive in the local archive without producing invented readings.

Do not write unknown commands or FDD5. Sleep and raw PPG remain unimplemented pending evidence.
