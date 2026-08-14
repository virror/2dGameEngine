package main

import "core:mem"
import "core:fmt"
import "core:strings"
import "core:os"
import sdl "vendor:sdl3"
import imgui "../../imgui"
import "../../imgui/imgui_impl_sdl3"
import "../../imgui/imgui_impl_sdlgpu3"
import fsw "../../odin-fsw"

ODIN_DEBUG :: true
EDITOR :: true
VERSION :: "0.1"

MapEntity :: struct {
    type: EntityType,
    position: Vector2,
}

exit := false
pause: bool
renaming: bool
old_name: string

main :: proc() {
    when ODIN_DEBUG {
        debug_allocator: mem.Tracking_Allocator
        mem.tracking_allocator_init(&debug_allocator, context.allocator)
        context.allocator = mem.tracking_allocator(&debug_allocator)
        defer print_memory(debug_allocator)
    }

    if !sdl.Init(sdl.INIT_VIDEO | sdl.INIT_GAMEPAD | sdl.INIT_AUDIO) {
        panic("SDL3 init failed")
    }
    defer sdl.Quit()

    window := sdl.CreateWindow("2d engine", WIN_WIDTH, WIN_HEIGHT,
        sdl.WINDOW_OPENGL | sdl.WINDOW_RESIZABLE)
    assert(window != nil)
    defer sdl.DestroyWindow(window)

    audio_init()
    defer audio_exit()

    render_init(window)
    defer render_deinit()
    render_update_viewport(WIN_WIDTH, WIN_HEIGHT)

    input_init(window)    
    ui_init(window)
    defer ui_cleanup()

    imgui.CHECKVERSION()
	imgui.CreateContext()
	defer imgui.DestroyContext()
	io := imgui.GetIO()
	io.ConfigFlags += {.NavEnableKeyboard, .NavEnableGamepad, .DockingEnable, .ViewportsEnable}

	imgui.StyleColorsDark()

	style := imgui.GetStyle()
    main_scale := f32(WIN_WIDTH) / f32(WIN_HEIGHT)
	imgui.Style_ScaleAllSizes(style, main_scale)
	style.FontScaleDpi = main_scale
	io.ConfigDpiScaleFonts = true
	io.ConfigDpiScaleViewports = true

	if .ViewportsEnable in io.ConfigFlags {
		style.WindowRounding = 0
		style.Colors[imgui.Col.WindowBg].w = 1
        style.ScrollbarSize = 12
        style.IndentSpacing = 20
	}

	imgui_impl_sdl3.InitForSDLGPU(window)
	defer imgui_impl_sdl3.Shutdown()

    init_info := imgui_impl_sdlgpu3.InitInfo {
		Device               = get_gpu(),
		ColorTargetFormat    = sdl.GetGPUSwapchainTextureFormat(get_gpu(), window),
		MSAASamples          = ._1,
		SwapchainComposition = .SDR,
		PresentMode          = .VSYNC,
	}
	imgui_impl_sdlgpu3.Init(&init_info)
	defer imgui_impl_sdlgpu3.Shutdown()

    performance_freq := cast(f32)sdl.GetPerformanceFrequency()
    time_last := sdl.GetPerformanceCounter()
    poll_timer :f32= 0.0

    for !exit {
        time_start := sdl.GetPerformanceCounter()
        time_delta := f32(time_start - time_last) / performance_freq

        handle_events()
        input_update(time_delta)
        ui_process()

        /*if pause == false {
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
            collide_entities()
        }*/

        for i := 0; i < ENTITY_COUNT; i += 1 {
            if entities[i].type != .empty && entities[i].marked_for_destruction {
                actually_destroy_entity(&entities[i])
            }
        }

        ui_update()

        // Render all
        render_pre({0.298, 0.27, 0.259, 1.0})
        render_set_shader(.game_shader)
        for i in 0..<len(entities) {
            if entities[i].type != .empty {
                entity_render(&entities[i])
            }
        }

        render_set_shader(.ui_shader)
        ui_render()

        render_post(io)

        // Each frame, free all memory allocated by things such as tprint
        free_all(context.temp_allocator)

        when ODIN_DEBUG {
            if len(debug_allocator.bad_free_array) > 0 {
                fmt.println(debug_allocator.bad_free_array)
                panic("Bad free(s) detected.")
            }
        }

        poll_timer += time_delta
        if poll_timer >= 0.5 {
            poll_timer = 0.0
            events := fsw.get_events(&file_watcher)
            defer fsw.delete_events(events)

            for event in events {
                is_dir := os.ext(event.path) == ""
                #partial switch event.kind {
                case .Added:
                    if is_dir {
                        parts := strings.split(event.path, "\\", context.temp_allocator)
                        name := parts[len(parts) - 1]
                        path := parts[len(parts) - 2]
                        folder_add(path, name, &root_folder)
                    } else {
                        ext := os.ext(event.path)
                        switch ext {
                        case ".png":
                            meta_create_sprite(event.path)
                            add_asset(event.path, ext)
                        case ".wav":
                            meta_create_audio(event.path)
                            add_asset(event.path, ext)
                        case ".odin":
                            add_asset(event.path, ext)
                        }
                    }
                case .Removed:
                    if is_dir {
                        parts := strings.split(event.path, "\\", context.temp_allocator)
                        name := parts[len(parts) - 1]
                        folder_remove(name, &root_folder)
                    } else {
                        ext := os.ext(event.path)
                        switch ext {
                        case ".png",
                             ".wav":
                            path := fmt.tprintf("%s.meta", event.path)
                            if os.exists(path) {
                                os.remove(path)
                            }
                            remove_asset(event.path, ext)
                        case ".odin":
                            remove_asset(event.path, ext)
                        }
                    }
                case .Renamed:
                    if is_dir {
                        if renaming {
                            renaming = false
                            parts := strings.split(event.path, "\\", context.temp_allocator)
                            new_name := parts[len(parts) - 1]
                            folder_rename(old_name, new_name, &root_folder)
                        } else {
                            renaming = true
                            parts := strings.split(event.path, "\\", context.temp_allocator)
                            old_name = parts[len(parts) - 1]
                        }
                    }
                    //TODO: Handle file renames
                case .Modified:
                    fmt.println(event)   
                }
            }
            if len(events) > 0 {
                rebuild_asset_list()
            }
        }
        time_last = time_start
    }
}

handle_events :: proc() {
    input_reset()
    event: sdl.Event
    for sdl.PollEvent(&event) {
        imgui_impl_sdl3.ProcessEvent(&event)
        #partial switch event.type {
        case sdl.EventType.WINDOW_CLOSE_REQUESTED:
            exit = true
        case sdl.EventType.WINDOW_RESIZED:
            render_update_viewport(event.window.data1, event.window.data2)
        }
    }
}

print_memory :: proc(debug_allocator: mem.Tracking_Allocator) {
    fmt.println(debug_allocator.allocation_map)
    fmt.println(debug_allocator.current_memory_allocated)
}