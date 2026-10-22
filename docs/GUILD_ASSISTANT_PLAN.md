# Guild Assistant — port plan

Guild Assistant is Nrage Assistant (imported at `f24a640`) opened to **any guild**. The only access requirement is
being in a guild. The addon detects which guild the player is in and keeps that guild's data apart from every other
guild's.

## Decisions

| Topic | Decision |
|---|---|
| Access | Only `IsInGuild()`. No guild name, club id, faction or PvP-ruleset check. |
| Addon folder / TOC | `GuildAssistant/GuildAssistant.toc`, title `Guild Assistant`. |
| SavedVariables | `GuildAssistantDB`. New addon: no data to migrate from `NrageAssistantDB`. |
| Slash commands | `/guildassistant` and `/ga` (`SLASH_GUILDASSISTANT1`, `SLASH_GUILDASSISTANT2`). `/guild` is a native client command and must not be taken. |
| Comm prefixes | `ADDON_PREFIX = "GUILDASST"`, `POSITION_PREFIX = "GUILDASSTPOS"` (≤ 16 chars). Never talks to Nrage Assistant. |
| Export marker | `GUILDA1:` instead of `NRAGE1:`. |
| Guild key | `"club:<C_Club.GetGuildClubId()>"`; fallback `"name:<guild name>-<normalized realm>"` when the club id is unavailable. |
| Guild data | Per guild under `db.guilds[guildKey]`. Account settings (minimap, language, windows, sounds) under `db.settings`. Characters stay in `db.chars`. |
| Guild change in session | Joining a guild activates the addon. Leaving or switching to another guild deactivates it and asks for `/reload`. |
| Branding | Generic icon; UI and strings use the player's guild name where Nrage was named. |
| PvP features | Kept as they are; they also work on non-PvP realms. |
| CurseForge | No project yet. The release workflow must not publish anywhere until a new project id is set. |

## Phases

Each phase is one commit (or a few) on branch `feat/any-guild`. Run them in order; a phase starts only when the
previous one is green.

Verification for every phase:

```bash
export PATH="$HOME/.luarocks/bin:$PATH"
luacheck GuildAssistant tests
busted
```

> The local luarocks tree may target Lua 5.5 while the addon and CI use Lua 5.1, so local `busted` can fail on
> `unpack` and similar. CI (Lua 5.1) is the reference. Report local results as they are; do not "fix" 5.1 code for 5.5.

### P1 — Mechanical rename · level: medium · model: Haiku

Pure renames, no behaviour change. Tests must keep passing as they do today.

1. `git mv NrageAssistant GuildAssistant` and `git mv GuildAssistant/NrageAssistant.toc GuildAssistant/GuildAssistant.toc`.
2. TOC: `## Title: Guild Assistant`, `## Notes: Guild coordination and raid readiness for any guild.`,
   `## SavedVariables: GuildAssistantDB`, `IconTexture` path under `Interface\AddOns\GuildAssistant\Media\`.
   Rename `Media/nrage_logo*` to `Media/guild_logo*` (keep the image for now) and update every reference.
3. Every `NrageAssistantDB` → `GuildAssistantDB`; every `Interface\\AddOns\\NrageAssistant` → `...\\GuildAssistant`.
4. Constants: `ADDON_PREFIX = "GUILDASST"`, `POSITION_PREFIX = "GUILDASSTPOS"`. Export marker `NRAGE1:` → `GUILDA1:`
   wherever it is produced, parsed or tested.
5. Slash: `SLASH_GUILDASSISTANT1 = "/guildassistant"`, `SLASH_GUILDASSISTANT2 = "/ga"`,
   `SlashCmdList["GUILDASSISTANT"]`. Replace `/nrage` with `/ga` in every user-facing string, help text and comment.
6. User-facing strings: "Nrage" → "Guild Assistant" when it names the addon ("Nrage export" → "Guild Assistant
   export", "Nrage import" → "Guild Assistant import"); "Nrage Loot Council" → "Loot Council". Update the English
   source string **and** the matching `Locales/esES.lua` key and translation together, so no key is orphaned.
   Do not touch the four `disabled:` notices in `Core/Init.lua` (P2 owns them).
7. Tooling: `.luacheckrc` (globals, `exclude_files`, locale path), `.busted`, `.luacov`, `.styluaignore`,
   `tools/package.sh`, `tools/make_icons.py`, `.github/workflows/ci.yml` (`luacheck GuildAssistant tests`),
   `.github/workflows/release.yml` (zip name, release title, TOC path).
8. Release safety: in `release.yml` set `CF_PROJECT_ID: ""` and make the CurseForge step fail with
   `::error::CF_PROJECT_ID is not set` when it is empty. Never leave `1757381` (Nrage's project).
9. Tests: update paths, globals, prefixes and expected strings only.

Done when `grep -rniI "nrage" --exclude-dir=.git --exclude-dir=Libs GuildAssistant tests tools .github .luacheckrc .busted`
only returns hits in the `AccessGuard`/`Constants`/`Init` notices that P2 removes.

### P2 — Any guild, guild detection and per-guild data · level: high · model: Sonnet

1. **AccessGuard** (`Core/AccessGuard.lua`): only `not_in_guild`. Remove `GUILD_NAME`, `GUILD_CLUB_ID`, `FACTION`,
   `RULESET_REALM_MARKER` from `Constants.lua` and the `wrong_guild` / `wrong_faction` / `wrong_ruleset` notices
   and locale entries. Add a `guild_unknown` case: in a guild but the client has not returned the guild name/club id
   yet (common for a few seconds after login) → stay inactive silently and re-evaluate on `PLAYER_GUILD_UPDATE` /
   `GUILD_ROSTER_UPDATE`, without printing a notice.
2. **Guild identity** (`Core/Platform.lua` + new `Core/GuildIdentity.lua`): `GuildIdentity.Current(platform)` returns
   `{ key, name, realm }` or `nil`, following the guild-key rule in Decisions. Pure function, unit-tested.
3. **Per-guild store** (`Core/Store.lua`): schema 13.
   - Root layout: `{ schemaVersion, settings = {...}, guilds = { [guildKey] = <what db.global was> }, chars = {...} }`.
   - `Store.ForGuild(db, guildKey)` creates/returns the guild table with every sub-table the migrations create today.
   - Migration 13: create `guilds` and `settings`; drop any leftover `db.global` (no installs exist yet).
   - Keep the ~100 existing `db.global` call sites untouched: on activation build the runtime view
     `ns.db = { global = root.guilds[key], settings = root.settings, chars = root.chars, root = root }`. The view is
     never assigned back to `GuildAssistantDB`, so SavedVariables never serializes a table twice.
   - `Domain/Settings.lua` and `UI/MinimapButton.lua` (and anything else reading `global.settings`) read and write
     `db.settings`, so minimap, language and window settings are account-wide and work before the guild is known.
   - `db.chars[identityKey]` is per character and therefore already per guild; leave it.
4. **Activation and guild change** (`Core/Init.lua`): activation needs the guild identity. Remember the active guild
   key. If `PLAYER_GUILD_UPDATE` reports no guild or a different key while active: set `ns.active = false`, stop
   publishing, and print once "guild changed: type /reload to load <guild>'s data." Do not try to re-wire live
   services to another guild's tables.
5. **Comm boundary** (`Sync/Comm.lua`): verify that a `WHISPER` addon message from someone who is not in the current
   guild roster is dropped before it is decoded. If it is not, add the check (reason `not_in_guild`) and a test.
6. **Guild name in the UI**: window title, loaded message and other strings that named Nrage use the detected guild
   name through a format placeholder (for example `"%s Loot Council"`). Update `esES.lua` in step.
7. **Diagnostics**: `/ga debug identity` prints the guild key and how it was resolved (club id or name fallback).
8. **Tests**: `access_guard_spec` (only not-in-guild and guild-unknown), new `guild_identity_spec`, `store_spec` for
   migration 13 and `ForGuild` isolation (two guild keys never share roster/loot/events), init/activation test for
   guild change, comm whisper test, settings tests against `db.settings`.
9. Update `docs/PROTOCOL.md` (prefixes, export marker) and `docs/API_NOTES.md` (club id as guild key).

### P3 — Docs, release notes and cleanup · level: low · model: Haiku

1. `README.md`, `docs/USER_GUIDE.md`, `docs/PRIVACY.md`: rewrite for Guild Assistant, any guild, `/ga` commands,
   data kept per guild. Remove Nrage-only content (guild requirement, faction/ruleset, CurseForge link to Nrage).
2. Delete Nrage feature plans that no longer apply as plans: `plan.md`, `docs/REDESIGN_PLAN.md`,
   `docs/PVP_MISSIONS_PLAN.md`, `docs/LAYER_SWAP_PLAN.md`, `docs/GUILD_MAP_PLAN.md`. Their history stays in
   `addon-nrage-assistant`.
3. `release-notes/`: remove Nrage's notes and add `release-notes/v0.1.0.md` describing the port.
4. Final sweep: the `grep -rniI "nrage"` from P1 over the whole repo (excluding `.git` and `Libs`) returns nothing,
   except a single line in `README.md` crediting Nrage Assistant as the origin.

## Out of scope

- A new logo/icon (the user provides it).
- Creating the CurseForge project and its `CF_API_TOKEN` secret.
- Changing role assignment (`ROLE_SOURCE = "assigned"`, guild master as admin): already generic.
