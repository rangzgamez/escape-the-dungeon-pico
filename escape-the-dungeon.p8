pico-8 cartridge // http://www.pico-8.com
version 42
__lua__
-- ENDLESS VERTICAL JUMPER - REFACTORED
-- Cleaner structure with separated concerns

-- GAME STATE MANAGEMENT
game_state = "playing" -- playing, powerup_selection, gameover

-- CORE GAME DATA
function _init()
  init_player()
  init_world()
  init_camera()
  init_effects()
end

function init_world()
  level = 1
  prev_level = 1
  score = 0
  highest_y = player.y
  
  platforms = {}
  next_platform_y = 80
  platform_spacing = 25
  
  enemies = {}
  next_enemy_y = 60
  enemy_spacing = 30 -- reduced spacing for more frequent individual enemies
  

  
  -- initial platform
  add(platforms, {x = 0, y = 110, w = 128})
  for i = 1, 20 do add_platform() end
  
  -- pre-spawn enemies ahead for radar to detect
  for i = 1, 10 do add_enemy() end -- spawn 10 initial enemies ahead

  -- tutorial messages
  tutorial_messages = {
    {y = platforms[1].y - 10, text = "🅾️ to jump!"},
    {y = enemies[1].y - 10, text = "jump again to attack!"},
    {y = enemies[2].y - 10, text = "hit enemy, jump again!"}
  }
end

function init_camera()
  camera_y = 0
  camera_sp = 0
  camera_follow_y = 60
end

function init_effects()
  freeze_timer = 0
  shake_timer = 0
  shake_intensity = 0
  combo_end_timer = 0
  levelup_timer = 0
  levelup_active = false
  powerup_cursor = 1
  powerup_options = {}
  powerup_slide_timer = 0
  powerup_slide_duration = 30 -- frames to slide in
  powerup_fully_visible = false
  
  -- gameover state variables
  gameover_cursor = 1
  gameover_slide_timer = 0
  gameover_slide_duration = 30
  gameover_fully_visible = false
  final_score = 0
  
  -- simple input delay to prevent button bleed
  startup_delay = 6 -- frames to block input after restart
  
  -- spike chase system
  spikes_active = false
  spikes_grow_timer = 0
  spikes_grow_duration = 12 -- frames to grow
  spikes_y = 110 -- starts at initial platform
  spike_height = 0 -- current height during grow animation
  max_spike_height = 8 -- full spike height
end

-- MAIN UPDATE LOOP
function _update()
  update_effects()
  
  if freeze_timer > 0 then return end
  
  if game_state == "playing" then
    update_playing()
  elseif game_state == "powerup_selection" then
    update_powerup_selection()
  elseif game_state == "gameover" then
    update_gameover()
  end
end

function update_effects()
  if startup_delay > 0 then startup_delay -= 1 end
  if freeze_timer > 0 then freeze_timer -= 1 end
  if shake_timer > 0 then
    shake_timer -= 1
    shake_intensity *= 0.9
  end
  if combo_end_timer > 0 then combo_end_timer -= 1 end
  if item_cooldown > 0 then item_cooldown -= 1 end
  
  -- level up animations (continue even during pause)
  if levelup_active then
    levelup_timer -= 1
    if levelup_timer <= 0 then levelup_active = false end
  end
end

function update_playing()
  handle_input()
  update_player_physics()
  update_player_state()
  update_enemies()
  update_camera()
  update_spikes()
  update_world_generation()
  check_collisions()
  update_score_and_level()
  check_game_over()
end

function update_powerup_selection()
  -- Update slide animation
  if powerup_slide_timer < powerup_slide_duration then
    powerup_slide_timer += 1
    if powerup_slide_timer >= powerup_slide_duration then
      powerup_fully_visible = true
    end
    return -- don't allow input during slide
  end
  
  -- Only allow input once fully visible
  if powerup_fully_visible then
    if btnp(0) and powerup_cursor > 1 then powerup_cursor -= 1 end
    if btnp(1) and powerup_cursor < 3 then powerup_cursor += 1 end
    
    if btnp(4) or btnp(5) then
      apply_powerup(powerup_options[powerup_cursor])
      game_state = "playing"
      powerup_fully_visible = false
      powerup_slide_timer = 0
      refresh_jumps()
    end
  end
end

function update_gameover()
  -- Update slide animation
  if gameover_slide_timer < gameover_slide_duration then
    gameover_slide_timer += 1
    if gameover_slide_timer >= gameover_slide_duration then
      gameover_fully_visible = true
    end
    return -- don't allow input during slide
  end
  
  -- Only allow input once fully visible
  if gameover_fully_visible then
    if btnp(2) and gameover_cursor > 1 then gameover_cursor -= 1 end
    if btnp(3) and gameover_cursor < 2 then gameover_cursor += 1 end
    
    if btnp(4) or btnp(5) then
      if gameover_cursor == 1 then
        -- retry
        _init()
        game_state = "playing"
      else
        -- quit - for now just restart, but could add title screen later
        _init()
        game_state = "playing"
      end
    end
  end
end

-- INPUT HANDLING
function handle_input()
  -- block input for a few frames after restart to prevent button bleed
  if startup_delay > 0 then return end
  
  -- movement
  if btn(0) then player.dx -= speed end
  if btn(1) then player.dx += speed end
  
  -- item usage
  if btnp(5) then use_item() end
  
  -- jump handling
  handle_jump_input()
end

function handle_jump_input()
  local jump_btn_currently_held = btn(4)
  
  if jump_btn_currently_held then
    if not jump_held then
      jump()
      jump_held = true
      jump_released = false
    end
  else
    if jump_held then
      jump_released = true
      jump_held = false
    end
  end
  
  -- variable jump height
  if jump_released and player.dy < 0 and player.dy < jump_speed * 0.5 then
    player.dy *= 0.5
    jump_released = false
  end
end

-- PLAYER SYSTEMS
function update_player_physics()
  -- apex boost
  if not grounded and not apex_boost_used and 
     player.dy > -0.5 and player.dy < 0.5 then
    
    local boost_strength = 0.8
    local direction_held = false
    
    if btn(0) then player.dx -= boost_strength; direction_held = true end
    if btn(1) then player.dx += boost_strength; direction_held = true end
    
    if direction_held then apex_boost_used = true end
  end
  
  -- coyote timer
  if not grounded then
    coyote_timer -= 1
    coyote_timer = max(0, coyote_timer)
  end
  
  -- physics
  player.dx *= 0.8
  player.dy += 0.2
  if player.dy > 4 then player.dy = 4 end
  
  -- movement
  player.x += player.dx
  player.y += player.dy
  
  -- wrap around
  if player.x < 0 then player.x = 128 end
  if player.x > 128 then player.x = 0 end
  
  -- update phantoms
  for phantom in all(phantoms) do
    phantom.x = player.x + phantom.offset_x
    phantom.y = player.y
  end
end

function update_player_state()
  if invuln_timer > 0 then invuln_timer -= 1 end
  
  if attack_timer > 0 then
    attack_timer -= 1
    if attack_timer <= 0 then attacking = false end
  end
  
  -- update hyper beam
  if hyper_beam_active then
    hyper_beam_timer -= 1
    if hyper_beam_timer <= 0 then
      hyper_beam_active = false
    else
      -- check hyper beam collisions every frame while active
      check_hyper_beam_collisions()
    end
  end
end

function jump()
  local can_jump = grounded or coyote_timer > 0 or jumps_left > 0
  if not can_jump then return end
  
  if not grounded and coyote_timer > 0 then
    coyote_timer = 0
  elseif not grounded then
    jumps_left -= 1
    attack()
  end
  
  player.dy = jump_speed
  jump_held = true
  jump_released = false
  apex_boost_used = false
end

function refresh_jumps()
  jumps_left = max_jumps
end

--TODO
-- refactor to generalize for all items w duration
function fire_hyper_beam()
  hyper_beam_active = true
  hyper_beam_timer = 300 -- 5 seconds at 60fps
end

-- COMBAT SYSTEM
function attack()
  attacking = true
  attack_timer = 10
  
  calc_attack(player)

  
  -- phantom attacks
  for phantom in all(phantoms) do
    calc_attack(phantom)
  end
end

function calc_attack(entity)
  local attack_x = entity.x - (attack_w - player.w) / 2
  local attack_y = entity.y + player.h - 2
  
  check_attack_collision(attack_x, attack_y, attack_w, attack_h)
  
  -- overhead slice
  if overhead_slices > 0 then
    local slice_w = 8 + overhead_slices * 4
    local slice_h = 6 + overhead_slices * 2
    local slice_x = entity.x - (slice_w - player.w) / 2
    local slice_y = entity.y - slice_h - 2
    check_attack_collision(slice_x, slice_y, slice_w, slice_h)
  end
end

function check_attack_collision(attack_x, attack_y, attack_w, attack_h)
  for enemy in all(enemies) do
    if not enemy.dead and 
       enemy.x + enemy.w > attack_x and enemy.x < attack_x + attack_w and
       enemy.y + enemy.h > attack_y and enemy.y < attack_y + attack_h then
        
      -- combo and scoring
      combo += 1
      local multiplier = get_combo_multiplier()
      xp += flr(5 * multiplier)
      score += flr(10 * multiplier)
      
      -- effects
      freeze_timer = 4
      shake_timer = 6
      shake_intensity = 3
      
      -- check player level up
      if xp >= xp_to_next then
        xp -= xp_to_next
        player_level += 1
        xp_to_next += 5
        
        -- start powerup selection with slide animation
        game_state = "powerup_selection"
        powerup_cursor = 1
        powerup_slide_timer = 0
        powerup_fully_visible = false
        generate_powerup_options()
      end
      
      refresh_jumps()
      
      if rnd(1) < vampire_chance then heal() end
      kill_enemy(enemy)
      break
    end
  end
end

--TODO this should be item collisions
-- actually there should just be generic collision checks
function check_hyper_beam_collisions()
  if not hyper_beam_active then return end
  
  -- laser extends from current player position straight down to bottom of screen
  local beam_center_x = player.x + player.w/2
  local beam_left = beam_center_x - hyper_beam_width/2
  local beam_right = beam_center_x + hyper_beam_width/2
  
  for enemy in all(enemies) do
    if not enemy.dead and
       enemy.x + enemy.w > beam_left and
       enemy.x < beam_right and
       enemy.y > player.y then -- only hit enemies below the player
      
      -- enemy hit by laser!
      kill_enemy(enemy)
    end
  end
end

function kill_enemy(enemy)
  enemy.dead = true
  enemy.dead_timer = 60
  enemy.dead_color = 5
  
  -- fling enemy
  local fling_direction_x = enemy.x < player.x and -1 or 1
  enemy.dx = fling_direction_x * (2 + rnd(2))
  enemy.dy = -1 * (1.5 + rnd(1.5))

end

function get_combo_multiplier()
  if combo >= 50 then return 1.4
  elseif combo >= 20 then return 1.3
  elseif combo >= 10 then return 1.2
  elseif combo >= 5 then return 1.1
  else return 1.0 end
end

function end_combo()
  if combo >= 5 then combo_end_timer = 90 end
  combo = 0
end

function heal() 
  hearts += 1
  if hearts > max_hearts then
    hearts = max_hearts
  end
end

-- ENEMY SYSTEM
function update_enemies()
  for enemy in all(enemies) do
    if enemy.dead then
      update_dead_enemy(enemy)
    else
      update_living_enemy(enemy)
    end
  end
end

function update_dead_enemy(enemy)
  enemy.dead_timer -= 1
  enemy.dx *= 0.95
  enemy.dy += 0.3
  enemy.x += enemy.dx
  enemy.y += enemy.dy
  
  if enemy.dead_timer <= 0 or 
     enemy.x < -10 or enemy.x > 138 or 
     enemy.y > camera_y + 160 then
    del(enemies, enemy)
  end
end

function update_living_enemy(enemy)
  enemy.bob_timer += 0.1
  enemy.x += sin(enemy.bob_timer) * 0.3
  enemy.y += cos(enemy.bob_timer * 1.5) * 0.2
  enemy.x = mid(5, enemy.x, 123)
end

-- COLLISION DETECTION
function check_collisions()
  check_platform_collisions()
  check_enemy_collisions()
  check_spike_collisions()
end

function check_platform_collisions()
  local was_grounded = grounded
  grounded = false
  
  for platform in all(platforms) do
    if not platform.broken and player.dy > 0 and
       player.y + player.h > platform.y and
       player.y + player.h < platform.y + 8 and
       player.x + player.w > platform.x and
       player.x < platform.x + platform.w then
      
      player.y = platform.y - player.h
      player.dy = 0
      grounded = true
      coyote_timer = 2
      jump_released = false
      apex_boost_used = false
      
      end_combo()
      refresh_jumps()
    end
  end
  
  if was_grounded and not grounded then
    coyote_timer = 2
  end
end

function check_enemy_collisions()
  if invuln_timer > 0 then return end
  
  for enemy in all(enemies) do
    if not enemy.dead and
       player.x + player.w > enemy.x and player.x < enemy.x + enemy.w and
       player.y + player.h > enemy.y and player.y < enemy.y + enemy.h then
      
      -- player hit
      hearts -= 1
      invuln_timer = flr(invuln_time)
      end_combo()
      
      -- knockback
      if player.x < enemy.x then
        player.dx = -1.5
      else
        player.dx = 1.5
      end
      player.dy = -2
      break
    end
  end
end

function check_spike_collisions()
  if not spikes_active or spike_height <= 0 then return end
  
  local spike_top = spikes_y - spike_height
  
  -- check player collision
  if player.y + player.h > spike_top and player.y + player.h < spikes_y + 8 then
    -- instant death from spikes!
    hearts = 0
  end
  
  -- check enemy collisions
  for enemy in all(enemies) do
    if not enemy.dead and 
       enemy.y + enemy.h > spike_top and enemy.y + enemy.h < spikes_y + 8 then
      -- enemy killed by spikes!
      kill_enemy(enemy)
    end
  end
  
  -- check platform collisions
  for platform in all(platforms) do
    if not platform.broken and 
       platform.y + 8 > spike_top and platform.y < spikes_y + 8 then
      -- platform destroyed by spikes!
      break_platform(platform)
    end
  end
end


-- CAMERA SYSTEM
function update_camera()
  local target_camera_y = player.y - camera_follow_y
  if target_camera_y < camera_y and player.dy < 0 and camera_sp > player.dy then
    camera_y = camera_y + (target_camera_y - camera_y) * 0.1
    if camera_sp == 0 then
      camera_sp = -0.3
      -- activate spikes when camera starts auto-scrolling!
      activate_spikes()
    end
  else
    camera_y += camera_sp
  end
end

function activate_spikes()
  if not spikes_active then
    spikes_active = true
    spikes_grow_timer = spikes_grow_duration
    
    -- dramatic screen shake to signal danger
    shake_timer = 20
    shake_intensity = 4
  end
end

function update_spikes()
  if not spikes_active then return end
  
  -- grow animation
  if spikes_grow_timer > 0 then
    spikes_grow_timer -= 1
    spike_height = max_spike_height * (1 - spikes_grow_timer / spikes_grow_duration)
  else
    spike_height = max_spike_height
  end
  
  -- follow camera at same speed (stay at bottom of screen)
  spikes_y = camera_y + 128 - 8 -- 8px above bottom of screen
end

-- WORLD GENERATION
function update_world_generation()
  while next_platform_y > camera_y - 50 do add_platform() end
  
  -- Generate enemies much further ahead so radar has multiple targets
  while next_enemy_y > camera_y - 200 do add_enemy() end -- increased from -50 to -200
  
  -- cleanup
  for platform in all(platforms) do
    if platform.broken then
      update_broken_platform(platform)
      if platform.break_timer <= 0 then
        del(platforms, platform)
      end
    elseif platform.y > camera_y + 150 then 
      del(platforms, platform) 
    end
  end
  
  for enemy in all(enemies) do
    if not enemy.dead and enemy.y > camera_y + 150 then del(enemies, enemy) end
  end
end

function update_broken_platform(platform)
  platform.break_timer -= 1
  
  -- update falling pieces
  for piece in all(platform.pieces) do
    piece.dy += 0.2 -- gravity
    piece.x += piece.dx
    piece.y += piece.dy
    piece.dx *= 0.98 -- slight air resistance
  end
end

function add_platform()
  local min_width = max(15, 35 - level * 3)
  local max_width = max(20, 50 - level * 2)
  local base_spacing = 25 + level * 2
  local spacing_variance = 5 + level * 3
  
  local platform = {
    x = flr(rnd(128 - max_width)) + 5,
    y = next_platform_y,
    w = flr(rnd(max_width - min_width)) + min_width
  }
  
  add(platforms, platform)
  next_platform_y -= base_spacing + flr(rnd(spacing_variance))
end

function add_enemy()
  local enemy_chance = 0.6 + level * 0.15
  
  if rnd(1) < enemy_chance then
    local enemy = {
      x = flr(rnd(118)) + 5, -- random x position
      y = next_enemy_y + flr(rnd(20)) - 10, -- slight y variance
      w = 5, h = 5,
      bob_timer = rnd(1) -- random starting phase for bobbing
    }
    add(enemies, enemy)
  end
  
  -- space out enemy generation (smaller spacing for more frequent enemies)
  next_enemy_y -= enemy_spacing + flr(rnd(20)) -- reduced variance for more consistent spacing
end

function break_platform(platform)
  platform.broken = true
  platform.break_timer = 30 -- animation duration
  platform.pieces = {}
  
  -- create falling pieces
  local piece_count = flr(platform.w / 8) + 2
  for i = 1, piece_count do
    local piece = {
      x = platform.x + (i - 1) * (platform.w / piece_count) + rnd(4) - 2,
      y = platform.y + rnd(2),
      w = 4 + rnd(4),
      h = 2 + rnd(4),
      dx = (rnd(2) - 1) * 1.5,
      dy = -rnd(1) - 0.5,
      color = (rnd(1) < 0.5) and 11 or 3 -- mix of platform colors
    }
    add(platform.pieces, piece)
  end
  
  -- screen shake from destruction
  shake_timer = 8
  shake_intensity = 2
end

-- SCORING AND PROGRESSION
function update_score_and_level()
  if player.y < highest_y then
    highest_y = player.y
    score = max(score, flr((100 - highest_y) / 10))
  end
  
  prev_level = level
  level = flr(score / 50) + 1
  
  if level > prev_level then
    levelup_active = true
    levelup_timer = 90
  end
  
  if camera_sp ~= 0 then
    camera_sp = -0.3 - (level - 1) * 0.1
  end
end

function check_game_over()
  if player.y > camera_y + 150 or hearts <= 0 then
    -- transition to gameover instead of immediately restarting
    game_state = "gameover"
    final_score = score
    gameover_cursor = 1
    gameover_slide_timer = 0
    gameover_fully_visible = false
  end
end

-- ITEM SYSTEM
function use_item()
  if not equipped_item or item_cooldown > 0 then return end
  
  equipped_item.func()
  shake_timer = 3
  shake_intensity = 1
  item_cooldown = equipped_item.cooldown
  max_item_cooldown = equipped_item.cooldown
end

-- POWERUP SYSTEM
function shuffle(t)
  for i = #t, 2, -1 do
    local j = flr(rnd(i))
    t[i], t[j] = t[j], t[i]
  end
end

function generate_powerup_options()
  powerup_options = {}
  
  local common_powers = {
    {name = "apple", effect = "+1 maxhp", type = "powerup", spr = 7, func = function ()
      hearts += 1
      max_hearts += 1
    end},
    {name = "jump boot", effect = "jump higher", type = "powerup", spr = 2, func = function () jump_speed *= 1.2 end},
    {name = "coffee", effect = "move faster", type = "powerup", spr = 1, func = function () speed *= 1.2 end},
    {name = "big sword", effect = "+20% sword", type = "powerup", spr = 10, func = function () 
      attack_w *= 1.2
      attack_h *= 1.2
    end},
    {name = "armor", effect = "+20% invuln", type = "powerup", spr = 9, func = function () invuln_time *= 1.2 end},
    {name = "radar", effect = "show upcoming enemies", spr = 3, type = "powerup", func = function () radar_count += 1 end},
  }
  
  local rare_powers = {
    {name = "air jump", effect = "+1 max jump", type = "powerup", spr = 11, func = function () max_jumps += 1 end},
    {name = "sky slice", effect = "overhead cut", type = "powerup", spr = 4, func = function () overhead_slices += 1 end},
    {name = "vampire", effect = "chance to heal", type = "powerup", spr = 0, func = function () vampire_chance += .1 end},
    {name = "phantom", effect = "ghost ally", type = "powerup", spr = 8, func = function () add(phantoms, {x = player.x, y = player.y, offset_x = (15 + #phantoms * 5) * ((#phantoms % 2 * -2) + 1)}) end},
  }
  
  local common_items = {
    {name = "jump potion", effect = "refresh jumps", type = "item", cooldown = 300, func = refresh_jumps, spr = 6},
    {name = "hyper beam", effect = "big laser", type = "item", cooldown = 1200, func = fire_hyper_beam, spr = 5}
  }
  
  local rare_items = {}
  
  -- combine all options
  local all_common = {}
  for item in all(common_powers) do add(all_common, item) end
  for item in all(common_items) do add(all_common, item) end
  
  local all_rare = {}
  for item in all(rare_powers) do add(all_rare, item) end
  for item in all(rare_items) do add(all_rare, item) end
  
  local rare_weight = 10
  local has_rare = false
  
  shuffle(all_common)
  shuffle(all_rare)
  
  for i = 1, 3 do
    local selected_powerup
    local is_rare = rnd(100) < rare_weight and not has_rare and #all_rare > 0
    
    if is_rare then
      has_rare = true
      selected_powerup = all_rare[#all_rare-i+1] or all_rare[1]
      selected_powerup.rarity = 'rare'
    else
      selected_powerup = all_common[#all_common-i+1] or all_common[1]
      selected_powerup.rarity = 'common'
    end
    
    add(powerup_options, selected_powerup)
  end
end

function apply_powerup(powerup)
  if powerup.type == "item" then
    equipped_item = powerup
    item_cooldown = 0
    max_item_cooldown = powerup.cooldown
    return
  end
  powerup.func()
end

-- DRAWING SYSTEM
function _draw()
  cls(1)
  
  local shake_x, shake_y = 0, 0
  if shake_timer > 0 then
    shake_x = (rnd(shake_intensity * 2) - shake_intensity)
    shake_y = (rnd(shake_intensity * 2) - shake_intensity)
  end
  
  camera(shake_x, camera_y + shake_y)
  
  draw_world()
  draw_entities()
  draw_effects()
  
  camera() -- reset for UI
  draw_ui()
  
  if game_state == "powerup_selection" then
    draw_powerup_selection()
  elseif game_state == "gameover" then
    draw_gameover()
  end
end

function draw_world()
  for platform in all(platforms) do
    if platform.broken then
      draw_broken_platform(platform)
    else
      rectfill(platform.x, platform.y, platform.x + platform.w - 1, platform.y + 3, 11)
      rectfill(platform.x, platform.y + 4, platform.x + platform.w - 1, platform.y + 7, 3)
    end
  end
  
  draw_spikes()
end

function draw_broken_platform(platform)
  -- draw falling pieces
  for piece in all(platform.pieces) do
    rectfill(piece.x, piece.y, piece.x + piece.w - 1, piece.y + piece.h - 1, piece.color)
  end
  
  -- optional: draw some dust/debris particles
  if platform.break_timer > 20 then
    for i = 1, 3 do
      local px = platform.x + rnd(platform.w)
      local py = platform.y + rnd(8) - 4
      pset(px, py, 6) -- light brown dust
    end
  end
end

function draw_spikes()
  if not spikes_active or spike_height <= 0 then return end
  
  -- draw the spike platform base
  rectfill(0, spikes_y, 127, spikes_y + 7, 3) -- dark brown base
  
  -- draw triangular spikes growing from the platform
  local spike_spacing = 6 -- distance between spike centers
  local spike_width = 4
  
  for x = 2, 126, spike_spacing do
    local spike_top = spikes_y - spike_height
    local spike_left = x - spike_width / 2
    local spike_right = x + spike_width / 2
    
    -- draw triangular spike (pointing up)
    for y = spike_top, spikes_y do
      local progress = (y - spike_top) / spike_height
      local width = spike_width * progress
      local left = x - width / 2
      local right = x + width / 2
      
      if left <= right then
        line(left, y, right, y, 8) -- red spikes
      end
    end
  end
end

function draw_entities()
  draw_enemies()
  draw_phantoms()
  draw_player()
end

function draw_enemies()
  for enemy in all(enemies) do
    if enemy.dead then
      rectfill(enemy.x, enemy.y, enemy.x + enemy.w - 1, enemy.y + enemy.h - 1, enemy.dead_color)
      pset(enemy.x + 1, enemy.y + 3, 0)
      pset(enemy.x + 3, enemy.y + 3, 0)
      if enemy.dead_timer > 40 then
        pset(enemy.x + 1, enemy.y + 3, 8)
        pset(enemy.x + 3, enemy.y + 3, 8)
        pset(enemy.x + 2, enemy.y + 3, 0)
      end
    else
      rectfill(enemy.x, enemy.y, enemy.x + enemy.w - 1, enemy.y + enemy.h - 1, 8)
      pset(enemy.x + 1, enemy.y + 1, 0)
      pset(enemy.x + 3, enemy.y + 1, 0)
    end
  end
end

function draw_phantoms()
  for phantom in all(phantoms) do
    rect(phantom.x, phantom.y, phantom.x + player.w - 1, phantom.y + player.h - 1, 12)
    pset(phantom.x + 2, phantom.y + 2, 12)
    pset(phantom.x + 4, phantom.y + 2, 12)
  end
end

function draw_player()
  if invuln_timer <= 0 or invuln_timer % 8 < 4 then
    local jump_color_index = min(jumps_left + 1, #jumps_color)
    rectfill(player.x, player.y, player.x + player.w - 1, player.y + player.h - 1, 
             jumps_color[jump_color_index])
    pset(player.x + 2, player.y + 2, 0)
    pset(player.x + 4, player.y + 2, 0)
  end
end

function draw_effects()
  draw_combo()
  draw_combo_celebration()
  draw_attack()
  draw_level_up_world()
  draw_hyper_beam()
  draw_tutorial_messages()
end

function draw_combo()
  if combo >= 5 then
    local combo_text = tostr(combo)
    local text_x = player.x + player.w/2 - #combo_text * 2
    local text_y = player.y - 8
    
    rectfill(text_x - 2, text_y - 1, text_x + #combo_text * 4, text_y + 5, 0)
    
    local combo_color = 7
    if combo >= 50 then combo_color = 14
    elseif combo >= 20 then combo_color = 10
    elseif combo >= 10 then combo_color = 9
    elseif combo >= 5 then combo_color = 11 end
    
    print(combo_text, text_x, text_y, combo_color)
  end
end

function draw_combo_celebration()
  if combo_end_timer > 0 then
    local text = "nice!!"
    local text_x = player.x + player.w/2 - #text * 2
    local text_y = player.y - 18
    
    local base_colors = {10, 9, 8, 12, 11, 14}
    
    for i = 1, #text do
      local char = sub(text, i, i)
      local char_x = text_x + (i - 1) * 4
      local char_y = text_y + sin(time() * 8 + i * 0.8) * 2
      local color = base_colors[((flr(time() * 6) + i - 1) % #base_colors) + 1]
      print(char, char_x, char_y, color)
    end
  end
end


--TODO
--create table of attacks, and use table references for collisions and drawing
function draw_attack()
  if attacking and attack_timer > 7 then
    local attack_x = player.x - (attack_w - player.w) / 2
    local attack_y = player.y + player.h - 2
    
    rect(attack_x, attack_y, attack_x + attack_w - 1, attack_y + attack_h - 1, 9)
    
    if overhead_slices > 0 then
      local slice_w = 8 + overhead_slices * 4
      local slice_h = 6 + overhead_slices * 2
      local slice_x = player.x - (slice_w - player.w) / 2
      local slice_y = player.y - slice_h - 2
      rect(slice_x, slice_y, slice_x + slice_w - 1, slice_y + slice_h - 1, 10)
    end
    
    for phantom in all(phantoms) do
      local phantom_attack_x = phantom.x - (attack_w - player.w) / 2
      local phantom_attack_y = phantom.y + player.h - 2
      rect(phantom_attack_x, phantom_attack_y, 
           phantom_attack_x + attack_w - 1, phantom_attack_y + attack_h - 1, 12)
      
      if overhead_slices > 0 then
        local slice_w = 8 + overhead_slices * 4
        local slice_h = 6 + overhead_slices * 2
        local phantom_slice_x = phantom.x - (slice_w - player.w) / 2
        local phantom_slice_y = phantom.y - slice_h - 2
        rect(phantom_slice_x, phantom_slice_y, 
             phantom_slice_x + slice_w - 1, phantom_slice_y + slice_h - 1, 12)
      end
    end
  end
end

function draw_level_up_world()
  if levelup_active then
    local text = "level " .. level .. "!"
    local progress = (90 - levelup_timer) / 90
    local text_x = 128 + 10 - progress * (128 + 10 + #text * 4)
    local text_y = 60
    
    local base_colors = {10, 9, 8, 12, 11, 14}
    
    for i = 1, #text do
      local char = sub(text, i, i)
      local char_x = text_x + (i - 1) * 4
      local char_y = text_y + sin(time() * 6 + i * 0.5) * 1
      local color = base_colors[((flr(time() * 4) + i - 1) % #base_colors) + 1]
      print(char, char_x, char_y, color)
    end
  end
end

function draw_hyper_beam()
  if not hyper_beam_active then return end
  
  local beam_center_x = player.x + player.w/2 -- use current player position
  local beam_top_y = player.y + player.h
  local beam_bottom_y = camera_y + 128 -- extend to bottom of visible screen
  
  -- crackling border colors that cycle
  local border_colors = {12, 8, 10} -- light blue, red, yellow
  local border_color = border_colors[flr(time() * 10) % 3 + 1]
  
  -- draw the beam from player position downward
  for beam_width = hyper_beam_width, 1, -1 do
    local color = 7 -- white center
    if beam_width > 4 then
      color = border_color -- crackling border
    elseif beam_width > 2 then
      color = 6 -- light gray
    end
    
    -- draw vertical lines for the beam
    for x_offset = -beam_width/2, beam_width/2 do
      line(beam_center_x + x_offset, beam_top_y, 
           beam_center_x + x_offset, beam_bottom_y, color)
    end
  end
  
  -- add some crackling effects around the edges
  for i = 1, 5 do
    local crackle_x = beam_center_x + (rnd(hyper_beam_width) - hyper_beam_width/2)
    local crackle_y = beam_top_y + rnd(beam_bottom_y - beam_top_y)
    pset(crackle_x, crackle_y, border_color)
  end
end

function draw_tutorial_messages()
  -- only show tutorial messages in early game
  if level > 3 then return end
  
  for message in all(tutorial_messages) do
    -- only draw messages that are near the visible screen
    if message.y > camera_y - 20 and message.y < camera_y + 150 then
      -- center the text horizontally
      local text_x = 64 - #message.text * 2
      print(message.text, text_x, message.y, 5) -- grey color
    end
  end
end

function draw_ui()
  print("score: " .. score, 2, 2, 7)
  print("level: " .. level, 2, 10, 7)
  print("plv: " .. player_level, 2, 18, 7)
  print("xp: " .. xp .. "/" .. xp_to_next, 2, 26, 7)
  
  for i = 1, max_hearts do
    local heart_x = 2 + (i - 1) * 8
    print("♥", heart_x, 34, i <= hearts and 8 or 5)
  end
  
  if equipped_item then
    draw_equipped_item()
  end
  
  -- Draw radar indicators (UI elements, not world objects)
  draw_radar_indicators()
end

function draw_equipped_item()
  local item_x = 128 - 18
  local item_y = 128 - 20
  print("❎",item_x+4,item_y - 7, 8);
  rectfill(item_x, item_y, item_x + 14, item_y + 14, 0)
  rect(item_x, item_y, item_x + 14, item_y + 14, 7)
    
  spr(equipped_item.spr, item_x + 4, item_y + 4)

  if item_cooldown > 0 then
    local cooldown_seconds = flr(item_cooldown / 60) + 1
    print(tostr(cooldown_seconds) .. "s", item_x + 2, item_y + 18, 8)
    local bar_width = 26
    local progress = (max_item_cooldown - item_cooldown) / max_item_cooldown
    rectfill(item_x + 2, item_y + 16, item_x + 2 + bar_width * progress, item_y + 16, 11)
  end
end

function draw_radar_indicators()
  if radar_count <= 0 then return end
  
  -- Find enemies above the visible screen
  local upcoming_enemies = {}
  local screen_top = camera_y - 10 -- enemies above the screen top
  
  for enemy in all(enemies) do
    if not enemy.dead and enemy.y < screen_top then
      add(upcoming_enemies, enemy)
    end
  end
  
  -- Sort by Y position (closest to screen first = highest Y values first)
  for i = 1, #upcoming_enemies - 1 do
    for j = i + 1, #upcoming_enemies do
      if upcoming_enemies[i].y < upcoming_enemies[j].y then
        local temp = upcoming_enemies[i]
        upcoming_enemies[i] = upcoming_enemies[j]
        upcoming_enemies[j] = temp
      end
    end
  end
  
  -- Draw indicators for the first radar_count enemies
  for i = 1, min(radar_count, #upcoming_enemies) do
    local enemy = upcoming_enemies[i]
    local indicator_x = enemy.x + enemy.w/2
    local indicator_y = 2
    
    if i == 1 then
      -- Closest enemy: red triangle (arrow pointing down)
      pset(indicator_x, indicator_y, 8) -- red tip
      pset(indicator_x - 1, indicator_y + 1, 8) -- red left
      pset(indicator_x + 1, indicator_y + 1, 8) -- red right
      pset(indicator_x, indicator_y + 1, 8) -- red center
    else
      -- Other enemies: smaller yellow dots
      pset(indicator_x, indicator_y, 10) -- yellow dot
    end
  end
end

function draw_powerup_selection()
  -- Calculate slide animation offset
  local slide_progress = powerup_slide_timer / powerup_slide_duration
  slide_progress = min(slide_progress, 1) -- clamp to 1
  
  -- Ease-out animation (starts fast, slows down)
  slide_progress = 1 - (1 - slide_progress) * (1 - slide_progress)
  
  local slide_offset = -128 + slide_progress * 128 -- starts at -128 (off-screen left), ends at 0
  
  -- Background (slides in too)
  rectfill(slide_offset, 20, slide_offset + 128, 108, 0)
  
  -- Title
  print("level up!", slide_offset + 46, 26, 10)
  
  -- Draw the 3 powerup option boxes (just icons now)
  for i = 1, 3 do
    local rect_x = slide_offset + 16 + (i - 1) * 32
    local rect_y = 35
    local rect_w = 30
    local rect_h = 30
    
    local bg_color = 1
    local border_color = 7
    
    if powerup_options[i].rarity == "rare" then
      bg_color = 2
      border_color = 14
    end
    
    if i == powerup_cursor and powerup_fully_visible then
      bg_color = 5
      border_color = powerup_options[i].rarity == "rare" and 10 or 11
      if sin(time() * 4) > 0 then border_color = 10 end
    end
    
    rectfill(rect_x, rect_y, rect_x + rect_w, rect_y + rect_h, bg_color)
    rect(rect_x, rect_y, rect_x + rect_w, rect_y + rect_h, border_color)
    
    -- Draw icon centered in box
    spr(powerup_options[i].spr,rect_x + rect_w/2 - 4, rect_y + rect_h/2 - 4)

    -- Small rarity indicator in corner
    local rarity_color = powerup_options[i].rarity == "rare" and 14 or 7
    print(sub(powerup_options[i].rarity, 1, 1), rect_x + 2, rect_y + 2, rarity_color)
  end
  
  -- Only show details and instructions when fully visible
  if powerup_fully_visible then
    -- Draw details for selected powerup below the options
    local selected = powerup_options[powerup_cursor]
    local details_y = 75
    
    -- Name (centered)
    local name_x = slide_offset + 64 - #selected.name * 2
    print(selected.name, name_x, details_y, 7)
    
    -- Type (centered, smaller)
    local type_text = "(" .. selected.type .. ")"
    local type_x = slide_offset + 64 - #type_text * 2
    print(type_text, type_x, details_y + 8, 6)
    
    -- Effect/Description (centered)
    local effect_x = slide_offset + 64 - #selected.effect * 2
    print(selected.effect, effect_x, details_y + 16, 11)
    
    -- Rarity (centered)
    local rarity_text = selected.rarity
    local rarity_x = slide_offset + 64 - #rarity_text * 2
    local rarity_color = selected.rarity == "rare" and 14 or 7
    print(rarity_text, rarity_x, details_y + 24, rarity_color)
    
  end
end

function draw_gameover()
  -- Calculate slide animation offset
  local slide_progress = gameover_slide_timer / gameover_slide_duration
  slide_progress = min(slide_progress, 1) -- clamp to 1
  
  -- Ease-out animation (starts fast, slows down)
  slide_progress = 1 - (1 - slide_progress) * (1 - slide_progress)
  
  local slide_offset = -128 + slide_progress * 128 -- starts at -128 (off-screen left), ends at 0
  
  -- Background (slides in too)
  rectfill(slide_offset, 30, slide_offset + 128, 98, 0)
  rect(slide_offset, 30, slide_offset + 127, 98, 8)
  
  -- Title
  print("you died...", slide_offset + 42, 40, 8)
  
  -- Final score
  local score_text = "final score: " .. final_score
  local score_x = slide_offset + 64 - #score_text * 2
  print(score_text, score_x, 52, 7)
  
  -- Menu options
  local retry_color = gameover_cursor == 1 and 11 or 6
  local quit_color = gameover_cursor == 2 and 11 or 6
  
  -- Only show options and cursor when fully visible
  if gameover_fully_visible then
    -- cursor indicator
    local cursor_x = slide_offset + 35
    local cursor_y = gameover_cursor == 1 and 66 or 78
    print("*", cursor_x, cursor_y, 10)
    
    print("retry", slide_offset + 44, 66, retry_color)
    print("quit", slide_offset + 46, 78, quit_color)
    
  end
end

-->8
--player and stats
function init_player()
  player = {
    x = 64, y = 100, w = 6, h = 6,
    dx = 0, dy = 0,
    
  }
  jump_speed = -3.5
  grounded = false
  speed = 0.5
  jumps_left = 1
  max_jumps = 1
  hearts = 3 
  max_hearts = 3
  invuln_timer = 0
  invuln_time = 60
  invuln_mult = 1.0
  attack_timer = 0
  attacking = false
  attack_w = 12
  attack_h = 12
  overhead_slices = 0
  xp = 0
  player_level = 1
  xp_to_next = 10
  speed_mult = 1.0
  jump_mult = 1.0
  jumps_color = {5, 8, 10}
  coyote_timer = 0
  jump_held = false
  jump_released = false
  apex_boost_used = false
  phantoms = {}
  vampire_chance = 0
  combo = 0
  combo_display_timer = 0
  equipped_item = nil
  item_cooldown = 0
  max_item_cooldown = 0
  radar_count = 0
  hyper_beam_active = false
  hyper_beam_timer = 0
  hyper_beam_width = 8 -- width of the laser beam
end
__gfx__
0000000006006000000111000333333007767770a8c77a8a00242000033000000077770000000000000440006677000000000000000000000000000000000000
000000000060060000cccc103abbb8337706607708c7ac8000244000000400000775757006000006004444007767777000000000000000000000000000000000
700000070077600000022c103ba333b37006600708c77c8000242400028488000775757005665665000760007677777000000000000000000000000000000000
0777777007444700000ccc103b3a33b3700660070aca7c8a00244400288877800757777005665665000760300766770000000000000000000000000000000000
070000700677766000022c103b3333b300066000a8c7aca0007cc000288887800775557000555550000763330777770000000000000000000000000000000000
080000800666660606cccc103b8333b30044420008c77c8007cccc00288888800777777700665660000760300066777700000000000000000000000000000000
0000000006666660cccccc1033bbbb33000420000ac77c8007cccc00028888207777770700655560000760000077677700000000000000000000000000000000
0800008000666000777771100333333000042000a8a77c8a007cc000002222007777770006500056000070000007777000000000000000000000000000000000
__sfx__
0006000000000000000000000000000001b05000000000000000018050000000000030350000001f05000000000000000014050120501105012050190501b0500000000000000000000000000000000000000000
d7100000103200e330133300c330103300e330113300e330133300e33015330113300000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
011900001c9771c97718b551ab0510b740cb641c9771c9662eb0730b771c9771c9771c97716000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
011000000c043000000000000000246150000000000000000c043000000000000000246150000000000000000c043000000000000000246150000000000000000c04300000000000000024615000000000000000
__music__
00 01424344

