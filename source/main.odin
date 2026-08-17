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
        //input_update(time_delta)
        //ui_process()

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
        console_print()

        poll_timer += time_delta
        if poll_timer >= 0.5 {
            poll_timer = 0.0
            poll_files()
        }

        when ODIN_DEBUG {
            if len(debug_allocator.bad_free_array) > 0 {
                fmt.println(debug_allocator.bad_free_array)
                panic("Bad free(s) detected.")
            }
        }

        // Each frame, free all memory allocated by things such as tprint
        free_all(context.temp_allocator)

        time_last = time_start
    }
}

console_print :: proc() {
    if stdout_args != nil {
        buf1: [256]u8
        buf2: [256]u8
        has_data1, _ := os.pipe_has_data(stdout_args)
        if has_data1 {
            n, _ := os.read(stdout_args, buf1[:])
            console_add_line(strings.clone(string(buf1[:n])))
        }
        has_data2, _ := os.pipe_has_data(stderr_args)
        if has_data2 {
            n, _ := os.read(stderr_args, buf2[:])
            console_add_line(strings.clone(string(buf2[:n])))
        }

        state, _ := os.process_wait(process, 0)
        if state.exited {
            os.close(stdout_args)
            os.close(stderr_args)
            stdout_args = nil
            stderr_args = nil
        }
    }
}

poll_files :: proc() {
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
            } else {
                if renaming {
                    renaming = false
                    ext := os.ext(event.path)
                    switch ext {
                    case ".png":
                        for i in 0..<len(full_assets_list.textures) {
                            texture := &full_assets_list.textures[i]
                            if texture.path == old_name {
                                delete(texture.path)
                                delete(texture.name)
                                texture.path = strings.clone(event.path)
                                texture.name = strings.clone_to_cstring(os.short_stem(event.path))
                                rename_meta(event.path)
                                break
                            }
                        }
                    case ".wav":
                        for i in 0..<len(full_assets_list.audio) {
                            if full_assets_list.audio[i] == old_name {
                                delete(full_assets_list.audio[i])
                                full_assets_list.audio[i] = strings.clone(event.path)
                                rename_meta(event.path)
                                break
                            }
                        }
                    case ".odin":
                        for i in 0..<len(full_assets_list.scripts) {
                            script := &full_assets_list.scripts[i]
                            if script.path == old_name {
                                delete(script.path)
                                delete(script.name)
                                script.path = strings.clone(event.path)
                                script.name = strings.clone_to_cstring(os.short_stem(event.path))
                                break
                            }
                        }
                    case ".ent":
                        for i in 0..<len(full_assets_list.entities) {
                            if full_assets_list.entities[i] == old_name {
                                delete(full_assets_list.entities[i])
                                full_assets_list.entities[i] = strings.clone(event.path)
                                break
                            }
                        }
                    }
                } else {
                    renaming = true
                    old_name = event.path
                }
            }
        case .Modified:
            if is_dir {
                //Do nothing
            } else {
                ext := os.ext(event.path)
                switch ext {
                case ".odin":
                    for i in 0..<len(full_assets_list.scripts) {
                        script := &full_assets_list.scripts[i]
                        if script.path == event.path {
                            delete(script.name)
                            delete(script.path)
                            for func in script.func {
                                delete(func.name)
                                delete(func.signature)
                            }
                            delete(script.func)
                            unordered_remove(&full_assets_list.scripts, i)
                            list_add_script(event.path)
                            break      
                        }
                    }
                }
            }
        }
    }
    if len(events) > 0 {
        rebuild_asset_list()
    }
}

rename_meta :: proc(path: string) {
    old_meta := fmt.tprintf("%s.meta", old_name)
    new_meta := fmt.tprintf("%s.meta", path)
    if os.exists(old_meta) {
        os.rename(old_meta, new_meta)
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