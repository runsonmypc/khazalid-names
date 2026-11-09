# Khazalid Names

Khazalid names for Dwarf Fortress with DFHack: Dwarf characters, settlements, institutions, squads and carefully fitted artifact titles. This is a focused naming mod, independent of Forthammer and its gameplay systems.

**Development candidate: 0.1.0.** This standalone source repository is public; no Steam Workshop release has been published. No blanket license is granted for the mixed-provenance code and data; see the provenance notes. Tested with **Dwarf Fortress 53.14 and DFHack 53.14-r2**, using a fresh vanilla-content world in an isolated, muted Windows runtime under Wine on Linux. Other versions and native operating-system builds are not yet qualified. World generation, all four supported institution creation flows, explicit edits, artifact fixtures and cold-reload name preservation passed. This is bounded compatibility evidence, not a long-running campaign test.

Names use attested vocabulary and personal-name tables from official Warhammer books. New compounds are reviewed adaptations, not newly discovered canonical names or claims about a character's history. Famous identities are screened out; that screening cannot guarantee coverage of every published name.

## Start here

- [Installation, use and save safety](docs/PLAYER-GUIDE.md)
- [Name capacities and repetition](docs/CAPACITIES.md)
- [Sources and lore policy](docs/SOURCES.md)
- [Credits, provenance and publication review](docs/PROVENANCE.md)
- [Changelog](CHANGELOG.md)

Select **Khazalid Names** when creating a **new world**, with DFHack enabled. Do not combine it with Forthammer or another Dwarf naming provider. Open the DFHack console and run:

```text
khazalid-names person-male 5
khazalid-names hold 8
gui/khazalid-names
```

Console commands only suggest names. The interface previews explicit edits and asks you to confirm. Loading a save does not rename existing people or places. Native world generation still shares its surname/site pool and mixes male and female forename lists; these limitations are explained in the player guide.

## Build from source

Python 3 is required for generation and packaging; the offline Lua checks also require the Lua 5.4 shared library (`liblua5.4-0` on Ubuntu). From this project directory:

```sh
python3 build.py check
python3 build.py build --profile standalone
python3 build.py package
```

The development build is `build/standalone/KhazalidNames` and includes tools that should not be installed in a normal game. The clean player package is `dist/KhazalidNames-0.1.0.zip`, accompanied by a content manifest and checksum. The allowlisted package excludes development tools, tests, research images, books and unrelated gameplay modules. Game testing requires a separately supplied, isolated DF/DFHack installation; no game binaries are included.

`source/` is the shared naming source. Do not hand-edit generated output. A separate fork profile preserves the existing integration's identifiers and raw ordering. `python3 build.py export-fork /path/to/fork` performs a dry run; `--apply` permits only checked, drift-safe naming exports. After an applied export, use `--checkpoint build/fork-export-checkpoint.json` for subsequent exports so the last applied state remains the drift baseline. Do not use that developer export command to install the player mod.

This is an unofficial fan project. Credits and citations are attribution, not a redistribution license or an endorsement by the original publishers.
