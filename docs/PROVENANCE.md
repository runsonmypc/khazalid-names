# Credits, provenance and publication gate

This local candidate extracts the Khazalid naming subsystem developed in a private Forthammer fork. It does not include Forthammer's creatures, graphics, charter, magic, initializer or unrelated gameplay systems. It is not an official product or an endorsement by Bay 12 Games, DFHack, Games Workshop, Cubicle 7 or the upstream mod author.

## Inventory

| Material | Provenance | Review needed before publication |
| --- | --- | --- |
| Naming Lua, compiler and tests | Added during development of the private fork, then adapted for this standalone product. | Confirm authorship/contribution rights and select a code license. New paths alone do not prove every line is original. |
| Khazalid vocabulary, selected meanings and forename tables | Official books listed in [Sources](SOURCES.md); compiled into reviewed catalogs. | Review the distribution of the selected book-derived data separately from code. Citation is not permission. |
| Complete compounds, category constraints and fit policy | Project adaptations using those sources. | Do not describe complete compounds or project grammar as printed canon. |
| Vanilla Dwarven translation fallback | Compatibility mapping decoded from Dwarf Fortress language raws; deliberately not Khazalid. | Review redistribution of this inherited game data. It is a substantial external-data component even though no executable is bundled. |
| Native integration patterns | DFHack interfaces and naming/synchronization behavior informed implementation. | Inspect any incorporated code and retain notices applicable to it; use of an API alone is not a provenance audit. |
| Player documentation and packaging | Standalone extraction work. | Confirm contributor attribution and eventual license coverage. |

The verified upstream import is commit `1f30d3bef48ec9e27cab741273c4889891f6c531`, tagged `upstream-0.1.8.0-1807332073001238862`. An October 30, 2026 path comparison found none of the 18 audited naming-runtime/compiler Python paths in that import. This establishes that those files were added after the import; it is **not** a line-by-line originality or licensing determination. Naming data and generated outputs still include the external material above.

Forthammer Fantasy's upstream metadata credits **7isAnOddNumber**. The private fork's provenance record found no standalone redistribution license in the inspected upstream package. The standalone extraction therefore does not grant itself rights to upstream material or place the whole result under an assumed permissive license. Exact build/source manifests record the extracted content for subsequent review.

Credit also belongs to the authors and publishers of the cited Warhammer books, Bay 12 Games for Dwarf Fortress, and DFHack contributors for the integration platform. These acknowledgements do not imply that those parties authored or approved this mod.

## Licensing and release notes

The repository is public at the owner’s request. The following work remains before selecting a blanket license or publishing a Workshop release:

- Resolve contributor attribution and code licensing; inspect any copied implementation fragments and required notices.
- Resolve the selected vocabulary/forename and vanilla translation data distribution questions.
- Confirm no private paths, research scans, corpus extracts, game binaries or unrelated private-fork content appear in the exact release archive.
- Complete standalone native verification, record the tested versions, and distinguish naturally created objects from synthetic test fixtures.
- Select final branding and publish an accurate compatibility statement and known-limitations list.

Publishing this repository does not itself settle these provenance questions or grant a blanket license. No Workshop item has been published.
