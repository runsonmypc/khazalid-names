# Player guide

## Install for a new world

This local candidate was tested with DF 53.14 and DFHack 53.14-r2, using vanilla content plus this mod in an isolated Windows/Wine runtime on Linux. Other versions and native operating-system builds are unverified. Tests covered fresh world generation and embark, institution creation, explicit edits, artifact fixtures and cold-reload names; they do not certify long campaigns or every naturally created artifact.

1. Build the package or obtain a verified release ZIP. Extract the `KhazalidNames` folder into the game's user mod directory so its `info.txt` is directly inside `KhazalidNames`.
2. Start Dwarf Fortress through DFHack. Select **Khazalid Names** when creating a new world, alongside the normal vanilla modules.
3. Do not select Forthammer, ForthammerLocal, another Khazalid Names version, or another mod changing Dwarf naming/language selectors in the same world. Runtime conflict refusal cannot undo conflicting raw changes made during world creation.
4. Embark with a normal Dwarf civilization. Open the DFHack console and run `gui/khazalid-names` for explicit suggestions and edits.

The mod ID is `KhazalidNames`; displayed version is `0.1.0`, numeric version `1`. No global initializer, Forthammer files, book corpus or network service is needed. Do not copy development probe scripts into a normal installation.

## Generate suggestions

```text
khazalid-names person-male 5
khazalid-names person-female 5
khazalid-names hold 8
khazalid-names artifact 8
khazalid-names help
```

Counts are integers from 1 to 100, default 1. A batch contains distinct names; a request larger than a category's pool is rejected before printing a partial batch. Different invocations can repeat names. Output includes selected meanings, adaptation status and source references. Console generation does not edit the game.

Available categories are `forename-male`, `forename-female`, `person-male`, `person-female`, `family`, `clan`, `hold`, `settlement`, `mountain`, `pass`, `cavern`, `stream`, `lake`, `squad`, `civilization`, `government`, `tavern`, `guildhall`, `library`, `hospital`, `business`, `artifact`, `road`, `tunnel`, `bridge` and `wall`.

## Preview and apply

Run `gui/khazalid-names` in an eligible Dwarf fortress. Select one of your civilization's Dwarfs first to propose a forename. A forename edit preserves its family name and nickname and synchronizes the native name records. The fortress option proposes a hold name. Additional-target menus list eligible existing objects; not every visible building or item qualifies.

A confirmation shows the old and proposed names. **Enter** accepts; **Escape** cancels. Save normally to preserve an accepted edit. If the target, name, world or relevant item facts change, the old proposal is invalidated. Existing occupied names are checked again at acceptance; exhaustion is reported without inventing suffixes. A squad's custom alias must be deliberately cleared before editing its generated name.

Artifact choices require a linked artifact/named-equipment record and a verified Dwarf maker from the current civilization. Ordinary items and separately titled written works are excluded. Select an eligible named item, then choose **Propose a fitted name for the selected item**, or use the artifact target list. Every unused compatible title is available, ordered as best fits, other fits and symbolic imagery. Escape from a confirmation returns to the choices with the next alternative selected; closing the list makes no edit or reservation.

Concrete material, equipment and depicted-creature words require observed support. Decorations do not turn a copper-alloy or stone body into solid silver. Unknown properties remain unknown. Symbolic moonlight or thunder does not assert a physical effect. Naming grants no powers, artifacts, deeds or ownership.

## Automatic naming and its limits

| Situation | Behavior |
| --- | --- |
| New world with mod and DFHack | Curated Dwarf selectors feed native generation; DF handles inheritance. |
| New fortress name | Native generation uses the shared 301 family/site labels. Longer hold names are explicit proposals. |
| Newly created tavern, guildhall, library or hospital | Supported native location-creation input initializes that new institution with a reviewed name. Existing institutions, temples, reassignment and cancelled creation are excluded. Third-party creation scripts are not intercepted. |
| New squad through supported creation route | A scoped selector override supplies reviewed squad names and restores the previous selectors immediately afterward. |
| Migrant or visitor | Keeps the identity it already has. There is no arrival-time rename watcher. |
| Existing artifact | Keeps its name unless an eligible explicit edit is confirmed. Global artifact naming remains unchanged. |
| Other civilizations | Curated Dwarf selectors do not replace global/non-Dwarf selectors. Explicit edits require the active mod and an eligible Dwarf fortress. |
| DFHack absent | Curated selectors and editing tools are unavailable; native fallback vocabulary is not presented as Khazalid. |

DF's native first-name selector has no sex input: native generation mixes the 93 male and 113 female source names. Explicit commands preserve the separate lists. DF also shares its surname and physical-site selector. These are unresolved engine integration limits, not lore rules. Manual edits do not solve automatic creation.

Family/clan outputs are symbolic labels, not proof of ancestry or recognized membership. Patronymics and earned epithets are deliberately not manufactured. Geographical proposals should be chosen for corresponding real features; they do not locate or create mountains, rivers or resources. Infrastructure targets are qualifying named world constructions, not individual local wall tiles. Religious, cultural-work and event naming remains outside scope.

## Updates, removal and existing saves

Initial installation is **new-world only**. Do not add these raws to an existing vanilla or Forthammer world and do not copy a translation into its cached raws. Saved names contain word indices; changing their definitions can corrupt their meaning.

Keep a world's matching installed mod cache and scripts. Do not overwrite that cache with a future version unless its release explicitly documents and verifies compatibility. Back up saves before any update. Loading the current mod does not silently rename existing identities.

Before creating a world, removal means deselecting the mod and removing its unused source folder. Once a world uses it, retain its matching cache for that world. Disabling DFHack does not undo names already created or accepted. There is no automatic conversion back to vanilla names and no background rename queue.
