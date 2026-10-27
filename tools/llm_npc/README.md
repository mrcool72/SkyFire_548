# SkyFire 5.4.8 — experimental LLM NPC dialogue

**Scope:** This is an opt-in single-NPC dialogue prototype, **not** a complete
playerbot system or a replacement for SkyFire's game logic. SkyFire targets WoW
5.4.8 build 18414. An LLM process on a different server generates short text;
the worldserver retains all authority for movement, spells, rewards and quests.

## Architecture

1. A player selects **Ask me a question** on one opted-in creature.
2. Eluna writes a question into a dedicated WORLD database queue.
3. An external Python worker claims the question, asks an OpenAI-compatible
   chat-completions API, and writes a bounded dialogue-only response.
4. Eluna polls every 2 seconds. If the player is still near the same creature,
   the NPC speaks; otherwise the player receives a private server message.

No LLM-generated command is executed by SkyFire. This Eluna fork exposes
synchronous `WorldDBQuery`, so pilot with one NPC and low traffic. An
asynchronous native bridge is the recommended scale-up path.

## Prerequisites

- Working authserver, worldserver, and WORLD database. See the main
  [SkyFire README](../../README.md) and existing platform-specific guides.
- Build/install with `ELUNA=ON`. On Windows set `ELUNA = 'ON'` under
  `CMakeOptions` in your untracked `skyfire-build.config.ps1`, then run
  `.\SkyFire-Build.ps1 build-install`. On Ubuntu configure CMake with
  `-DELUNA=ON -DSCRIPTS=ON` along with the compiler and libraries documented
  in the project README; then build and install.
- A legitimately sourced matching WoW 5.4.8 build 18414 client and its
  matching world data, maps, DBC, vmaps and mmaps. Those proprietary client
  assets are not supplied by this feature.
- Python 3.10+, MySQL connectivity, and an OpenAI-compatible LLM API.

## Enable on a nonessential test NPC

1. Back up the WORLD database. Apply the **optional** [schema.sql](schema.sql)
   manually (it is not in automatic SkyFire SQL updates):

   `mysql -h 127.0.0.1 -u your_admin -p world < tools/llm_npc/schema.sql`

   Replace `world` with the actual WORLD DB name if different.

2. Select one test creature with a working gossip interaction and find its
   `creature_template.entry`. Do **not** bind important quest givers, vendors,
   trainers, bosses, or other original-content characters. A dedicated
   custom test creature with gossip enabled is preferable.

3. Change `NPC_ENTRY = 0` in
   [llm_npc_bridge.lua](../../src/server/game/LuaEngine/scripts/llm_npc_bridge.lua)
   to that numeric creature entry. **0 means disabled.** Place the edited
   script under the installed `etc/lua_scripts` (or reinstall the updated
   source build) and restart worldserver. Confirm the
   `[Eluna] LLM NPC dialogue bridge enabled` log message.

4. Start the worker on the outside server. Install its dependency in a
   Python virtual environment:

   `pip install -r tools/llm_npc/requirements.txt`

   Configure the environment as follows:

   | Variable | Meaning |
   | --- | --- |
   | `SKYFIRE_LLM_DB_HOST` | MySQL address, default `127.0.0.1` |
   | `SKYFIRE_LLM_DB_PORT` | MySQL port, default `3306` |
   | `SKYFIRE_LLM_DB_NAME` | WORLD DB name, default `world` |
   | `SKYFIRE_LLM_DB_USER` | **Required** restricted database username |
   | `SKYFIRE_LLM_DB_PASSWORD` | Password, read from a secret store or private environment |
   | `SKYFIRE_LLM_DB_SSL_CA` | **Required** for remote MySQL; trusted TLS CA cert path, with hostname verification |
   | `SKYFIRE_LLM_API_URL` | Chat completions URL, default `http://127.0.0.1:11434/v1/chat/completions` |
   | `SKYFIRE_LLM_MODEL` | Model ID, default `llama3.2` |
   | `SKYFIRE_LLM_API_KEY` | Optional Bearer token |
   | `SKYFIRE_LLM_TIMEOUT` | LLM HTTP timeout in seconds, default `15` |
   | `SKYFIRE_LLM_POLL_SECONDS` | Delay between empty queue polls, default `1` |

   A local Ollama server supporting its OpenAI-compatible API is one option;
   ensure the chosen model is installed and running. Remote LLM endpoints
   **must use HTTPS**. Start the worker:

   `python tools/llm_npc/worker.py`

   Use `--once` to process at most one queued item and exit.

5. Log into the matching client, interact with your test NPC, and submit a
   short question. Inspect recent queue statuses with:

   `SELECT id,status,created_at FROM llm_npc_dialogue ORDER BY id DESC LIMIT 10;`

## Security and operations

Create a MySQL user specific to the external worker. It requires only
`SELECT`, `UPDATE` and `DELETE` on `world.llm_npc_dialogue`, **not** access
to accounts, characters, or other world tables. For example, after creating
your user with a strong password and setting a trusted worker IP:

`GRANT SELECT, UPDATE, DELETE ON world.llm_npc_dialogue TO 'skyfire_llm'@'YOUR_WORKER_IP';`

Restrict inbound MySQL to the worker's trusted IP with a firewall, and use
encrypted database transport between hosts. Do not expose the DB publicly
or commit API tokens or credentials. The worldserver's existing database
connection inserts requests.

The LLM cannot edit quests, cast spells, or issue commands. Reply control
characters and WoW chat markup pipes are stripped, and text is limited to
220 UTF-8 bytes. Input requests are capped at 240 bytes and throttled per
player. Queued jobs expire after 90 seconds; delivered rows are deleted
after one hour and all rows after a day. Player questions are sent to the
configured model provider; choose an appropriate provider and privacy policy.

## Validation

Run worker unit tests without MySQL or an LLM:

`python -m unittest discover -s tools/llm_npc -p 'test_*.py' -v`

Live acceptance requires database, compiled ELUNA worldserver, compatible
game client, and reachable LLM. Verify gossip question/response, unavailable
model fallback, limits, logout behavior, and no gameplay-state changes.
Nearby players can hear NPC speech like ordinary game dialogue.

**Not yet implemented:** Blizzard-complete quests, raids, combat behavior,
pathfinding, pet battles, autonomous playerbots, LLM memory, or server-side
action approval. Those require separate in-game parity tests and a
server-authoritative action allowlist. Use this as a first integration slice.

For a complete Windows Server 2022 setup and independent repo creation, follow [the Windows guide](windows/WINDOWS_SERVER_2022.md).
