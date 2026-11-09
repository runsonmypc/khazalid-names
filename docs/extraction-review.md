# Extraction implementation review

Reviewed October 30, 2026 against `extract-standalone-khazalid-names`. This is an independent implementation review, not a certification of native game compatibility or redistribution rights.

## Verified claims

- **Runtime dependency closure:** the generated standalone includes all four public naming entry points and their internal naming imports. Script, raw-word, translation, session and hook identities are independently transformed. No runtime import points back into the private fork.
- **Activation isolation:** the installer, pool lookup and edit adapter retain their eligibility checks and reject ForthammerLocal coexistence. Executable tests cover inactive worlds, unrelated active mods, both conflicting-provider list orders and positive standalone eligibility. Missing modeled selector structures ensure the rejected installer paths cannot proceed with writes.
- **Preserved behavior:** the fork profile emits source bytes unchanged. The standalone changes product identities and explicit conflict refusal while retaining native selector setup, squad/location overlays, item-fit logic and guarded explicit edits. Existing sex-independent native forenames and shared surname/site selection remain limitations.
- **Single source/export:** the authoritative source is allowlisted. Export validates every destination before writing, rejects concurrent drift and supports a destination-bound checkpoint for subsequent updates. Initial extraction hashes remain separate evidence; ongoing maintenance does not require changing them to pass profile checks.
- **Independent build:** a fresh temporary copy containing only this standalone project completed all ordinary checks and packaging, without reading the private checkout or book corpus.
- **Package closure:** the reviewed archive has 25 entries: 24 content files and its manifest. Every content digest matches the manifest; all relative Markdown links resolve. The archive excludes development tools/tests, book images/PDFs, game binaries and private filesystem paths.
- **Honest release status:** player documentation identifies the compatibility target and pending native qualification, new-world activation, cached-raw preservation, provenance review and unsupported provider combinations. No public license is inferred.

## Independent checks

The clean-copy command `python3 build.py check` passed:

- 5 extraction/product tests at the independent clean-copy checkpoint, including deterministic package builds and stale generated-output rejection. The build agent subsequently expanded this to 7 tests covering vanilla fixture adaptation and reported passing results.
- 16 catalog/compiler tests in each of the source and standalone profiles.
- 1,551 offline quality assertions.
- 205 artifact-fact model assertions.
- 14 activation/conflict assertions against transformed shipping entry points.

A separate archive inspection verified manifests, relative documentation links and excluded file classes. The reviewed package digest is recorded in its generated checksum; rebuilding after documentation changes correctly changes that digest.

## Findings resolved during review

1. Added the changelog to the package so the README link resolves.
2. Separated ongoing source/profile parity from frozen extraction hashes and supplied export checkpoints, avoiding a maintenance deadlock.
3. Made copied native helpers use the standalone lab environment/helper namespace instead of a fixed previous lab path.
4. Added executable conflict refusal tests instead of relying solely on string inspection.

No unused extraction abstraction or verified shipping-code defect was found in this review. This is bounded to inspected code and executed checks; it does not establish that all possible game behavior is correct.

## Native evidence reviewed

The new standalone evidence under [native-evidence](native-evidence/) records:

- 18 packaged metadata/raw/runtime files matching the isolated installed product; execution from the installed mod cache rather than private development paths.
- 91 valid historical Dwarf names, no invalid historical names and zero global or other-entity selector leaks. Separate native draw samples cover characters and the 301-name physical-site pool.
- Four actually created institutions through native UI input: tavern, library, hospital and guildhall; previously existing locations remained unchanged.
- 431 artifact-adapter assertions and 20 production GUI-widget assertions using temporary native artifact fixtures. GUI coverage includes cancellation, next alternative, lower-fit acceptance and restoration of initially paused/unpaused state. This is fixture coverage, not natural artifact crafting.
- 1,956 artifact-fact assertions: 205 model and 1,751 native assertions across 833 temporary native items. Fork-only handgun, gunpowder and warpstone native cases are explicitly skipped; their model coverage remains. Vanilla dragon fixtures replace the unavailable fork dragon.
- Expanded native-category, integration, collision and nickname checks passing. Scoped naming selectors restore correctly; no global leakage was recorded.
- Two cold-process reloads preserved all 1,879 snapshotted native name records; accepted site/person edits passed reload checks. The second reload also preserved eight native weapon fact signatures and descriptions. These are name-record and native-item comparisons, not a natural artifact-crafting test.
- An initial vanilla-only world lacked the standalone script on its active path. Conflict refusal was verified through native active-provider substitution and model tests, not by combining unsupported raw packages.
- 6,224 pre-existing fork files unchanged, with none missing. Copied JSON evidence now parses as UTF-8; runtime raw encoding was retained.

This review inspected the evidence files and their explicit coverage boundaries; the parent task ran the game. It does not substitute older fork results for standalone qualification.

## Gates outside this review

Actual naturally crafted standalone artifacts, long migration/birth campaigns, the complete native squad-management UI flow and a broad platform/version matrix remain unverified. The tested runtime is DF 53.14 win64 with DFHack 53.14-r2 under Wine; do not expand this into a claim covering native Linux, macOS or other releases. Publication permission and final branding remain separate release decisions.

## Review disposition

The implementation and evidence review required by task 5.1 is complete. No unresolved verified extraction defect remains. The final verification report accurately distinguishes implemented behavior, actual creation, native fixtures, model coverage and untested scenarios. Marking this review complete does not authorize publication or close the documented broader compatibility limits. Strict OpenSpec validation and the final package checksum belong to the parent task's release record.
