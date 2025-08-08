pico-8 cartridge // http://www.pico-8.com
version 42
__lua__
-- endless vertical jumper
-- with double jump and infinite platforms
function _init()
  -- player setup
  player = {
    x = 64,
    y = 100,
    w = 6,
    h = 6,
    dx = 0,
    dy = 0,
    jump_speed = -3.5,
    grounded = false,
    speed = 0.5,
    jumps_left = 1,
    max_jumps = 1,
    hearts = 3,
    max_hearts = 3,
    invuln_timer = 0, -- invulnerability after getting hit
    base_invuln_time = 60, -- base invulnerability time
    invuln_mult = 1.0, -- multiplier for invulnerability time
    attack_timer = 0, -- sword attack animation
    attacking = false,
    sword_size_mult = 1.0, -- multiplier for sword attack size
    overhead_slices = 0, -- number of overhead slice upgrades
    xp = 0,
    player_level = 1,
    xp_to_next = 10, -- xp needed for next level
    -- powerup multipliers
    speed_mult = 1.0,
    jump_mult = 1.0,
    jumps_color = {5, 8, 10}, -- colors for 0, 1, 2+ jumps
    -- gamefeel improvements
    coyote_timer = 0, -- frames player can still jump after leaving ground
    jump_held = false, -- is jump button currently held?
    jump_released = false, -- was jump button released this jump?
    apex_boost_used = false, -- has apex boost been used this jump?
    -- phantom players
    phantoms = {},
    next_phantom_side = 1, -- 1 for right, -1 for left
    vampire_chance = 0
  }
  
  -- level
  level = 1
  prev_level = 1
  
  -- level up animation
  levelup_timer = 0
  levelup_active = false
  
  -- powerup selection
  game_paused = false
  powerup_selection = false
  powerup_cursor = 1
  powerup_options = {}
  
  -- juice effects
  freeze_timer = 0
  shake_timer = 0
  shake_intensity = 0
  
  -- camera
  camera_y = 0
  camera_sp = -.3
  camera_follow_y = 60
  
  -- platforms
  platforms = {}
  next_platform_y = 80
  platform_spacing = 25
  
  -- enemies
  enemies = {}
  next_enemy_y = 60
  enemy_spacing = 50 -- spawn enemies more frequently (was 80)
  
  local initial_platform = {
    x = 0, -- random x position
    y = 110,
    w = 128-- level-based width
  }
  
  add(platforms, initial_platform)
  -- generate initial platforms
  for i = 1, 20 do
    add_platform()
  end
  
  -- game state
  score = 0
  highest_y = player.y
end

function jump()
  -- can jump if grounded, have coyote time, or have jumps left
  local can_jump = player.grounded or player.coyote_timer > 0 or player.jumps_left > 0
  
  if not can_jump then
    return
  end
  
  -- use coyote time or air jump
  if not player.grounded and player.coyote_timer > 0 then
    player.coyote_timer = 0 -- consume coyote time
  elseif not player.grounded then
    player.jumps_left -= 1 -- use air jump
    attack()
  end
  
  player.dy = player.jump_speed
  player.jump_held = true
  player.jump_released = false -- reset for this jump
  player.apex_boost_used = false -- reset apex boost for new jump
end

function attack()
  player.attacking = true
  player.attack_timer = 10 -- shorter animation duration
  
  -- main attack area (scaled by sword size multiplier)
  local base_attack_w = 12
  local base_attack_h = 12
  local attack_w = base_attack_w * player.sword_size_mult
  local attack_h = base_attack_h * player.sword_size_mult
  
  local attack_x = player.x - (attack_w - player.w) / 2
  local attack_y = player.y + player.h - 2
  
  check_attack_collision(attack_x, attack_y, attack_w, attack_h)
  
  -- overhead slice attack (if player has overhead slices)
  if player.overhead_slices > 0 then
    local slice_w = 8 + player.overhead_slices * 4 -- grows with upgrades
    local slice_h = 6 + player.overhead_slices * 2
    local slice_x = player.x - (slice_w - player.w) / 2
    local slice_y = player.y - slice_h - 2
    
    check_attack_collision(slice_x, slice_y, slice_w, slice_h)
  end
  
  -- phantom attacks
  for phantom in all(player.phantoms) do
    local phantom_attack_x = phantom.x - (attack_w - player.w) / 2
    local phantom_attack_y = phantom.y + player.h - 2
    
    check_attack_collision(phantom_attack_x, phantom_attack_y, attack_w, attack_h)
    
    -- phantom overhead slices
    if player.overhead_slices > 0 then
      local slice_w = 8 + player.overhead_slices * 4
      local slice_h = 6 + player.overhead_slices * 2
      local phantom_slice_x = phantom.x - (slice_w - player.w) / 2
      local phantom_slice_y = phantom.y - slice_h - 2
      
      check_attack_collision(phantom_slice_x, phantom_slice_y, slice_w, slice_h)
    end
  end
end

function check_attack_collision(attack_x, attack_y, attack_w, attack_h)
  for enemy in all(enemies) do
    if not enemy.dead and -- only attack living enemies
       enemy.x + enemy.w > attack_x and
       enemy.x < attack_x + attack_w and
       enemy.y + enemy.h > attack_y and
       enemy.y < attack_y + attack_h then
      
      -- enemy defeated! convert to dead state instead of deleting
      enemy.dead = true
      enemy.dead_timer = 60 -- how long before cleanup
      enemy.dead_color = 5 -- dark gray color when dead
      
      -- fling enemy away from player
      local fling_direction_x = enemy.x < player.x and -1 or 1
      local fling_direction_y = -1 -- always fling upward
      enemy.dx = fling_direction_x * (2 + rnd(2)) -- 2-4 horizontal speed
      enemy.dy = fling_direction_y * (1.5 + rnd(1.5)) -- 1.5-3 upward speed
      
      player.xp += 5 -- gain 5 xp per enemy
      
      -- juice effects for successful hit!
      freeze_timer = 4 -- freeze for 4 frames
      shake_timer = 6 -- shake for 6 frames
      shake_intensity = 3 -- shake strength
      
      -- check for level up
      if player.xp >= player.xp_to_next then
        player.xp -= player.xp_to_next
        player.player_level += 1
        player.xp_to_next += 5 -- increase xp requirement
        
        -- trigger powerup selection
        game_paused = true
        powerup_selection = true
        powerup_cursor = 1
        generate_powerup_options()
      end
      
      -- refresh double jump
      player.jumps_left = player.max_jumps
       
      -- chance to vampire heal
      if rnd(1) < player.vampire_chance then
        heal()
      end
      break -- only hit one enemy per attack in this collision area
    end
  end
end

function heal() 
  player.hearts += 1
  if player.hearts > player.max_hearts then
    player.hearts = player.max_hearts
  end
end
function _update()
  -- update juice effects
  if freeze_timer > 0 then
    freeze_timer -= 1
    return -- freeze the game!
  end
  
  if shake_timer > 0 then
    shake_timer -= 1
    shake_intensity *= 0.9 -- reduce shake over time
  end
  
  -- handle powerup selection when paused
  if game_paused and powerup_selection then
    -- powerup selection input (left/right instead of up/down)
    if btnp(0) and powerup_cursor > 1 then -- left
      powerup_cursor -= 1
    end
    if btnp(1) and powerup_cursor < 3 then -- right
      powerup_cursor += 1
    end
    
    -- select powerup
    if btnp(4) or btnp(5) then -- x or z
      apply_powerup(powerup_options[powerup_cursor])
      powerup_selection = false
      game_paused = false
      -- refresh jumps when resuming
      player.jumps_left = player.max_jumps
    end
    
    return -- don't run game logic while paused
  end
  
  -- update level up animation
  if levelup_active then
    levelup_timer -= 1
    if levelup_timer <= 0 then
      levelup_active = false
    end
  end
  
  -- update player invulnerability
  if player.invuln_timer > 0 then
    player.invuln_timer -= 1
  end
  
  -- update attack timer
  if player.attack_timer > 0 then
    player.attack_timer -= 1
    if player.attack_timer <= 0 then
      player.attacking = false
    end
  end
  
  -- player input
  if btn(0) then player.dx -= player.speed end -- left
  if btn(1) then player.dx += player.speed end -- right
  
  -- track button state for variable jump height (separate from jumping)
  local jump_btn_currently_held = btn(4) or btn(5)
  
  if jump_btn_currently_held then
    -- button is currently held
    if not player.jump_held then
      jump()
      -- just started holding (but jump was already triggered by btnp above)
      player.jump_held = true
      player.jump_released = false
    end
  else
    -- button is not held
    if player.jump_held then
      -- just released the button
      player.jump_released = true
      player.jump_held = false
    end
  end
  
  -- variable jump height: cut jump short if button released early
  if player.jump_released and player.dy < 0 and player.dy < player.jump_speed * 0.5 then
    player.dy *= 0.5 -- cut jump height in half
    player.jump_released = false -- only apply once per jump
  end
  
  -- apex boost: small horizontal boost when holding direction at jump peak
  if not player.grounded and not player.apex_boost_used and 
     player.dy > -0.5 and player.dy < 0.5 then -- near apex of jump
    
    local boost_strength = 0.8 -- horizontal boost amount
    local direction_held = false
    
    if btn(0) then -- holding left
      player.dx -= boost_strength
      direction_held = true
    end
    if btn(1) then -- holding right  
      player.dx += boost_strength
      direction_held = true
    end
    
    if direction_held then
      player.apex_boost_used = true -- only one boost per jump
    end
  end
  
  -- update coyote timer
  if not player.grounded then
    player.coyote_timer -= 1
    player.coyote_timer = max(0, player.coyote_timer)
  end
  
  -- apply physics
  player.dx *= 0.8 -- friction
  player.dy += 0.2 -- gravity
  
  -- limit speeds (affected by speed multiplier)
  -- local max_speed = 2 * player.speed_mult
  -- player.dx = mid(-max_speed, player.dx, max_speed)
  if player.dy > 4 then
    player.dy = 4
  end
  
  -- move player
  player.x += player.dx
  player.y += player.dy
  
  -- update phantom positions
  for phantom in all(player.phantoms) do
    phantom.x = player.x + phantom.offset_x
    phantom.y = player.y
  end
  
  -- wrap around screen horizontally
  if player.x < 0 then player.x = 128 end
  if player.x > 128 then player.x = 0 end
  
  -- check platform collisions
  local was_grounded = player.grounded
  player.grounded = false
  
  for platform in all(platforms) do
    if player.dy > 0 and -- falling
       player.y + player.h > platform.y and
       player.y + player.h < platform.y + 8 and
       player.x + player.w > platform.x and
       player.x < platform.x + platform.w then
      
      player.y = platform.y - player.h
      player.dy = 0
      player.grounded = true
      player.jumps_left = player.max_jumps
      player.coyote_timer = 2 -- reset coyote time when landing
      player.jump_released = false -- reset jump state on landing
      player.apex_boost_used = false -- reset apex boost on landing
    end
  end
  
  -- if just left ground, start coyote timer
  if was_grounded and not player.grounded then
    player.coyote_timer = 2 -- give 2 frames of coyote time
  end
  
  -- update enemies
  for enemy in all(enemies) do
    if enemy.dead then
      -- update dead enemy physics
      enemy.dead_timer -= 1
      enemy.dx *= 0.95 -- slow down horizontally
      enemy.dy += 0.3 -- gravity on dead enemies
      enemy.x += enemy.dx
      enemy.y += enemy.dy
      
      -- remove if timer expired or off screen
      if enemy.dead_timer <= 0 or 
         enemy.x < -10 or enemy.x > 138 or 
         enemy.y > camera_y + 160 then
        del(enemies, enemy)
      end
    else
      -- normal living enemy behavior
      enemy.bob_timer += 0.1
      enemy.x += sin(enemy.bob_timer) * 0.3
      enemy.y += cos(enemy.bob_timer * 1.5) * 0.2
      
      -- keep enemies roughly in bounds
      enemy.x = mid(5, enemy.x, 123)
    end
  end
  
  -- check enemy collisions (only with living enemies, only with main player)
  if player.invuln_timer <= 0 then
    for enemy in all(enemies) do
      if not enemy.dead and
         player.x + player.w > enemy.x and
         player.x < enemy.x + enemy.w and
         player.y + player.h > enemy.y and
         player.y < enemy.y + enemy.h then
        
        -- player hit!
        player.hearts -= 1
        player.invuln_timer = flr(player.base_invuln_time * player.invuln_mult)
        
        -- small knockback
        if player.x < enemy.x then
          player.dx = -1.5
        else
          player.dx = 1.5
        end
        player.dy = -2
        
        break -- only hit one enemy per frame
      end
    end
  end
  
  -- update score
  if player.y < highest_y then
    highest_y = player.y
    score = flr((100 - highest_y) / 10)
  end
  
  -- level progression based on score
  prev_level = level
  level = flr(score / 50) + 1 -- level up every 50 points
  
  -- trigger level up animation
  if level > prev_level then
    levelup_active = true
    levelup_timer = 90 -- 1.5 seconds at 60fps
  end
  
  -- update camera speed based on level
  camera_sp = -.3 - (level - 1) * 0.1 -- faster each level
  
  -- update camera to follow player (your improved version)
  local target_camera_y = player.y - camera_follow_y
  if target_camera_y < camera_y  and player.dy < 0  and camera_sp > player.dy then
  	camera_y = camera_y + (target_camera_y - camera_y) * 0.1
  else
   camera_y += camera_sp
  end
  
  -- generate new platforms as player goes up
  while next_platform_y > camera_y - 50 do
    add_platform()
  end
  
  -- generate new enemies as player goes up
  while next_enemy_y > camera_y - 50 do
    add_enemy()
  end
  
  -- remove old platforms below camera
  for platform in all(platforms) do
    if platform.y > camera_y + 150 then
      del(platforms, platform)
    end
  end
  
  -- remove old living enemies below camera (dead enemies clean themselves up)
  for enemy in all(enemies) do
    if not enemy.dead and enemy.y > camera_y + 150 then
      del(enemies, enemy)
    end
  end
  
  -- game over check (fall too far or no hearts)
  if player.y > camera_y + 150 or player.hearts <= 0 then
    _init() -- restart
  end
end

function _draw()
  cls(1) -- clear screen with dark blue
  
  -- apply camera shake
  local shake_x = 0
  local shake_y = 0
  if shake_timer > 0 then
    shake_x = (rnd(shake_intensity * 2) - shake_intensity)
    shake_y = (rnd(shake_intensity * 2) - shake_intensity)
  end
  
  -- set camera with shake
  camera(shake_x, camera_y + shake_y)
  
  -- draw platforms
  for platform in all(platforms) do
    rectfill(platform.x, platform.y, 
             platform.x + platform.w - 1, 
             platform.y + 3, 11) -- light green
    rectfill(platform.x, platform.y + 4, 
             platform.x + platform.w - 1, 
             platform.y + 7, 3) -- dark green
  end
  
  -- draw enemies
  for enemy in all(enemies) do
    if enemy.dead then
      -- draw dead enemy (upside down and different color)
      rectfill(enemy.x, enemy.y,
               enemy.x + enemy.w - 1,
               enemy.y + enemy.h - 1, enemy.dead_color) -- dark gray when dead
      
      -- upside down dead eyes (at bottom instead of top)
      pset(enemy.x + 1, enemy.y + 3, 0)
      pset(enemy.x + 3, enemy.y + 3, 0)
      
      -- optional: add X eyes for extra dead effect
      if enemy.dead_timer > 40 then -- show X eyes for first part of death
        pset(enemy.x + 1, enemy.y + 3, 8) -- red X
        pset(enemy.x + 3, enemy.y + 3, 8)
        pset(enemy.x + 2, enemy.y + 3, 0)
      end
    else
      -- draw living enemy normally
      rectfill(enemy.x, enemy.y,
               enemy.x + enemy.w - 1,
               enemy.y + enemy.h - 1, 8) -- red body
      
      -- simple enemy eyes
      pset(enemy.x + 1, enemy.y + 1, 0)
      pset(enemy.x + 3, enemy.y + 1, 0)
    end
  end
  
  -- draw phantom players
  for phantom in all(player.phantoms) do
    if player.invuln_timer <= 0 or player.invuln_timer % 8 < 4 then
      -- draw phantom with transparency effect (outline only)
      rect(phantom.x, phantom.y, 
           phantom.x + player.w - 1, 
           phantom.y + player.h - 1, 12) -- light blue outline
      
      -- phantom eyes
      pset(phantom.x + 2, phantom.y + 2, 12)
      pset(phantom.x + 4, phantom.y + 2, 12)
    end
  end
  
  -- draw player (flash when invulnerable)
  if player.invuln_timer <= 0 or player.invuln_timer % 8 < 4 then
    local jump_color_index = min(player.jumps_left + 1, #player.jumps_color)
    rectfill(player.x, player.y, 
             player.x + player.w - 1, 
             player.y + player.h - 1, player.jumps_color[jump_color_index])
    
    -- add simple face
    pset(player.x + 2, player.y + 2, 0) -- left eye
    pset(player.x + 4, player.y + 2, 0) -- right eye
  end
  
  -- draw sword attack animation
  if player.attacking then
    -- show attack area briefly (first few frames only)
    if player.attack_timer > 7 then
      -- main attack area
      local base_attack_w = 12
      local base_attack_h = 12
      local attack_w = base_attack_w * player.sword_size_mult
      local attack_h = base_attack_h * player.sword_size_mult
      local attack_x = player.x - (attack_w - player.w) / 2
      local attack_y = player.y + player.h - 2
      
      rect(attack_x, attack_y, attack_x + attack_w - 1, attack_y + attack_h - 1, 9)
      
      -- overhead slice
      if player.overhead_slices > 0 then
        local slice_w = 8 + player.overhead_slices * 4
        local slice_h = 6 + player.overhead_slices * 2
        local slice_x = player.x - (slice_w - player.w) / 2
        local slice_y = player.y - slice_h - 2
        
        rect(slice_x, slice_y, slice_x + slice_w - 1, slice_y + slice_h - 1, 10)
      end
      
      -- phantom attacks
      for phantom in all(player.phantoms) do
        local phantom_attack_x = phantom.x - (attack_w - player.w) / 2
        local phantom_attack_y = phantom.y + player.h - 2
        
        rect(phantom_attack_x, phantom_attack_y, 
             phantom_attack_x + attack_w - 1, phantom_attack_y + attack_h - 1, 12)
        
        -- phantom overhead slices
        if player.overhead_slices > 0 then
          local slice_w = 8 + player.overhead_slices * 4
          local slice_h = 6 + player.overhead_slices * 2
          local phantom_slice_x = phantom.x - (slice_w - player.w) / 2
          local phantom_slice_y = phantom.y - slice_h - 2
          
          rect(phantom_slice_x, phantom_slice_y, 
               phantom_slice_x + slice_w - 1, phantom_slice_y + slice_h - 1, 12)
        end
      end
    end
  end
  
  -- reset camera for ui (no shake on UI)
  camera()
  
  -- draw ui
  print("score: " .. score, 2, 2, 7)
  print("level: " .. level, 2, 10, 7)
  print("plv: " .. player.player_level, 2, 18, 7)
  print("xp: " .. player.xp .. "/" .. player.xp_to_next, 2, 26, 7)

  
  -- draw hearts
  for i = 1, player.max_hearts do
    local heart_x = 2 + (i - 1) * 8
    local heart_y = 34
    print("♥", heart_x, heart_y, i <= player.hearts and 8 or 5)
  end
  
  -- draw powerup selection screen
  if powerup_selection then
    -- semi-transparent background
    rectfill(0, 20, 128, 108, 0)
    
    -- title
    print("level up!", 24, 26, 10)
    
    -- draw 3 powerup rectangles
    for i = 1, 3 do
      local rect_x = 8 + (i - 1) * 38
      local rect_y = 35
      local rect_w = 36
      local rect_h = 50
      
      -- rectangle background and border
      local bg_color = 1 -- dark blue
      local border_color = 7 -- white
      
      -- rarity-based coloring
      if powerup_options[i].rarity == "rare" then
        bg_color = 2 -- dark purple for rare
        border_color = 14 -- pink for rare
      end
      
      if i == powerup_cursor then
        bg_color = 5 -- dark gray (highlighted)
        border_color = powerup_options[i].rarity == "rare" and 10 or 11 -- yellow pulse for rare, green for common
        -- pulsing effect
        if sin(time() * 4) > 0 then
          border_color = 10 -- yellow pulse
        end
      end
      
      rectfill(rect_x, rect_y, rect_x + rect_w, rect_y + rect_h, bg_color)
      rect(rect_x, rect_y, rect_x + rect_w, rect_y + rect_h, border_color)
      
      -- draw powerup icon
      local icon_x = rect_x + rect_w/2 - 4
      local icon_y = rect_y + 8
      
      if powerup_options[i].name == "apple" then
        -- heart icon
        rectfill(icon_x + 1, icon_y, icon_x + 2, icon_y, 8)
        rectfill(icon_x + 5, icon_y, icon_x + 6, icon_y, 8)
        rectfill(icon_x, icon_y + 1, icon_x + 7, icon_y + 1, 8)
        rectfill(icon_x, icon_y + 2, icon_x + 7, icon_y + 2, 8)
        rectfill(icon_x + 1, icon_y + 3, icon_x + 6, icon_y + 3, 8)
        rectfill(icon_x + 2, icon_y + 4, icon_x + 5, icon_y + 4, 8)
        rectfill(icon_x + 3, icon_y + 5, icon_x + 4, icon_y + 5, 8)
        
      elseif powerup_options[i].name == "jump boot" then
        -- boot/jump icon
        rectfill(icon_x + 2, icon_y, icon_x + 5, icon_y + 2, 12) -- boot top
        rectfill(icon_x, icon_y + 3, icon_x + 7, icon_y + 5, 12) -- boot sole
        -- upward arrows
        pset(icon_x + 3, icon_y - 2, 7)
        line(icon_x + 2, icon_y - 1, icon_x + 4, icon_y - 1, 7)
        pset(icon_x + 6, icon_y - 2, 7)
        line(icon_x + 5, icon_y - 1, icon_x + 7, icon_y - 1, 7)
        
      elseif powerup_options[i].name == "coffee" then
        -- lightning bolt icon
        line(icon_x + 3, icon_y, icon_x + 1, icon_y + 3, 10)
        line(icon_x + 1, icon_y + 3, icon_x + 4, icon_y + 3, 10)
        line(icon_x + 4, icon_y + 3, icon_x + 2, icon_y + 6, 10)
        pset(icon_x + 5, icon_y + 2, 10)
        pset(icon_x, icon_y + 4, 10)
        
      elseif powerup_options[i].name == "air jump" then
        -- double jump icon (two boots stacked)
        rectfill(icon_x + 1, icon_y - 1, icon_x + 4, icon_y + 1, 11) -- top boot
        rectfill(icon_x + 2, icon_y + 2, icon_x + 5, icon_y + 4, 12) -- bottom boot
        
      elseif powerup_options[i].name == "big sword" then
        -- sword icon
        line(icon_x + 3, icon_y, icon_x + 3, icon_y + 4, 6) -- blade
        line(icon_x + 2, icon_y + 5, icon_x + 4, icon_y + 5, 4) -- guard
        line(icon_x + 3, icon_y + 6, icon_x + 3, icon_y + 7, 9) -- handle
        
      elseif powerup_options[i].name == "sky slice" then
        -- overhead slice icon (arc above)
        circfill(icon_x + 3, icon_y + 4, 3, 0) -- black circle
        circfill(icon_x + 3, icon_y + 4, 2, 10) -- yellow inner
        -- arc above
        for a = 0.25, 0.75, 0.1 do
          local px = icon_x + 3 + cos(a) * 4
          local py = icon_y + 4 + sin(a) * 4
          pset(px, py, 10)
        end
        
      elseif powerup_options[i].name == "armor" then
        -- shield icon
        rectfill(icon_x + 2, icon_y + 1, icon_x + 5, icon_y + 5, 6) -- shield body
        pset(icon_x + 3, icon_y, 6) -- shield point
        pset(icon_x + 4, icon_y, 6)
        line(icon_x + 3, icon_y + 2, icon_x + 4, icon_y + 4, 7) -- shield pattern
        
      elseif powerup_options[i].name == "phantom" then
        -- phantom icon (ghostly outline)
        rect(icon_x + 1, icon_y + 1, icon_x + 3, icon_y + 4, 12) -- left phantom
        rect(icon_x + 4, icon_y + 1, icon_x + 6, icon_y + 4, 12) -- right phantom
        rectfill(icon_x + 2, icon_y + 2, icon_x + 4, icon_y + 4, 7) -- main player
      elseif powerup_options[i].name == "vampire" then
        -- phantom icon (ghostly outline)
        rect(icon_x + 1, icon_y + 1, icon_x + 3, icon_y + 4, 12) -- left phantom
        rect(icon_x + 4, icon_y + 1, icon_x + 6, icon_y + 4, 12) -- right phantom
        rectfill(icon_x + 2, icon_y + 2, icon_x + 4, icon_y + 4, 7) -- main player
      end
      -- powerup name (centered)
      local name = powerup_options[i].name
      local name_x = rect_x + rect_w/2 - #name * 2
      print(name, name_x, rect_y + 20, 7)
      
      -- powerup effect (centered, smaller text)
      local effect = powerup_options[i].effect
      local effect_x = rect_x + rect_w/2 - #effect * 2
      print(effect, effect_x, rect_y + 28, 6)
      
      -- rarity indicator
      local rarity_color = powerup_options[i].rarity == "rare" and 14 or 7
      print(powerup_options[i].rarity, rect_x + 2, rect_y + 2, rarity_color)
    end
    
    print("use ←→ to select, ❎/z to confirm", 16, 92, 6)
  end
  
  -- draw level up animation
  if levelup_active then
    -- animated scale effect
    local scale = 1 + sin(levelup_timer / 15) * 0.3
    local text = "level " .. level .. "!"
    local text_x = 64 - #text * 2
    local text_y = 50
    
    -- draw background box
    local box_size = #text * 4 + 8
    rectfill(64 - box_size/2, text_y - 4, 
             64 + box_size/2, text_y + 10, 0)
    rect(64 - box_size/2, text_y - 4, 
         64 + box_size/2, text_y + 10, 7)
    
    -- animated text color
    local text_color = 7
    if levelup_timer % 10 < 5 then
      text_color = 10 -- yellow flash
    end
    
    print(text, text_x, text_y, text_color)
  end
end

function add_platform()
  -- difficulty scaling based on level
  local min_width = max(15, 35 - level * 3) -- platforms get narrower
  local max_width = max(20, 50 - level * 2)
  local base_spacing = 25 + level * 2 -- platforms get further apart
  local spacing_variance = 5 + level * 3 -- more random spacing variance
  
  local platform = {
    x = flr(rnd(128 - max_width)) + 5, -- random x position
    y = next_platform_y,
    w = flr(rnd(max_width - min_width)) + min_width -- level-based width
  }
  
  add(platforms, platform)
  next_platform_y -= base_spacing + flr(rnd(spacing_variance))
end

function add_enemy()
  -- more enemies at higher levels
  local enemy_chance = 0.6 + level * 0.15 -- 60% base, +15% per level (was 30% + 10%)
  
  if rnd(1) < enemy_chance then
    local enemy = {
      x = flr(rnd(118)) + 5, -- random x position
      y = next_enemy_y + flr(rnd(20)) - 10, -- slight y variance
      w = 5,
      h = 5,
      bob_timer = rnd(1) -- random starting phase for bobbing
    }
    
    add(enemies, enemy)
  end
  
  -- space out enemy generation
  next_enemy_y -= enemy_spacing + flr(rnd(40))
end

function shuffle(t)
  for i = #t, 2, -1 do
      local j = flr(rnd(i))
      t[i], t[j] = t[j], t[i]
  end
end


function generate_powerup_options()
  powerup_options = {}
  
  -- all possible powerups with their rarity
  local common_powers = {
    -- Common powerups
    {name = "apple", effect = "+1 maxhp"},
    {name = "jump boot", effect = "jump higher"},
    {name = "coffee", effect = "move faster"},
    {name = "big sword", effect = "+20% sword"},
    {name = "armor", effect = "+20% invuln"},
  }
  local rare_powers = {
    -- Rare powerups
    {name = "air jump", effect = "+1 max jump"},
    {name = "sky slice", effect = "overhead cut"},
    {name = "phantom", effect = "ghost ally"},
    {name = "vampire", effect = "chance to heal"}
  }
  
  -- rarity weights
  local rare_weight = 10   -- 10% chance for rare
  local has_rare = false

  shuffle(common_powers)
  shuffle(rare_powers)
  -- local common_len = #common_powers
  -- local rare_len = #rare_powers
  -- generate 3 options
  for i = 1, 3 do
    local selected_powerup
    
    -- determine rarity for this slot
    -- only one rare per set
    local is_rare = rnd(100) < rare_weight and not has_rare
    if is_rare then
      has_rare = true
    end
    if is_rare then
      selected_powerup = rare_powers[#rare_powers-i+1] or rare_powers[1]
      selected_powerup.rarity = 'rare'
    else
      selected_powerup = common_powers[#common_powers-i+1] or common_powers[1]
      selected_powerup.rarity = 'common'
    end
    
    add(powerup_options, selected_powerup)
  end
end

function apply_powerup(powerup)
  if powerup.name == "apple" then
    player.max_hearts += 1
    player.hearts += 1
    
  elseif powerup.name == "jump boot" then
    player.jump_speed = player.jump_speed + player.jump_speed * .2
    
  elseif powerup.name == "speed" then
    player.speed = player.speed + player.speed * .2
    
  elseif powerup.name == "air jump" then
    player.max_jumps += 1
    player.jumps_left = player.max_jumps -- refresh jumps
    
  elseif powerup.name == "big sword" then
    player.sword_size_mult += 0.2
    
  elseif powerup.name == "sky slice" then
    player.overhead_slices += 1
    
  elseif powerup.name == "armor" then
    player.invuln_mult += 0.2
    
  elseif powerup.name == "phantom" then
    -- add a phantom player
    local offset_x = player.next_phantom_side * (15 + #player.phantoms * 5)
    
    local phantom = {
      x = player.x + offset_x,
      y = player.y,
      offset_x = offset_x
    }
    
    add(player.phantoms, phantom)
    
    -- alternate sides for next phantom
    player.next_phantom_side *= -1
elseif powerup.name == "vampire" then
  player.vampire_chance += .10
end
end
__gfx__
00000000777776666666655500000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000777776666666655500000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00700700777776666666655500000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00077000777776666666666600000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00077000777777666666666600000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00700700777776666666666600000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000777777666666666600000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000777777766666666600000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000777777776666666600000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000777777776666666600000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000777777777666666600000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000777777777776666600000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000077777777777666600000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000007777777777766600000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000777777777766600000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000077777770000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
__sfx__
0006000000000000000000000000000001b05000000000000000018050000000000030350000001f05000000000000000014050120501105012050190501b0500000000000000000000000000000000000000000
d7100000103200e330133300c330103300e330113300e330133300e33015330113300000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
011900001c9771c97718b551ab0510b740cb641c9771c9662eb0730b771c9771c9771c97716000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
011000000c043053532461505353053530c04324615053530c0430000024615000000c0000c04324615246000c0430000024615000000c0000c04324615246000c0430000024615000000c0000c0432461524600
__music__
00 01424344

