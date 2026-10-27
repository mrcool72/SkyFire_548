-- Apply manually to the SkyFire WORLD database before enabling llm_npc_bridge.lua.
-- Isolated queue: no changes to Blizzard quest, movement, combat, or creature tables.
CREATE TABLE IF NOT EXISTS llm_npc_dialogue (
    id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    player_guid CHAR(18) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    npc_guid CHAR(18) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    npc_entry INT UNSIGNED NOT NULL,
    npc_name VARCHAR(96) NOT NULL,
    player_name VARCHAR(48) NOT NULL,
    prompt VARCHAR(240) NOT NULL,
    response VARCHAR(240) DEFAULT NULL,
    status ENUM('pending', 'processing', 'done', 'failed', 'delivered') NOT NULL DEFAULT 'pending',
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    KEY idx_llm_npc_status_id (status, id),
    KEY idx_llm_npc_created_at (created_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
