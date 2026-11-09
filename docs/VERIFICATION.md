# Standalone extraction verification — October 30, 2026

Local release candidate 0.1.0, numeric version 1. Nothing was uploaded. This report concerns the standalone product, not the complete private fork.

## Source and package

The standalone source builds and tests from a separate clean copy with no private checkout or local books. Seven product/profile tests, sixteen canonical catalog tests, sixteen transformed catalog tests, 1,551 quality assertions, 205 material-model assertions and fourteen activation/conflict assertions passed. Deterministic ZIP packaging includes only 25 runtime/documentation/manifest files. All relative package documentation links resolve. All eighteen runtime files in the test world's installed-mod cache match the package manifest. No development runtime modules were installed in hack/scripts; only clearly named test probes were added there. Production imports resolved to the installed KhazalidNames cache.

The fork export dry-run verified 62 files and reported zero changes. The preservation audit found all 6,224 pre-existing files unchanged. Independent source/package review is in [extraction-review.md](extraction-review.md). Source and archive manifests support later provenance review; they are not redistribution permission.

## Native evidence

The isolated runtime reported DF v0.53.14 win64 STEAM and DFHack 53.14-r2. It contained only vanilla content and KhazalidNames, no Forthammer assets, initializer, custom gameplay modules or existing user saves. Sound was disabled and volumes zero. Game binaries, saves and private lab files are not distributed.

- An initial vanilla-only world had no standalone naming script on its active path. The standalone world then loaded the mod from its own installed cache.
- World generation: 91 Dwarf historical names passed; zero custom-word leakage into global or other-civilization selectors. Two thousand person draws gave 1,961 distinct names, and two thousand site draws reached all 301 labels. Native independent draws can repeat.
- Actual generated Dwarf civilizations/governments matched the reviewed pools. The native core test passed 531,532 assertions; these are data/policy assertions, not that many distinct gameplay scenarios.
- Both naming overlays registered enabled without a global initializer. Through the normal zone/location UI, a tavern, library, hospital and miners' guildhall received reviewed names. Creation-guard native fixtures passed and were cleaned up.
- Artifact adapter: 431 assertions plus 20 actual-widget GUI assertions passed. Lower-fit acceptance, cancellation/next-choice wrap, stale state, item linkage, physical description and pause restoration were checked. Fifty complete 363-option lists took 0.317 CPU seconds total in this fixture.
- Item facts: 205 model and 1,751 native assertions passed using 833 initialized native items. Fork-only handgun, gunpowder and warpstone native fixtures were explicitly skipped; model exclusion tests remain. The production mod does not require these objects.
- Expanded native generation/rendering, thirteen adapter categories, repeated installation, nested cleanup, 21 collision controls and 67 native nickname assertions passed. Temporary fixtures were removed and borrowed native items restored.
- Explicit site and forename acceptance passed, including unit/soul/historical-figure synchronization and rejection of proposal replay. After normal save, complete process shutdown and cold load, all 1,879 snapshotted name records matched, including the four actual institutions. The accepted site/person edits separately passed reload checks.
- A second normal save and cold process restart preserved all 1,879 names again and all eight snapshotted native weapon fact signatures and descriptions. The isolated game was stopped after verification.
- Conflicting-provider refusal was tested with temporary active-mod provider substitution in the native runtime and with executable model tests. It was not tested by installing the two conflicting raw packages together; such coexistence remains unsupported. The provider was restored and normal eligibility rechecked.

Machine reports are in [native-evidence](native-evidence/). Copied JSON evidence was normalized from native CP437 where necessary into UTF-8 with escaped non-ASCII characters. Runtime raws retain their required encoding. [Naming menu screenshot](native-evidence/names-menu.png) was visually inspected at 1280 by 800; exhaustive resizing and every scrolling state are not claimed.

## Limits

Artifact tests use initialized native items and temporary artifact linkage, not a naturally crafted standalone artifact. No long migration/birth campaign, actual natural-artifact persistence, or broad version/platform matrix was run. Tests of lower-level native squad generation do not substitute for an actual squad-management UI test. Native sex-specific forenames and separate architectural-site generation remain the documented pre-existing limitations. Existing saves are not migrated.

Publication remains separate: resolve code attribution/licensing, selected book-derived data and the inherited vanilla translation fallback. No blanket license has been applied. The private fork remains private and unchanged.

The first copied native fact harness still expected a fork-only handgun and failed before completing. The standalone test profile was corrected to report that native fixture as unavailable; the complete corrected run passed. No production change or fork raw import was needed.
