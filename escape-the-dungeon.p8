pico-8 cartridge // http://www.pico-8.com
version 42
__lua__
-- ENDLESS VERTICAL JUMPER - REFACTORED
-- Cleaner structure with separated concerns

-- GAME STATE MANAGEMENT
game_state = "playing" -- playing, powerup_selection, player_levelup

-- CORE GAME DATA
function _init()
  init_player()
  init_world()
  init_camera()
  init_effects()
end

function init_player()
  player = {
    x = 64, y = 100, w = 6, h = 6,
    dx = 0, dy = 0,
    jump_speed = -3.5, grounded = false, speed = 0.5,
    jumps_left = 1, max_jumps = 1,
    hearts = 3, max_hearts = 3,
    invuln_timer = 0, base_invuln_time = 60, invuln_mult = 1.0,
    attack_timer = 0, attacking = false, sword_size_mult = 1.0,
    overhead_slices = 0, xp = 0, player_level = 1, xp_to_next = 10,
    speed_mult = 1.0, jump_mult = 1.0,
    jumps_color = {5, 8, 10},
    coyote_timer = 0, jump_held = false, jump_released = false, apex_boost_used = false,
    phantoms = {}, next_phantom_side = 1, vampire_chance = 0,
    combo = 0, combo_display_timer = 0,
    equipped_item = nil, item_cooldown = 0, max_item_cooldown = 0,
    radar_count = 0,
    hyper_beam_active = false,
    hyper_beam_timer = 0,
    hyper_beam_width = 8 -- width of the laser beam
  }
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
end

-- MAIN UPDATE LOOP
function _update()
  update_effects()
  
  if freeze_timer > 0 then return end
  
  if game_state == "playing" then
    update_playing()
  elseif game_state == "powerup_selection" then
    update_powerup_selection()
  end
end

function update_effects()
  if freeze_timer > 0 then freeze_timer -= 1 end
  if shake_timer > 0 then
    shake_timer -= 1
    shake_intensity *= 0.9
  end
  if combo_end_timer > 0 then combo_end_timer -= 1 end
  if player.item_cooldown > 0 then player.item_cooldown -= 1 end
  
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

-- INPUT HANDLING
function handle_input()
  -- movement
  if btn(0) then player.dx -= player.speed end
  if btn(1) then player.dx += player.speed end
  
  -- item usage
  if btnp(5) then use_item() end
  
  -- jump handling
  handle_jump_input()
end

function handle_jump_input()
  local jump_btn_currently_held = btn(4)
  
  if jump_btn_currently_held then
    if not player.jump_held then
      jump()
      player.jump_held = true
      player.jump_released = false
    end
  else
    if player.jump_held then
      player.jump_released = true
      player.jump_held = false
    end
  end
  
  -- variable jump height
  if player.jump_released and player.dy < 0 and player.dy < player.jump_speed * 0.5 then
    player.dy *= 0.5
    player.jump_released = false
  end
end

-- PLAYER SYSTEMS
function update_player_physics()
  -- apex boost
  if not player.grounded and not player.apex_boost_used and 
     player.dy > -0.5 and player.dy < 0.5 then
    
    local boost_strength = 0.8
    local direction_held = false
    
    if btn(0) then player.dx -= boost_strength; direction_held = true end
    if btn(1) then player.dx += boost_strength; direction_held = true end
    
    if direction_held then player.apex_boost_used = true end
  end
  
  -- coyote timer
  if not player.grounded then
    player.coyote_timer -= 1
    player.coyote_timer = max(0, player.coyote_timer)
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
  for phantom in all(player.phantoms) do
    phantom.x = player.x + phantom.offset_x
    phantom.y = player.y
  end
end

function update_player_state()
  if player.invuln_timer > 0 then player.invuln_timer -= 1 end
  
  if player.attack_timer > 0 then
    player.attack_timer -= 1
    if player.attack_timer <= 0 then player.attacking = false end
  end
  
  -- update hyper beam
  if player.hyper_beam_active then
    player.hyper_beam_timer -= 1
    if player.hyper_beam_timer <= 0 then
      player.hyper_beam_active = false
    else
      -- check hyper beam collisions every frame while active
      check_hyper_beam_collisions()
    end
  end
end

function jump()
  local can_jump = player.grounded or player.coyote_timer > 0 or player.jumps_left > 0
  if not can_jump then return end
  
  if not player.grounded and player.coyote_timer > 0 then
    player.coyote_timer = 0
  elseif not player.grounded then
    player.jumps_left -= 1
    attack()
  end
  
  player.dy = player.jump_speed
  player.jump_held = true
  player.jump_released = false
  player.apex_boost_used = false
end

function refresh_jumps()
  player.jumps_left = player.max_jumps
end

function fire_hyper_beam()
  player.hyper_beam_active = true
  player.hyper_beam_timer = 300 -- 5 seconds at 60fps
end

-- COMBAT SYSTEM
function attack()
  player.attacking = true
  player.attack_timer = 10
  
  local base_attack_w = 12
  local base_attack_h = 12
  local attack_w = base_attack_w * player.sword_size_mult
  local attack_h = base_attack_h * player.sword_size_mult
  
  local attack_x = player.x - (attack_w - player.w) / 2
  local attack_y = player.y + player.h - 2
  
  check_attack_collision(attack_x, attack_y, attack_w, attack_h)
  
  -- overhead slice
  if player.overhead_slices > 0 then
    local slice_w = 8 + player.overhead_slices * 4
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
    if not enemy.dead and 
       enemy.x + enemy.w > attack_x and enemy.x < attack_x + attack_w and
       enemy.y + enemy.h > attack_y and enemy.y < attack_y + attack_h then
      
      kill_enemy(enemy)
      break
    end
  end
end

function check_hyper_beam_collisions()
  if not player.hyper_beam_active then return end
  
  -- laser extends from current player position straight down to bottom of screen
  local beam_center_x = player.x + player.w/2
  local beam_left = beam_center_x - player.hyper_beam_width/2
  local beam_right = beam_center_x + player.hyper_beam_width/2
  
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
  
  -- combo and scoring
  player.combo += 1
  local multiplier = get_combo_multiplier()
  player.xp += flr(5 * multiplier)
  score += flr(10 * multiplier)
  
  -- effects
  freeze_timer = 4
  shake_timer = 6
  shake_intensity = 3
  
  -- check player level up
  if player.xp >= player.xp_to_next then
    player.xp -= player.xp_to_next
    player.player_level += 1
    player.xp_to_next += 5
    
    -- start powerup selection with slide animation
    game_state = "powerup_selection"
    powerup_cursor = 1
    powerup_slide_timer = 0
    powerup_fully_visible = false
    generate_powerup_options()
  end
  
  refresh_jumps()
  
  if rnd(1) < player.vampire_chance then heal() end
end

function get_combo_multiplier()
  if player.combo >= 50 then return 1.4
  elseif player.combo >= 20 then return 1.3
  elseif player.combo >= 10 then return 1.2
  elseif player.combo >= 5 then return 1.1
  else return 1.0 end
end

function end_combo()
  if player.combo >= 5 then combo_end_timer = 90 end
  player.combo = 0
end

function heal() 
  player.hearts += 1
  if player.hearts > player.max_hearts then
    player.hearts = player.max_hearts
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
end

function check_platform_collisions()
  local was_grounded = player.grounded
  player.grounded = false
  
  for platform in all(platforms) do
    if player.dy > 0 and
       player.y + player.h > platform.y and
       player.y + player.h < platform.y + 8 and
       player.x + player.w > platform.x and
       player.x < platform.x + platform.w then
      
      player.y = platform.y - player.h
      player.dy = 0
      player.grounded = true
      player.coyote_timer = 2
      player.jump_released = false
      player.apex_boost_used = false
      
      end_combo()
      refresh_jumps()
    end
  end
  
  if was_grounded and not player.grounded then
    player.coyote_timer = 2
  end
end

function check_enemy_collisions()
  if player.invuln_timer > 0 then return end
  
  for enemy in all(enemies) do
    if not enemy.dead and
       player.x + player.w > enemy.x and player.x < enemy.x + enemy.w and
       player.y + player.h > enemy.y and player.y < enemy.y + enemy.h then
      
      -- player hit
      player.hearts -= 1
      player.invuln_timer = flr(player.base_invuln_time * player.invuln_mult)
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

-- CAMERA SYSTEM
function update_camera()
  local target_camera_y = player.y - camera_follow_y
  if target_camera_y < camera_y and player.dy < 0 and camera_sp > player.dy then
    camera_y = camera_y + (target_camera_y - camera_y) * 0.1
    if camera_sp == 0 then
      camera_sp = -0.3 
    end
  else
    camera_y += camera_sp
  end
end

-- WORLD GENERATION
function update_world_generation()
  while next_platform_y > camera_y - 50 do add_platform() end
  
  -- Generate enemies much further ahead so radar has multiple targets
  while next_enemy_y > camera_y - 200 do add_enemy() end -- increased from -50 to -200
  
  -- cleanup
  for platform in all(platforms) do
    if platform.y > camera_y + 150 then del(platforms, platform) end
  end
  
  for enemy in all(enemies) do
    if not enemy.dead and enemy.y > camera_y + 150 then del(enemies, enemy) end
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
  if player.y > camera_y + 150 or player.hearts <= 0 then
    _init()
  end
end

-- ITEM SYSTEM
function use_item()
  if not player.equipped_item or player.item_cooldown > 0 then return end
  
  player.equipped_item.func()
  shake_timer = 3
  shake_intensity = 1
  player.item_cooldown = player.equipped_item.cooldown
  player.max_item_cooldown = player.equipped_item.cooldown
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
    {name = "apple", effect = "+1 maxhp", type = "powerup"},
    {name = "jump boot", effect = "jump higher", type = "powerup"},
    {name = "coffee", effect = "move faster", type = "powerup"},
    {name = "big sword", effect = "+20% sword", type = "powerup"},
    {name = "armor", effect = "+20% invuln", type = "powerup"},
    {name = "radar", effect = "show upcoming enemies", type = "powerup"},
  }
  
  local rare_powers = {
    {name = "air jump", effect = "+1 max jump", type = "powerup"},
    {name = "sky slice", effect = "overhead cut", type = "powerup"},
    {name = "phantom", effect = "ghost ally", type = "powerup"},
    {name = "vampire", effect = "chance to heal", type = "powerup"}
  }
  
  local common_items = {
    {name = "jump potion", effect = "refresh jumps", type = "item", cooldown = 300, func = refresh_jumps},
    {name = "hyper beam", effect = "fire a powerful laser", type = "item", cooldown = 1200, func = fire_hyper_beam}
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
    player.equipped_item = {
      name = powerup.name,
      cooldown = powerup.cooldown,
      func = powerup.func
    }
    player.item_cooldown = 0
    player.max_item_cooldown = powerup.cooldown
  elseif powerup.name == "apple" then
    player.max_hearts += 1
    player.hearts += 1
  elseif powerup.name == "jump boot" then
    player.jump_speed = player.jump_speed + player.jump_speed * 0.2
  elseif powerup.name == "coffee" then
    player.speed = player.speed + player.speed * 0.2
  elseif powerup.name == "air jump" then
    player.max_jumps += 1
    refresh_jumps()
  elseif powerup.name == "big sword" then
    player.sword_size_mult += 0.2
  elseif powerup.name == "sky slice" then
    player.overhead_slices += 1
  elseif powerup.name == "armor" then
    player.invuln_mult += 0.2
  elseif powerup.name == "phantom" then
    local offset_x = player.next_phantom_side * (15 + #player.phantoms * 5)
    local phantom = {x = player.x + offset_x, y = player.y, offset_x = offset_x}
    add(player.phantoms, phantom)
    player.next_phantom_side *= -1
  elseif powerup.name == "vampire" then
    player.vampire_chance += 0.10
  elseif powerup.name == "radar" then
    player.radar_count += 1
  end
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
  end
end

function draw_world()
  for platform in all(platforms) do
    rectfill(platform.x, platform.y, platform.x + platform.w - 1, platform.y + 3, 11)
    rectfill(platform.x, platform.y + 4, platform.x + platform.w - 1, platform.y + 7, 3)
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
  for phantom in all(player.phantoms) do
    if player.invuln_timer <= 0 or player.invuln_timer % 8 < 4 then
      rect(phantom.x, phantom.y, phantom.x + player.w - 1, phantom.y + player.h - 1, 12)
      pset(phantom.x + 2, phantom.y + 2, 12)
      pset(phantom.x + 4, phantom.y + 2, 12)
    end
  end
end

function draw_player()
  if player.invuln_timer <= 0 or player.invuln_timer % 8 < 4 then
    local jump_color_index = min(player.jumps_left + 1, #player.jumps_color)
    rectfill(player.x, player.y, player.x + player.w - 1, player.y + player.h - 1, 
             player.jumps_color[jump_color_index])
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
  if player.combo >= 5 then
    local combo_text = tostr(player.combo)
    local text_x = player.x + player.w/2 - #combo_text * 2
    local text_y = player.y - 8
    
    rectfill(text_x - 2, text_y - 1, text_x + #combo_text * 4, text_y + 5, 0)
    
    local combo_color = 7
    if player.combo >= 50 then combo_color = 14
    elseif player.combo >= 20 then combo_color = 10
    elseif player.combo >= 10 then combo_color = 9
    elseif player.combo >= 5 then combo_color = 11 end
    
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

function draw_attack()
  if player.attacking and player.attack_timer > 7 then
    local base_attack_w = 12
    local base_attack_h = 12
    local attack_w = base_attack_w * player.sword_size_mult
    local attack_h = base_attack_h * player.sword_size_mult
    local attack_x = player.x - (attack_w - player.w) / 2
    local attack_y = player.y + player.h - 2
    
    rect(attack_x, attack_y, attack_x + attack_w - 1, attack_y + attack_h - 1, 9)
    
    if player.overhead_slices > 0 then
      local slice_w = 8 + player.overhead_slices * 4
      local slice_h = 6 + player.overhead_slices * 2
      local slice_x = player.x - (slice_w - player.w) / 2
      local slice_y = player.y - slice_h - 2
      rect(slice_x, slice_y, slice_x + slice_w - 1, slice_y + slice_h - 1, 10)
    end
    
    for phantom in all(player.phantoms) do
      local phantom_attack_x = phantom.x - (attack_w - player.w) / 2
      local phantom_attack_y = phantom.y + player.h - 2
      rect(phantom_attack_x, phantom_attack_y, 
           phantom_attack_x + attack_w - 1, phantom_attack_y + attack_h - 1, 12)
      
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
  if not player.hyper_beam_active then return end
  
  local beam_center_x = player.x + player.w/2 -- use current player position
  local beam_top_y = player.y + player.h
  local beam_bottom_y = camera_y + 128 -- extend to bottom of visible screen
  
  -- crackling border colors that cycle
  local border_colors = {12, 8, 10} -- light blue, red, yellow
  local border_color = border_colors[flr(time() * 10) % 3 + 1]
  
  -- draw the beam from player position downward
  for beam_width = player.hyper_beam_width, 1, -1 do
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
    local crackle_x = beam_center_x + (rnd(player.hyper_beam_width) - player.hyper_beam_width/2)
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
  print("plv: " .. player.player_level, 2, 18, 7)
  print("xp: " .. player.xp .. "/" .. player.xp_to_next, 2, 26, 7)
  
  for i = 1, player.max_hearts do
    local heart_x = 2 + (i - 1) * 8
    print("♥", heart_x, 34, i <= player.hearts and 8 or 5)
  end
  
  if player.equipped_item then
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
  
  local icon_x = item_x + 4
  local icon_y = item_y + 4
  
  if player.equipped_item.name == "jump potion" then
    rect(icon_x + 1, icon_y + 1, icon_x + 4, icon_y + 5, 6)
    rectfill(icon_x + 2, icon_y + 2, icon_x + 3, icon_y + 4, 12)
    line(icon_x + 1, icon_y, icon_x + 4, icon_y, 6)
  elseif player.equipped_item.name == "hyper beam" then
    -- laser beam icon (smaller version for UI)
    line(icon_x + 2, icon_y, icon_x + 2, icon_y + 6, 7) -- white core
    line(icon_x + 3, icon_y, icon_x + 3, icon_y + 6, 7)
    -- crackling edges
    local crackle_color = 12
    if flr(time() * 8) % 3 == 0 then crackle_color = 8
    elseif flr(time() * 8) % 3 == 1 then crackle_color = 10 end
    pset(icon_x + 1, icon_y + 1, crackle_color)
    pset(icon_x + 4, icon_y + 2, crackle_color)
    pset(icon_x, icon_y + 4, crackle_color)
    pset(icon_x + 5, icon_y + 5, crackle_color)
  end  
  if player.item_cooldown > 0 then
    local cooldown_seconds = flr(player.item_cooldown / 60) + 1
    print(tostr(cooldown_seconds) .. "s", item_x + 2, item_y + 18, 8)
    local bar_width = 26
    local progress = (player.max_item_cooldown - player.item_cooldown) / player.max_item_cooldown
    rectfill(item_x + 2, item_y + 16, item_x + 2 + bar_width * progress, item_y + 16, 11)
  end
end

function draw_radar_indicators()
  if player.radar_count <= 0 then return end
  
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
  for i = 1, min(player.radar_count, #upcoming_enemies) do
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
    draw_powerup_icon(powerup_options[i], rect_x + rect_w/2 - 4, rect_y + rect_h/2 - 4)
    
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
    
    -- Instructions
    print("use ←→ to select, ❎/z to confirm", slide_offset + 16, 105, 6)
  end
end

function draw_powerup_icon(powerup, icon_x, icon_y)
  if powerup.name == "apple" then
    -- heart icon
    rectfill(icon_x + 1, icon_y, icon_x + 2, icon_y, 8)
    rectfill(icon_x + 5, icon_y, icon_x + 6, icon_y, 8)
    rectfill(icon_x, icon_y + 1, icon_x + 7, icon_y + 2, 8)
    rectfill(icon_x + 1, icon_y + 3, icon_x + 6, icon_y + 3, 8)
    rectfill(icon_x + 2, icon_y + 4, icon_x + 5, icon_y + 4, 8)
    rectfill(icon_x + 3, icon_y + 5, icon_x + 4, icon_y + 5, 8)
    
  elseif powerup.name == "jump boot" then
    -- boot with upward arrows
    rectfill(icon_x + 2, icon_y, icon_x + 5, icon_y + 2, 12)
    rectfill(icon_x, icon_y + 3, icon_x + 7, icon_y + 5, 12)
    pset(icon_x + 3, icon_y - 2, 7)
    line(icon_x + 2, icon_y - 1, icon_x + 4, icon_y - 1, 7)
    pset(icon_x + 6, icon_y - 2, 7)
    line(icon_x + 5, icon_y - 1, icon_x + 7, icon_y - 1, 7)
    
  elseif powerup.name == "coffee" then
    -- lightning bolt icon
    line(icon_x + 3, icon_y, icon_x + 1, icon_y + 3, 10)
    line(icon_x + 1, icon_y + 3, icon_x + 4, icon_y + 3, 10)
    line(icon_x + 4, icon_y + 3, icon_x + 2, icon_y + 6, 10)
    pset(icon_x + 5, icon_y + 2, 10)
    pset(icon_x, icon_y + 4, 10)
    
  elseif powerup.name == "air jump" then
    -- double jump icon (two boots stacked)
    rectfill(icon_x + 1, icon_y - 1, icon_x + 4, icon_y + 1, 11)
    rectfill(icon_x + 2, icon_y + 2, icon_x + 5, icon_y + 4, 12)
    
  elseif powerup.name == "big sword" then
    -- sword icon
    line(icon_x + 3, icon_y, icon_x + 3, icon_y + 4, 6)
    line(icon_x + 2, icon_y + 5, icon_x + 4, icon_y + 5, 4)
    line(icon_x + 3, icon_y + 6, icon_x + 3, icon_y + 7, 9)
    
  elseif powerup.name == "sky slice" then
    -- overhead slice icon (arc above)
    circfill(icon_x + 3, icon_y + 4, 3, 0)
    circfill(icon_x + 3, icon_y + 4, 2, 10)
    -- arc above
    for a = 0.25, 0.75, 0.1 do
      local px = icon_x + 3 + cos(a) * 4
      local py = icon_y + 4 + sin(a) * 4
      pset(px, py, 10)
    end
    
  elseif powerup.name == "armor" then
    -- shield icon
    rectfill(icon_x + 2, icon_y + 1, icon_x + 5, icon_y + 5, 6)
    pset(icon_x + 3, icon_y, 6)
    pset(icon_x + 4, icon_y, 6)
    line(icon_x + 3, icon_y + 2, icon_x + 4, icon_y + 4, 7)
    
  elseif powerup.name == "phantom" then
    -- phantom icon (ghostly outlines)
    rect(icon_x + 1, icon_y + 1, icon_x + 3, icon_y + 4, 12)
    rect(icon_x + 4, icon_y + 1, icon_x + 6, icon_y + 4, 12)
    rectfill(icon_x + 2, icon_y + 2, icon_x + 4, icon_y + 4, 7)
    
  elseif powerup.name == "vampire" then
    -- vampire fangs with blood drop
    pset(icon_x + 2, icon_y + 1, 7)
    pset(icon_x + 5, icon_y + 1, 7)
    pset(icon_x + 2, icon_y + 2, 7)
    pset(icon_x + 5, icon_y + 2, 7)
    pset(icon_x + 3, icon_y + 4, 8)
    pset(icon_x + 3, icon_y + 5, 8)
    pset(icon_x + 4, icon_y + 5, 8)
    circfill(icon_x + 3, icon_y + 6, 1, 8)
    
  elseif powerup.name == "jump potion" then
    -- potion bottle
    rect(icon_x + 2, icon_y + 2, icon_x + 5, icon_y + 6, 6)
    pset(icon_x + 3, icon_y + 1, 6)
    pset(icon_x + 4, icon_y + 1, 6)
    line(icon_x + 2, icon_y, icon_x + 5, icon_y, 6)
    rectfill(icon_x + 3, icon_y + 3, icon_x + 4, icon_y + 5, 12)
    pset(icon_x + 3, icon_y - 1, 4)
    pset(icon_x + 4, icon_y - 1, 4)
    
  elseif powerup.name == "radar" then
    -- radar/scanner icon (circular with sweeping line)
    circ(icon_x + 3, icon_y + 3, 3, 11) -- outer circle
    circ(icon_x + 3, icon_y + 3, 1, 11) -- inner circle
    -- sweeping radar line
    local angle = time() * 2 -- rotating line
    local line_x = icon_x + 3 + cos(angle) * 3
    local line_y = icon_y + 3 + sin(angle) * 3
    line(icon_x + 3, icon_y + 3, line_x, line_y, 10)
    -- small blips
    pset(icon_x + 1, icon_y + 1, 8)
    pset(icon_x + 5, icon_y + 2, 8)
    
  elseif powerup.name == "hyper beam" then
    -- laser beam icon
    -- central beam
    line(icon_x + 3, icon_y, icon_x + 3, icon_y + 7, 7) -- white core
    line(icon_x + 4, icon_y, icon_x + 4, icon_y + 7, 7)
    -- crackling edges
    local crackle_color = 12 -- light blue
    if flr(time() * 8) % 3 == 0 then crackle_color = 8 -- red
    elseif flr(time() * 8) % 3 == 1 then crackle_color = 10 end -- yellow
    
    pset(icon_x + 2, icon_y + 1, crackle_color)
    pset(icon_x + 5, icon_y + 2, crackle_color)
    pset(icon_x + 1, icon_y + 4, crackle_color)
    pset(icon_x + 6, icon_y + 5, crackle_color)
    pset(icon_x + 2, icon_y + 6, crackle_color)
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
011000000c043000000000000000246150000000000000000c043000000000000000246150000000000000000c043000000000000000246150000000000000000c04300000000000000024615000000000000000
__music__
00 01424344

