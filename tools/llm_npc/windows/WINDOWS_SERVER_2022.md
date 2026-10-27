# SkyFire 5.4.8 + experimental NPC AI — Windows Server 2022

This guide assumes x64 Windows Server 2022. **All experimental changes should
live in a separate repo** (suggested: `mrcool72/SkyFire_548_AI`). The original
`mrcool72/SkyFire_548` main branch is never edited or pushed by this setup.

## 1. Create a completely separate GitHub repository

On a Windows development machine install [Git for Windows](https://git-scm.com/)
and [GitHub CLI](https://cli.github.com/), then authenticate using
`gh auth login`. You need repository-creation permission on your account.

In PowerShell, run:

    git clone --single-branch --branch feature/llm-npc-dialogue-bridge-20261027 https://github.com/mrcool72/SkyFire_548.git C:\SkyFireAI-bootstrap
    & C:\SkyFireAI-bootstrap\tools\llm_npc\windows\New-SkyFireAIRepository.ps1

The script **creates a new private GitHub repository**, clones the entire
SkyFire code with the feature commits to `C:\SkyFire_548_AI`, renames the
branch to `main`, **removes the original Git remote**, and pushes only to
the new repository. It stops if the destination folder or new repo already
exists. Supply `-NewRepo` or `-Destination` to change those defaults.

An operator needs to run this script because ChatGPT's GitHub connector
does not expose repository creation. The bootstrap directory is temporary.
All future code changes should be made in the new repository checkout.

## 2. Install compiler and build dependencies

See the [current SkyFire Windows guide](https://wiki.projectskyfire.org/index.php/Installation_%28Windows_5xx%29)
for installation details. This codebase currently expects:

- Windows Server 2022 x64; Visual Studio 2022 with **Desktop development
  with C++**, MSVC toolchain **19.44.35217.0+**, and Windows SDK.
- CMake **4.1.2+**.
- Boost **1.91.0**, usually at `C:\local\boost_1_91_0`.
- OpenSSL **4.0.1** x64 **including the legacy provider**.
- MySQL client development headers and libraries plus a working database
  service; edit default `C:\tools\mysql\current` if yours differs.
- Properly sourced client and data files for **WoW 5.4.8 build 18414**.
  Blizzard's proprietary client assets are not included.

**Known Windows CI blocker (Oct 27, 2026):** The existing Windows workflow
fails before it compiles C++ because Chocolatey's OpenSSL 4.0.1 installer
URL returns 404. There is an [official OpenSSL 4.0.1 Windows testing
installer](https://github.com/openssl/installer/releases/tag/testing_release)
with an x64 Visual Studio variant. It is **pre-release software**.
Confirm its signature, development libraries, version, directory layout,
and legacy provider before using it. This is a manual dependency option,
**not** a verified source-code build fix.

Run the non-invasive prerequisites checks:

    & C:\SkyFire_548_AI\tools\llm_npc\windows\Test-WindowsPrerequisites.ps1

## 3. Configure and build, without overwriting old binaries

From Windows PowerShell on the build host:

    Set-Location C:\SkyFire_548_AI
    Copy-Item .\skyfire-build.config.ps1.example .\skyfire-build.config.ps1
    notepad .\skyfire-build.config.ps1

In `CMakeOptions`, set `ELUNA = 'ON'`. Adjust `BoostRoot`,
`OpenSslRootDir`, `OpenSslModules`, and `MySqlRoot` to match your
installation. Set `InstallPrefix = 'C:\SkyFire_Files\Server_AI'` so no
existing SkyFire installation is overwritten.

Use the repository's existing build helper:

    .\SkyFire-Build.ps1 configure
    .\SkyFire-Build.ps1 build-install

The build helper does not initialize your full game deployment.
Configure authserver/worldserver, auth/characters/world databases,
and required client-derived data via the SkyFire installation guide.
Verify client login, quests, combat and map loading **before** AI.

## 4. Enable one NPC dialogue after basic server startup

1. Back up the WORLD database. Apply `tools\llm_npc\schema.sql` manually.
   In PowerShell use CMD for input redirection:

       cmd.exe /d /c 'mysql -u root -p world < "C:\SkyFire_548_AI\tools\llm_npc\schema.sql"'

   Adapt the MySQL executable and DB name. Only the new queue table is created.

2. Choose a dedicated, nonessential creature with gossip enabled.
   Change `NPC_ENTRY = 0` in
   `src\server\game\LuaEngine\scripts\llm_npc_bridge.lua`
   to its real `creature_template.entry`. Keep `0` to leave it disabled.
   Ensure this edited Lua file is installed under `etc\lua_scripts`
   and restart the worldserver.

3. Start the Python LLM worker on the external computer.
   Follow [worker setup](../README.md). Use Python 3.10+ and PyMySQL.
   Configure a least-privileged MySQL user with only SELECT, UPDATE,
   DELETE on the queue table, plus firewall and TLS for remote access.
   Set the model API URL (remote endpoints must use HTTPS) and model ID.

4. Start with `python tools\llm_npc\worker.py` from the external
   server checkout. Test an in-game gossip question and inspect the queue.

## Acceptance checks

- Required Visual Studio, CMake, Boost, OpenSSL and MySQL libraries are valid.
- authserver and worldserver build, start, and remain stable without AI.
- Correct 5.4.8 client connects; maps/DBC/vmaps/mmaps and game databases work.
- Basic original gameplay is regression tested (quests, mobs, spells, loot).
- An opted-in NPC sends and receives one LLM response without stalling
  the worldserver; outages and logouts are handled.
- Credentials stay out of Git; model responses cannot run server commands.

**Full Blizzard-level MoP parity and autonomous combat bots are not yet
implemented.** Both need separate game-mechanic tests, navigation and a
server-authoritative action allowlist before broader deployment.
