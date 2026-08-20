package main

import "core:math/linalg"

//Player
PLAYER_SPEED :: 3.75

player_start :: proc(self: ^Entity) {
    self.tag = .player
    entity_anim_run(self, 0, true)
}

player_update :: proc(self: ^Entity, delta_time: f32) {
    if key_down("left") {
        if self.velocity.x > -PLAYER_SPEED {
            self.velocity.x -= 1
            self.flip.x = 1
        }
    } else if key_down("right") {
        if self.velocity.x < PLAYER_SPEED {
            self.velocity.x += 1
            self.flip.x = -1
        }
    } else {
        self.velocity.x = 0
    }
    if key_down("up") {
        if self.velocity.y < PLAYER_SPEED {
            self.velocity.y += 1
        }
    } else if key_down("down") {
        if self.velocity.y > -PLAYER_SPEED {
            self.velocity.y -= 1
        }
    } else {
        self.velocity.y = 0
    }
    if self.velocity.x != 0 || self.velocity.y != 0 {
        if self.anim.clip != 1 {
            entity_anim_run(self, 1, true)
        }
        self.velocity = linalg.normalize(self.velocity) * PLAYER_SPEED
    } else {
        self.velocity = {0, 0}
        if self.anim.clip != 0 {
            entity_anim_run(self, 0, true)
        }
    }
    position := entity_center(self)
    render_set_camera(position.x * QUAD_SIZE, position.y * QUAD_SIZE)
}

menu_main_create :: proc() {
    main_menu := ui_container({0,0}, .middle_center)
    a := ui_button({0, 90}, {260, 60}, menu_new_click, .middle_center, main_menu)
    ui_text({0, 0}, 28, "New Game", .middle_center, a)
    b := ui_button({0, -90}, {260, 60}, menu_quit_click, .middle_center, main_menu)
    ui_text({0, 0}, 28, "Exit Game", .middle_center, b)
}

menu_new_click :: proc(element: ^Ui_element) {
    scene_load(.Game)
}

menu_quit_click :: proc(element: ^Ui_element) {
    exit = true
}

scene_load :: proc(scene: Game_scene) {
    scene_clear()
    scene_state = scene
    switch scene {
    case .Menu:
        menu_main_create()
        tilemap_clear()
    case .Game:
        player = entity_create(.player, {2, 2})
        tilemap_set(0)
        render_set_light(1, 0)
    }
    ui_process()
}

scene_clear :: proc() {
    ui_clear()
    entity_clear_all()
    tilemap_clear()
}