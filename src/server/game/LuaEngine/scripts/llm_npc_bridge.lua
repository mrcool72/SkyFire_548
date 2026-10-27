-- Opt-in proof of concept: Eluna gossip <-> world DB queue <-> external LLM worker.
-- Set NPC_ENTRY to one dedicated, nonessential creature_template.entry after
-- manually applying tools/llm_npc/schema.sql. Disabled by default.
-- Do not bind to vendors, trainers, quest givers, or other gameplay NPCs.
local NPC_ENTRY = 0
local GOSSIP_HELLO = 1
local GOSSIP_SELECT = 2
local ASK_ACTION = 1
local COOLDOWN_SECONDS = 10
local REPLY_MAX_AGE_SECONDS = 120
local last_question = {}
local seen_replies = {}

if NPC_ENTRY == 0 then
    return
end

-- Encode all player-controlled strings as MySQL hex literals; never interpolate
-- raw chat text into SQL. Keep GUIDs strictly limited to Eluna's 0x... format.
local function sql_text(value)
    return "CONVERT(0x" .. value:gsub(".", function(c)
        return string.format("%02X", string.byte(c))
    end) .. " USING utf8mb4)"
end

local function valid_guid(guid)
    return type(guid) == "string" and #guid <= 18
        and guid:match("^0x[%da-fA-F]+$") ~= nil
end

local function on_hello(event, player, creature)
    player:GossipMenuAddItem(0, "Ask me a question", 0, ASK_ACTION, true,
        "Ask this character a question (up to 240 bytes).", 0)
    player:GossipSendMenu(1, creature)
end

local function on_select(event, player, creature, sender, action, code)
    player:GossipComplete()
    if sender ~= 0 or action ~= ASK_ACTION then
        return
    end

    if type(code) ~= "string" or #code == 0 or #code > 240
        or code:find("[%z\1-\8\11\12\14-\31]") then
        player:SendBroadcastMessage("Please enter a question of 1-240 bytes without control characters.")
        return
    end

    local player_guid, npc_guid = player:GetGUID(), creature:GetGUID()
    if not valid_guid(player_guid) or not valid_guid(npc_guid) then
        player:SendBroadcastMessage("This character cannot answer right now.")
        return
    end

    local now = GetGameTime()
    if last_question[player_guid] and now - last_question[player_guid] < COOLDOWN_SECONDS then
        player:SendBroadcastMessage("Please wait a moment before asking again.")
        return
    end

    local npc_name = creature:GetName():sub(1, 96)
    local player_name = player:GetName():sub(1, 48)
    local statement = string.format(
        "INSERT INTO llm_npc_dialogue (player_guid, npc_guid, npc_entry, npc_name, player_name, prompt) " ..
        "VALUES ('%s', '%s', %d, %s, %s, %s)",
        player_guid, npc_guid, NPC_ENTRY,
        sql_text(npc_name), sql_text(player_name), sql_text(code))
    WorldDBExecute(statement)
    last_question[player_guid] = now
    player:SendBroadcastMessage(npc_name .. " is thinking...")
end

local function deliver_replies()
    -- Bounded indexed lookup; DB reads are synchronous in this Eluna version.
    local result = WorldDBQuery(
        "SELECT id, player_guid, npc_guid, npc_entry, npc_name, status, response " ..
        "FROM llm_npc_dialogue WHERE status IN ('done', 'failed') " ..
        "AND created_at >= NOW() - INTERVAL " .. REPLY_MAX_AGE_SECONDS ..
        " SECOND ORDER BY id LIMIT 25")
    if not result then
        return
    end

    local now = GetGameTime()
    repeat
        local id = result:GetUInt64(0)
        local player_guid = result:GetString(1)
        local npc_guid = result:GetString(2)
        local npc_entry = result:GetUInt32(3)
        local npc_name = result:GetString(4)
        local reply = result:GetString(6)
        if not seen_replies[id] then
            seen_replies[id] = now
            -- An NPC can only speak if the player is still near the exact
            -- creature that was asked; otherwise send a private text reply.
            if npc_entry == NPC_ENTRY and valid_guid(player_guid) and valid_guid(npc_guid) then
                local player = GetPlayerByGUID(player_guid)
                if player and player:IsInWorld() then
                    local npc = player:GetWorldObject(npc_guid)
                    if npc and npc:GetEntry() == NPC_ENTRY
                        and player:IsWithinDistInMap(npc, 12) then
                        npc:SendUnitSay(reply, 0)
                    else
                        player:SendBroadcastMessage(npc_name .. ": " .. reply)
                    end
                end
            end
            WorldDBExecute("UPDATE llm_npc_dialogue SET status = 'delivered' " ..
                "WHERE id = " .. tostring(id) .. " AND status IN ('done', 'failed')")
        end
    until not result:NextRow()

    -- Keep the in-memory deduplication cache bounded.
    for id, timestamp in pairs(seen_replies) do
        if now - timestamp > REPLY_MAX_AGE_SECONDS then
            seen_replies[id] = nil
        end
    end
    for guid, timestamp in pairs(last_question) do
        if now - timestamp > REPLY_MAX_AGE_SECONDS then
            last_question[guid] = nil
        end
    end
end

RegisterCreatureGossipEvent(NPC_ENTRY, GOSSIP_HELLO, on_hello)
RegisterCreatureGossipEvent(NPC_ENTRY, GOSSIP_SELECT, on_select)
CreateLuaEvent(deliver_replies, 2000, 0)
print("[Eluna] LLM NPC dialogue bridge enabled for creature entry " .. NPC_ENTRY)
