package main

import "core:mem"
import "core:fmt"
import sdl "vendor:sdl3"

Game_scene :: enum {
    Menu,
    Game,
}

MapEntity :: struct {
    type: EntityType,
    position: Vector2,
}

exit := false
pause: bool
scene_state: Game_scene
player: ^Entity

main :: proc() {
    when ODIN_DEBUG {
        debug_allocator: mem.Tracking_Allocator
        mem.tracking_allocator_init(&debug_allocator, context.allocator)
        context.allocator = mem.tracking_allocator(&debug_allocator)
    }

    if !sdl.Init(sdl.INIT_VIDEO | sdl.INIT_GAMEPAD | sdl.INIT_AUDIO) {
        panic("SDL3 init failed")
    }
    defer sdl.Quit()

    window := sdl.CreateWindow("Default", WIN_WIDTH, WIN_HEIGHT,
        sdl.WINDOW_OPENGL | sdl.WINDOW_RESIZABLE)
    assert(window != nil)
    defer sdl.DestroyWindow(window)

    audio_init()
    defer audio_exit()

    render_init(window)
    defer render_deinit()
    render_update_viewport(WIN_WIDTH, WIN_HEIGHT)

    input_init(window)    
    controller := controller_create()
    defer sdl.CloseGamepad(controller)
    load_keys()

    load_textures()
    defer sprite_destroy_all()
    defer tilemap_unload_tilemaps()
    defer font_destroy_all()
    defer delete(sprite_map)
    defer delete(tilemap_map)
    defer delete(font_map)

    tiles[1].walkable = true
    map_array: [TILE_ROWS][TILE_COLS]u16
    tile_array = &map_array
    for r in 0..<TILE_ROWS {
        for c in 0..<TILE_COLS {
            tile_array[r][c] = 1 
        }
    }
    scene_load(.Menu)

    performance_freq := cast(f32)sdl.GetPerformanceFrequency()
    time_last := sdl.GetPerformanceCounter()
    for !exit {
        time_start := sdl.GetPerformanceCounter()
        time_delta := f32(time_start - time_last) / performance_freq

        handle_events()
        input_update(time_delta)
        ui_process()

        if pause == false {
            // Update
            for &e, i in entities {
                if entities[i].type != .empty {
                    if e.update != nil {
                        e->update(time_delta)
                    }
                    entity_animate(&e, time_delta)
                    collide_tiles(&e, time_delta)
                }
            }
        }
        collide_entities()

        switch scene_state {
        case .Menu:
            //Do nothing
        case .Game:
            //Do nothing
        }

        for i := 0; i < ENTITY_COUNT; i += 1 {
            if entities[i].type != .empty && entities[i].marked_for_destruction {
                actually_destroy_entity(&entities[i])
            }
        }

        // Render all
        render_pre({0.098, 0.07, 0.059, 1.0})
        render_set_shader(.game_shader)
        tilemap_render()
        for i := 0; i < ENTITY_COUNT; i += 1 {
            if entities[i].type != .empty {
                entity_render(&entities[i])
            }
        }

        render_set_shader(.ui_shader)
        ui_render()

        render_post()
        // Each frame, free all memory allocated by things such as tprint
        free_all(context.temp_allocator)

        when ODIN_DEBUG {
            if len(debug_allocator.bad_free_array) > 0 {
                fmt.println(debug_allocator.bad_free_array)
                panic("Bad free(s) detected.")
            }
        }
        time_last = time_start
    }
}

handle_events :: proc() {
    input_reset()
    event: sdl.Event
    for sdl.PollEvent(&event) {
        #partial switch event.type {
        case sdl.EventType.QUIT:
            exit = true
        case sdl.EventType.WINDOW_RESIZED:
            render_update_viewport(event.window.data1, event.window.data2)
        case:
            input_process(&event)
        }
    }
}

load_keys :: proc() {
    input_add("left", sdl.K_A, sdl.GamepadButton.DPAD_LEFT)
    input_add("right", sdl.K_D, sdl.GamepadButton.DPAD_RIGHT)
    input_add("down", sdl.K_S, sdl.GamepadButton.DPAD_DOWN)
    input_add("up", sdl.K_W, sdl.GamepadButton.DPAD_UP)
    input_add("quit", sdl.K_ESCAPE, sdl.GamepadButton.BACK)
    input_add("action", sdl.K_E, sdl.GamepadButton.NORTH)
}