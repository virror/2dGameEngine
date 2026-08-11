package main

import sdl "vendor:sdl3"

load_tilemaps :: proc() {
    tilemaps[0] = tilemap_load_tileset(#load("../tilemaps/Village.png"))
}

load_ui_sprites :: proc() {
    ui_sprites[0] = sprite_create(#load("../sprites/ui/White.png"), {1, 1})
    ui_sprites[1] = sprite_create(#load("../sprites/ui/Bitmap_font.png"), {18, 6})
    ui_sprites[2] = sprite_create(#load("../sprites/ui/Button.png"), {1, 1})
    ui_sprites[2].slice9 = {5, 5, 5, 5}
}

load_sprites :: proc() {
    sprites[0] = sprite_create(#load("../sprites/Player.png"), {6, 12})
}

load_keys :: proc() {
    input_add("left", sdl.K_A, sdl.GamepadButton.DPAD_LEFT)
    input_add("right", sdl.K_D, sdl.GamepadButton.DPAD_RIGHT)
    input_add("down", sdl.K_S, sdl.GamepadButton.DPAD_DOWN)
    input_add("up", sdl.K_W, sdl.GamepadButton.DPAD_UP)
    input_add("quit", sdl.K_ESCAPE, sdl.GamepadButton.BACK)
    input_add("action", sdl.K_E, sdl.GamepadButton.NORTH)
}