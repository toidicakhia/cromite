# Windows 7 compat patches (base 153.0.8010.27)

Imported from <https://github.com/e3kskoy7wqk/Chromium-for-windows-7-REWORK>
(directory `chromium-153.0.8010.27`, imported 2026-10-20).

- 335 `.diff` files + `commit_message_*.txt` + original `commit_hashes.txt`.
- Apply order: `build/win7_patches_list.txt` (= reverse of `commit_hashes.txt`:
  newest upstream removal reverted first, oldest last, then `rust01`, `rust02`).
- `cdm_module.cc_corrected.diff` was intentionally **skipped** (cromite does not
  ship Widevine, the patch would be inert).
- Applied by `scripts/04b-apply-win7-patches.sh` after the cromite patchset
  (`04-apply-patches.sh`), before `gn gen`. Enabled with `WITH_WIN7=1`.
- `overrides/skip/<hash>` (empty file) drops `<hash>.diff` from all phases:
  XP/Vista-only code, dead WP-capable paths and revert entries made obsolete by
  cromite's newer libraries. Full list + rationale in `overrides/skip/README.md`.
- `overrides/base27/<hash>.patch` / `overrides/deps/<hash>.patch` replaces
  `<hash>.diff` when the original does not apply on 153.0.8010.37 (context
  drift + cromite conflicts); the replacement is applied by the same phase as
  the original.
- Expected run summary (2026-10-20 optimization): 335/335 performed, 50 skipped,
  35 `[WIN7]` commits.
