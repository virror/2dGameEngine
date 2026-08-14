package main

import "base:runtime"
import "core:fmt"
import "core:os"
import "core:strings"
import "core:time"
import sdl "vendor:sdl3"
import "../../imgui"
import "../../imgui/imgui_impl_sdl3"
import "../../imgui/imgui_impl_sdlgpu3"
import fsw "../../odin-fsw"
import mix "vendor:sdl3/mixer"

@(private="file")
Asset_type :: enum {
    Unknown,
    Sprite,
    Entity,
    Sound,
    Script,
}

Sprite_type :: enum {
    Sprite,
    Tilemap,
    Font,
}

@(private="file")
Texture :: struct {
    texture: u32,
    size: Vector2,
}

@(private="file")
Asset :: struct {
    name: cstring,
    texture: Texture,
    type: Asset_type,
    path: string,
}

@(private="file")
Folder_node :: struct {
    name: cstring,
    children: [dynamic]Folder_node,
    selected: bool,
    parent: ^Folder_node,
}

@(private="file")
Recent_item :: struct {
    path: string,
    date: string,
}

@(private="file")
Asset_list_item :: struct {
    path: string,
    name: cstring,
}

@(private="file")
Asset_list_script :: struct {
    path: string,
    name: cstring,
    list: [dynamic]cstring,
}

@(private="file")
Asset_List :: struct {
    textures: [dynamic]Asset_list_item,
    scripts: [dynamic]Asset_list_script,
    audio: [dynamic]string,
    entities: [dynamic]string,
}

file_watcher: fsw.Watcher
@(private="file")
io: ^imgui.IO
@(private="file")
viewport: ^imgui.Viewport
@(private="file")
window_flags := imgui.WindowFlags{.NoResize, .NoMove, .NoCollapse, .NoTitleBar}
@(private="file")
window: ^sdl.Window
@(private="file")
show_welcome: bool = true
@(private="file")
show_new_project: bool = false
@(private="file")
show_open_project: bool = false
@(private="file")
show_colorpicker: bool = false
@(private="file")
show_working: bool = false
@(private="file")
file_not_found: string = ""
@(private="file")
console_output: [dynamic]string
@(private="file")
project_loaded: bool = false
//@(private="file")
root_folder: Folder_node
@(private="file")
old_color: [4]f32
@(private="file")
sprite_props: Sprite_props
audio_props: Audio_props
entity_props: Entity_props
@(private="file")
assets_list: [dynamic]Asset
@(private="file")
filter_2de: sdl.DialogFileFilter = {name = "2d engine project", pattern = "2de"}
@(private="file")
filter_ent: sdl.DialogFileFilter = {name = "Entity file", pattern = "ent"}
@(private="file")
set_console_focus: bool = false
@(private="file")
icon_texture: u32
@(private="file")
odin_texture: u32
@(private="file")
audio_texture: u32
@(private="file")
entity_texture: u32
@(private="file")
recent_list: [5]Recent_item
full_assets_list: Asset_List
@(private="file")
selected_folder: string
loaded_track: ^mix.Track
stdout_args: ^os.File
stderr_args: ^os.File
process: os.Process

ui_init :: proc(window_: ^sdl.Window) {
    window = window_
    icon_texture, _ = texture_create(#load("../sprites/Icons.png"))
    odin_texture, _ = texture_create(#load("../sprites/Odin.png"))
    audio_texture, _ = texture_create(#load("../sprites/Audio.png"))
    entity_texture, _ = texture_create(#load("../sprites/Entity.png"))
    recent_read()
    project_name = fmt.caprintf("")
}

ui_cleanup :: proc() {
    texture_destroy(icon_texture)
    texture_destroy(odin_texture)
    texture_destroy(audio_texture)
    texture_destroy(entity_texture)
    fmt.println("0")
    for asset in assets_list {
        if asset.type == .Sprite {
            texture_destroy(asset.texture.texture)
        }
        delete(asset.name)
        delete(asset.path)
    }
    fmt.println("1")
    delete(assets_list)
    for item in recent_list {
        delete(item.path)
        delete(item.date)
    }
    fmt.println("2")
    delete(project_name)
    clean_folder(&root_folder)
    fsw.destroy(file_watcher)
    fmt.println("2.5")
    for text in console_output {
        delete(text)
    }
    fmt.println("3")
    delete(console_output)
    for asset in full_assets_list.textures {
        delete(asset.path)
        delete(asset.name)
    }
    delete(full_assets_list.textures)
    fmt.println("3.5")
    for asset in full_assets_list.scripts {
        delete(asset.path)
        delete(asset.name)
        for apa in asset.list {
            delete(apa)
        }
        delete(asset.list)
    }
    delete(full_assets_list.scripts)
    fmt.println("4")
    for asset in full_assets_list.audio {
        delete(asset)
    }
    delete(full_assets_list.audio)
    for asset in full_assets_list.entities {
        delete(asset)
    }
    delete(full_assets_list.entities)
    delete(textures)
    delete(selected_folder)
    fmt.println("5")
    delete(audio_props.duration)
    delete(entity_props.sprite)
    delete(entity_props.script_file1)
    delete(entity_props.script_file2)
    delete(entity_props.script_file3)
    delete(entity_props.update)
    delete(entity_props.on_collide_entity)
    delete(entity_props.on_collide_tile)
    mix.DestroyAudio(mix.GetTrackAudio(loaded_track))
    mix.DestroyTrack(loaded_track)
}

recent_read :: proc() {
    fs, _ := os.open("recent.txt", os.O_RDONLY | os.O_CREATE)
    defer os.close(fs)
    data, _ := os.read_entire_file(fs, context.temp_allocator)
    it := string(data)
    recent, _ := strings.split(it, "\n", context.temp_allocator)
    for i := 0; i < len(recent); i += 1 {
        if recent[i] == "" {
            continue
        }
        items, _ := strings.split(recent[i], ";", context.temp_allocator)
        recent_list[i] = Recent_item{path = strings.clone(items[0]), date = strings.clone(items[1])}
    }
}

recent_add :: proc(path: string) {
    existed := false
    now := time.now()
    for i := 0; i < len(recent_list); i += 1 {
        if recent_list[i].path == path {
            copy(recent_list[1:i + 1], recent_list[0:i])
            existed = true
            break
        }
    }
    if !existed {
        copy(recent_list[1:], recent_list[:len(recent_list)-1])
    }
    time_string, _ := time.time_to_rfc3339(now, 0, false, context.allocator)
    recent_list[0] = Recent_item{path, time_string}
    recent_write()
}

recent_write :: proc() {
    fs, _ := os.open("recent.txt", os.O_WRONLY | os.O_CREATE | os.O_TRUNC)
    for item in recent_list {
        if item.path == "" {
            continue
        }
        os.write_string(fs, item.path)
        os.write_string(fs, ";")
        os.write_string(fs, item.date)
        os.write_string(fs, "\n")
    }
    os.close(fs)
}

ui_update :: proc() {
    imgui_impl_sdlgpu3.NewFrame()
    imgui_impl_sdl3.NewFrame()
    imgui.NewFrame()
    
    viewport = imgui.GetMainViewport()
    ui_show_left()
    ui_show_right()
    ui_show_top()
    ui_show_bottom()
    if show_welcome {
        imgui.OpenPopup("Welcome")
        show_welcome = false
    }
    ui_show_welcome()
    if show_new_project {
        imgui.OpenPopup("New Project")
        copy(new_project_name[:len(new_project_name)-1], "New Project")
        show_new_project = false
    }
    ui_show_new_project()
    if show_open_project {
        imgui.OpenPopup("Open Project")
        show_open_project = false
    }
    ui_show_open_project()
    if show_colorpicker {
        ui_show_colorpicker()
    }
    if show_working {
        imgui.OpenPopup("Working")
    }
    ui_show_working()
    if file_not_found != "" {
        imgui.OpenPopup("File not found")
    }
    ui_show_file_not_found()
    imgui.Render()
}

ui_show_left :: proc() {
    imgui.SetNextWindowPos(viewport.Pos, .Always, imgui.Vec2{0, 0})
    imgui.SetNextWindowSize(imgui.Vec2{300, viewport.Size.y - 210})
    if imgui.Begin("LeftPanel", nil, window_flags) {
        if imgui.BeginTabBar("AssetsTabBar") {
            imgui.SetNextItemWidth(90)
            if imgui.BeginTabItem("Entities") {
                if project_loaded {
                    imgui.Text("Entities here")
                }
                imgui.EndTabItem()
            }
            imgui.SetNextItemWidth(90)
            if imgui.BeginTabItem("UI") {
                if project_loaded {
                    imgui.Text("UI here")
                }
                imgui.EndTabItem()
            }
        }
        imgui.EndTabBar()
    }
    imgui.End()
}

ui_show_colorpicker :: proc() {
    imgui.SetNextWindowPos(viewport.Pos + imgui.Vec2{300, 50}, .Always, imgui.Vec2{0, 0})
    imgui.SetNextWindowSize(imgui.Vec2{300, 350})
    if imgui.Begin("ColorPicker", nil) {
        //imgui.ColorPicker4("##Color", &sprite_props.color)
        imgui.Spacing()   
        if imgui.Button("Apply") {
            show_colorpicker = false
        }
        imgui.SameLine(80, 0)
        if imgui.Button("Cancel") {
            //sprite_props.color = old_color
            show_colorpicker = false
        }
    }
    imgui.End()
}

sprite_types := []cstring{"Sprite", "Tilemap", "Font"}
sprite_type_pre := sprite_types[0]
entity_type_pre :cstring
script_idx1 :int = 0
script_idx2 :int = 0
script_idx3 :int = 0

ui_show_right :: proc() {
    imgui.SetNextWindowPos(viewport.Pos + imgui.Vec2{viewport.Size.x, 0}, .Always, imgui.Vec2{1, 0})
    imgui.SetNextWindowSize(imgui.Vec2{300, viewport.Size.y - 210})
    if imgui.Begin("RightPanel", nil, window_flags) {
        if imgui.BeginTabBar("AssetsTabBar") {
            imgui.SetNextItemWidth(90)
            if imgui.BeginTabItem("Properties") {
                if selected_asset != nil && project_loaded {
                    switch selected_asset.type {
                    case .Sprite:
                        imgui.Text(selected_asset.name)
                        imgui.Text(fmt.ctprintf("Size: %.0fx%.0f", selected_asset.texture.size.x, selected_asset.texture.size.y))
                        //TODO: Fix crash here? : (
                        /*ratio := f32(selected_asset.texture.size.x) / f32(selected_asset.texture.size.y)
                        if ratio > 1.0 {
                            imgui.Image(texture_to_image(selected_asset.texture.texture), imgui.Vec2{100, 100 / ratio})
                        } else {
                            imgui.Image(texture_to_image(selected_asset.texture.texture), imgui.Vec2{100 * ratio, 100})
                        }*/
                        imgui.Spacing()
                        imgui.Text("Texture type:")
                        sprite_type_pre = sprite_types[int(sprite_props.type)]
                        if imgui.BeginCombo("##SpriteProps", sprite_type_pre) {
                            for i := 0; i < len(sprite_types); i += 1 {
                                is_selected := int(sprite_props.type) == i
                                if imgui.Selectable(sprite_types[i], is_selected) {
                                    sprite_props.type = string_type_to_type(sprite_types[i])
                                }
                                if is_selected {
                                    imgui.SetItemDefaultFocus()
                                }
                            }
                            imgui.EndCombo()
                        }
                        switch sprite_type_pre {
                        case "Sprite":
                            imgui.Text("Frames:")
                            imgui.Text("X:")
                            imgui.SetCursorPos(imgui.Vec2{30, imgui.GetCursorPos().y - 25})
                            imgui.SetNextItemWidth(120)
                            imgui.InputInt("##FramesX", &sprite_props.frames[0])
                            imgui.Text("Y:")
                            imgui.SetCursorPos(imgui.Vec2{30, imgui.GetCursorPos().y - 25})
                            imgui.SetNextItemWidth(120)
                            imgui.InputInt("##FramesY", &sprite_props.frames[1])
                            imgui.Spacing()
                            imgui.Text("9 Slice:")
                            imgui.SetCursorPos(imgui.Vec2{95, imgui.GetCursorPos().y - 25})
                            if imgui.Checkbox("##9 Slice", &sprite_props.is_slice9) {
                                if sprite_props.is_slice9 {
                                    sprite_props.slice9 = [4]i32{1, 1, 1, 1}
                                } else {
                                    sprite_props.slice9 = [4]i32{0, 0, 0, 0}
                                }
                            }
                            if sprite_props.is_slice9 {
                                imgui.Spacing()
                                imgui.Text("Left:")
                                imgui.SetCursorPos(imgui.Vec2{70, imgui.GetCursorPos().y - 25})
                                imgui.SetNextItemWidth(120)
                                imgui.InputInt("##Slice9_1", &sprite_props.slice9.x)
                                imgui.Text("Top:")
                                imgui.SetCursorPos(imgui.Vec2{70, imgui.GetCursorPos().y - 25})
                                imgui.SetNextItemWidth(120)
                                imgui.InputInt("##Slice9_2", &sprite_props.slice9.y)
                                imgui.Text("Right:")
                                imgui.SetCursorPos(imgui.Vec2{70, imgui.GetCursorPos().y - 25})
                                imgui.SetNextItemWidth(120)
                                imgui.InputInt("##Slice9_3", &sprite_props.slice9.z)
                                imgui.Text("Bottom:")
                                imgui.SetCursorPos(imgui.Vec2{70, imgui.GetCursorPos().y - 25})
                                imgui.SetNextItemWidth(120)
                                imgui.InputInt("##Slice9_4", &sprite_props.slice9.w)
                            }
                        case "Tilemap":
                            imgui.Text("Frames:")
                            imgui.Text("X:")
                            imgui.SetCursorPos(imgui.Vec2{30, imgui.GetCursorPos().y - 25})
                            imgui.SetNextItemWidth(120)
                            imgui.InputInt("##FramesX", &sprite_props.frames[0])
                            imgui.Text("Y:")
                            imgui.SetCursorPos(imgui.Vec2{30, imgui.GetCursorPos().y - 25})
                            imgui.SetNextItemWidth(120)
                            imgui.InputInt("##FramesY", &sprite_props.frames[1])
                        case "Font":
                            imgui.Text("Frames:")
                            imgui.Text("X:")
                            imgui.SetCursorPos(imgui.Vec2{30, imgui.GetCursorPos().y - 25})
                            imgui.SetNextItemWidth(120)
                            imgui.InputInt("##FramesX", &sprite_props.frames[0])
                            imgui.Text("Y:")
                            imgui.SetCursorPos(imgui.Vec2{30, imgui.GetCursorPos().y - 25})
                            imgui.SetNextItemWidth(120)
                            imgui.InputInt("##FramesY", &sprite_props.frames[1])
                        }
                        imgui.Spacing()
                        imgui.Spacing()
                        if imgui.Button("Apply") {
                            meta_save_sprite(selected_asset.path, sprite_props)
                        }
                        imgui.SameLine(80, 0)
                        if imgui.Button("Revert") {
                            sprite_props = meta_load_sprite(selected_asset.path)
                        }
                    case .Sound:
                        imgui.Text(selected_asset.name)
                        imgui.Text(fmt.ctprintf("Duration: %s", audio_props.duration))
                        imgui.Text(fmt.ctprintf("Channels: %d", audio_props.channels))
                        imgui.Text(fmt.ctprintf("Sample Rate: %d", audio_props.sample_rate))
                        imgui.Spacing()
                        if mix.TrackPlaying(loaded_track) {
                            if imgui.ImageButton("StopTrack", texture_to_image(icon_texture), imgui.Vec2{24, 24}, imgui.Vec2{0, 0.333}, imgui.Vec2{0.333, 0.666}) {
                                if !mix.StopTrack(loaded_track, 0) {
                                    panic("Failed to stop audio.")
                                }
                            }
                        } else {
                            if imgui.ImageButton("PlayTrack", texture_to_image(icon_texture), imgui.Vec2{24, 24}, imgui.Vec2{0.333, 0}, imgui.Vec2{0.666, 0.333}) {
                                options := sdl.CreateProperties()
                                if !mix.PlayTrack(loaded_track, options) {
                                    panic("Failed to play audio.")
                                }
                            }
                        }
                        imgui.SameLine(60, 0)
                        duration := mix.GetAudioDuration(mix.GetTrackAudio(loaded_track))
                        my_value := f32(mix.GetTrackPlaybackPosition(loaded_track)) / f32(duration)
                        if imgui.SliderFloat("##Playback Slider", &my_value, 0.0, 1.0, "") {
                            if !mix.SetTrackPlaybackPosition(loaded_track, i64(my_value * f32(duration))) {
                                panic("Failed to set audio position.")
                            }
                        }
                        imgui.Spacing()
                        imgui.Text("Preload:")
                        imgui.SetCursorPos(imgui.Vec2{95, imgui.GetCursorPos().y - 25})
                        imgui.Checkbox("##Preload", &audio_props.preload)
                        imgui.Spacing()
                        imgui.Spacing()
                        if imgui.Button("Apply") {
                            meta_save_audio(selected_asset.path, audio_props)
                        }
                        imgui.SameLine(80, 0)
                        if imgui.Button("Revert") {
                            audio_props = meta_load_audio(selected_asset.path, true)
                        }
                    case .Entity:
                        imgui.Text(selected_asset.name)
                        imgui.Spacing()
                        imgui.Text("Sprite:")
                        if entity_props.sprite != "" {
                            entity_type_pre = entity_props.sprite
                        } else {
                            entity_type_pre = "None"
                        }
                        if imgui.BeginCombo("##Sprite", entity_type_pre) {
                            for i := 0; i < len(full_assets_list.textures); i += 1 {
                                is_selected := entity_props.sprite == full_assets_list.textures[i].name
                                if imgui.Selectable(full_assets_list.textures[i].name, is_selected) {
                                    delete(entity_props.sprite)
                                    entity_props.sprite = strings.clone_to_cstring(string(full_assets_list.textures[i].name))
                                }
                                if is_selected {
                                    imgui.SetItemDefaultFocus()
                                }
                            }
                            imgui.EndCombo()
                        }
                        imgui.Spacing()
                        col := entity_props.collider
                        imgui.Text(fmt.ctprintf("Collider: %d, %d, %d, %d", col.x, col.y, col.z, col.w))
                        imgui.Button("Edit collider", imgui.Vec2{102, 25})
                        imgui.Spacing()
                        imgui.Text("Mass:")
                        imgui.SetCursorPos(imgui.Vec2{95, imgui.GetCursorPos().y - 25})
                        imgui.SetNextItemWidth(114)
                        imgui.InputFloat("##Mass", &entity_props.mass, 0.1, 1.0, "%.2f")
                        imgui.Text("Friction:")
                        imgui.SetCursorPos(imgui.Vec2{95, imgui.GetCursorPos().y - 25})
                        imgui.SetNextItemWidth(114)
                        imgui.InputFloat("##Friction", &entity_props.friction, 0.1, 1.0, "%.2f")
                        imgui.Text("Bounciness:")
                        imgui.SetCursorPos(imgui.Vec2{95, imgui.GetCursorPos().y - 25})
                        imgui.SetNextItemWidth(114)
                        imgui.InputFloat("##Bounciness", &entity_props.bounciness, 0.1, 1.0, "%.2f")
                        imgui.Text("Trigger:")
                        imgui.SetCursorPos(imgui.Vec2{95, imgui.GetCursorPos().y - 25})
                        imgui.Checkbox("##Trigger", &entity_props.trigger)
                        imgui.Text("No Gravity:")
                        imgui.SetCursorPos(imgui.Vec2{95, imgui.GetCursorPos().y - 25})
                        imgui.Checkbox("##No Gravity", &entity_props.no_gravity)
                        imgui.Spacing()
                        imgui.Text("Update:")
                        entity_props.script_file1 = ui_script_dropdown("##Update", entity_props.script_file1, &script_idx1)
                        if imgui.BeginCombo("##UpdateScript", entity_props.update) {
                            if entity_props.script_file1 != "None" {
                                for i := 0; i < len(full_assets_list.scripts[script_idx1].list); i += 1 {
                                    is_selected := entity_props.update == full_assets_list.scripts[script_idx1].list[i]
                                    if imgui.Selectable(full_assets_list.scripts[script_idx1].list[i], is_selected) {
                                        entity_props.update = strings.clone_to_cstring(string(full_assets_list.scripts[script_idx1].list[i]))
                                    }
                                    if is_selected {
                                        imgui.SetItemDefaultFocus()
                                    }
                                }
                            }
                            imgui.EndCombo()
                        }
                        imgui.Text("On Collide Entity:")
                        entity_props.script_file2 = ui_script_dropdown("##On Collide Entity", entity_props.script_file2, &script_idx2)
                        if imgui.BeginCombo("##On Collide EntityScript", entity_props.on_collide_entity) {
                            if entity_props.script_file2 != "None" {
                                for i := 0; i < len(full_assets_list.scripts); i += 1 {
                                    is_selected := entity_props.on_collide_entity == full_assets_list.scripts[script_idx2].list[i]
                                    if imgui.Selectable(full_assets_list.scripts[script_idx2].list[i], is_selected) {
                                        entity_props.on_collide_entity = strings.clone_to_cstring(string(full_assets_list.scripts[script_idx2].list[i]))
                                    }
                                    if is_selected {
                                        imgui.SetItemDefaultFocus()
                                    }
                                }
                            }
                            imgui.EndCombo()
                        }
                        imgui.Text("On Collide Tile:")
                        entity_props.script_file3 = ui_script_dropdown("##On Collide Tile", entity_props.script_file3, &script_idx3)
                        if imgui.BeginCombo("##On Collide TileScript", entity_props.on_collide_tile) {
                            if entity_props.script_file3 != "None" {
                                for i := 0; i < len(full_assets_list.scripts); i += 1 {
                                    is_selected := entity_props.on_collide_tile == full_assets_list.scripts[script_idx3].list[i]
                                    if imgui.Selectable(full_assets_list.scripts[script_idx3].list[i], is_selected) {
                                        entity_props.on_collide_tile = strings.clone_to_cstring(string(full_assets_list.scripts[script_idx3].list[i]))
                                    }
                                    if is_selected {
                                        imgui.SetItemDefaultFocus()
                                    }
                                }
                            }
                            imgui.EndCombo()
                        }
                        imgui.Spacing()
                        imgui.Spacing()
                        if imgui.Button("Apply") {
                            meta_save_entity(selected_asset.path, entity_props)
                        }
                        imgui.SameLine(80, 0)
                        if imgui.Button("Revert") {
                            entity_props = meta_load_entity(selected_asset.path)
                        }
                    case .Script:
                    case .Unknown:
                    }
                }
                imgui.EndTabItem()
            }
            imgui.SetNextItemWidth(90)
            if imgui.BeginTabItem("Tiles") {
                if project_loaded {
                    imgui.Text("Tiles here")
                }
                imgui.EndTabItem()
            }
        }
        imgui.EndTabBar()
    }
    imgui.End()
}

ui_script_dropdown :: proc(id: cstring, script_file: cstring, idx: ^int) -> cstring {
    tmp_file := script_file
    if imgui.BeginCombo(id, script_file) {
        for i := 0; i < len(full_assets_list.scripts); i += 1 {
            if len(full_assets_list.scripts[i].list) == 0 {
                continue
            }
            if full_assets_list.scripts[i].name == "" {
                continue
            }
            is_selected := script_file == full_assets_list.scripts[i].name
            if imgui.Selectable(full_assets_list.scripts[i].name, is_selected) {
                tmp_file = full_assets_list.scripts[i].name
                idx^ = i
                switch id {
                case "##Update":
                    entity_props.update = "None"
                case "##On Collide Entity":
                    entity_props.on_collide_entity = "None"
                case "##On Collide Tile":
                    entity_props.on_collide_tile = "None"
                }
            }
            if is_selected {
                imgui.SetItemDefaultFocus()
            }
        }
        imgui.EndCombo()
    }
    return tmp_file
}

string_type_to_type :: proc(value: cstring) -> Sprite_type {
    switch value {
    case "Sprite":
        return .Sprite
    case "Tilemap":
        return .Tilemap
    case "Font":
        return .Font
    }
    return .Sprite
}

ui_show_top :: proc() {
    imgui.SetNextWindowPos(viewport.Pos + imgui.Vec2{300, 0}, .Always, imgui.Vec2{0, 0})
    imgui.SetNextWindowSize(imgui.Vec2{viewport.Size.x - 600, 60})
    if imgui.Begin("TopPanel", nil, window_flags) {
        imgui.SetCursorPosY(10)
        if imgui.ImageButton("New", texture_to_image(icon_texture), imgui.Vec2{24, 24}, imgui.Vec2{0.666, 0}, imgui.Vec2{1, 0.333}) {
            if project_loaded {
                clean_project()
                show_new_project = true
            }
        }
        imgui.SetItemTooltip("New project")
        imgui.SameLine(60, 0)
        if imgui.ImageButton("Open", texture_to_image(icon_texture), imgui.Vec2{24, 24}, imgui.Vec2{0, 0}, imgui.Vec2{0.333, 0.333}) {
            if project_loaded {
                clean_project()
                show_open_project = true
            }
        }
        imgui.SetItemTooltip("Open project")
        imgui.SameLine(120, 0)
        if stdout_args != nil {
            if imgui.ImageButton("Stop", texture_to_image(icon_texture), imgui.Vec2{24, 24}, imgui.Vec2{0, 0.333}, imgui.Vec2{0.333, 0.666}) {
                if project_loaded {
                    if os.process_terminate(process) != nil {
                        panic("Failed to kill process.")
                    }
                }
            }
        } else {
            if imgui.ImageButton("Run", texture_to_image(icon_texture), imgui.Vec2{24, 24}, imgui.Vec2{0.333, 0}, imgui.Vec2{0.666, 0.333}) {
                if project_loaded {
                    run_project()
                }
            }
            imgui.SetItemTooltip("Run project")
        }
    }
    imgui.End()
}

clean_project :: proc() {
    project_loaded = false
    project_path = strings.clone("")
    fsw.destroy(file_watcher)
}

run_project :: proc() {
    build_assets()
    desc: os.Process_Desc
    path := fmt.tprintf("%s\\source", project_path)
    stdout_read, stdout_write, _ := os.pipe()
	stderr_read, stderr_write, _ := os.pipe()
    command := []string {
        "../Odin/odin.exe",
        "run",
        path,
        "-o:speed",
        "-vet-unused-variables",
        "-vet-shadowing",
        "-vet-using-stmt",
        "-strict-style",
    }
    desc.command = command
    desc.working_dir = project_path
    desc.stdout = stdout_write
    desc.stderr = stderr_write
    process, _ = os.process_start(desc)
    os.close(stdout_write)
	os.close(stderr_write)
    stdout_args = stdout_read
	stderr_args = stderr_read
}

console_add_line :: proc(line: string) {
    if len(console_output) > 100 {
        ordered_remove(&console_output, 0)
    }
    append(&console_output, line)
    set_console_focus = true
}

@(private="file")
selected_asset_idx: int = -1
selected_asset: ^Asset

ui_show_bottom :: proc() {
    imgui.SetNextWindowPos(viewport.Pos + imgui.Vec2{-300, viewport.Size.y - 210} + imgui.Vec2{300, 0}, .Always, imgui.Vec2{0, 0})
    imgui.SetNextWindowSize(imgui.Vec2{viewport.Size.x, 210})
    if imgui.Begin("BottomPanel", nil, window_flags) {
        if imgui.BeginTabBar("AssetsTabBar") {
            imgui.SetNextItemWidth(90)
            if imgui.BeginTabItem("Assets") {
                if imgui.BeginChild("AssetsChild", imgui.Vec2{285, 150}) {
                    if project_loaded {
                        draw_folder_tree(&root_folder)
                    }
                    imgui.EndChild()
                }

                pos1 := viewport.Pos + imgui.Vec2{300.0, viewport.Size.y - 173}
                pos2 := viewport.Pos + imgui.Vec2{300.0, viewport.Size.y}
                ui_draw_line(pos1, pos2)

                imgui.SameLine(310, 0)
                if imgui.BeginChild("AssetsList", imgui.Vec2{viewport.Size.x - 310, 150}) {
                    if project_loaded {
                        draw_asset_items()
                    }
                    imgui.Dummy(imgui.Vec2{10, 0})
                    imgui.EndChild()
                }

                if imgui.BeginPopupContextItem(nil, imgui.PopupFlags_MouseButtonRight) {
                    if imgui.Selectable("Create entity") {
                        tmp_file := fmt.ctprintf("%s\\NewEntity.ent", selected_folder)
                        sdl.ShowSaveFileDialog(save_callback, nil, nil, &filter_ent, 1, tmp_file)
                    }
                    imgui.EndPopup()
                }
                imgui.EndTabItem()
            }
            imgui.SetNextItemWidth(90)
            flag :imgui.TabItemFlags = {}
            if set_console_focus {
                flag = {imgui.TabItemFlags.SetSelected}
                set_console_focus = false
            }
            if imgui.BeginTabItem("Console", nil, flag) {
                if imgui.SmallButton("Clear") {
                    for text in console_output {
                        delete(text)
                    }
                    delete(console_output)
                    console_output = {}
                }
                for i := 0; i < len(console_output); i += 1 {
                    imgui.Text(strings.clone_to_cstring(console_output[i], context.temp_allocator))
                }
                imgui.EndTabItem()
            }
        }
        imgui.EndTabBar()
    }
    imgui.End()
}

save_callback :: proc "c" (userdata: rawptr, filelist: [^]cstring, filter: i32) {
    context = runtime.default_context()
    if filelist[0] == "" {
        return
    }
    meta_create_entity(string(filelist[0]))
}

selected_node: ^Folder_node

get_folder_path :: proc(node: ^Folder_node) -> string {
    if node.parent == nil {
        return string(node.name)
    }
    parent_path := get_folder_path(node.parent)
    return fmt.tprintf("%s\\%s", parent_path, node.name)
}

draw_folder_tree :: proc(node: ^Folder_node) {
    flags := imgui.TreeNodeFlags{.OpenOnArrow, .SpanLabelWidth}
    if len(node.children) == 0 {
        flags += {imgui.TreeNodeFlags.Leaf}
    }
    if node.selected {
        flags += {imgui.TreeNodeFlags.Selected}
    }
    is_open := imgui.TreeNodeEx(node.name, flags)
    if imgui.IsItemClicked(.Left) {
        if selected_node != nil {
            selected_node.selected = false
        }
        node.selected = true
        selected_node = node
        idx := strings.last_index(project_path, "\\")
        name, _ := strings.substring(project_path, 0, idx)
        delete(selected_folder)
        selected_folder = fmt.aprintf("%s\\%s", name, get_folder_path(node))
        build_asset_list(selected_folder)
        if len(assets_list) > 0 {
            selected_asset_idx = 0
            ext := os.ext(assets_list[0].path)
            switch ext {
            case ".png":
                sprite_props = meta_load_sprite(assets_list[0].path)
            case ".wav":
                audio_props = meta_load_audio(assets_list[0].path, true)
            case ".ent":
                entity_props = meta_load_entity(assets_list[0].path)
            }
        }
    }
    if is_open {
        for i := 0; i < len(node.children); i += 1 {
            node.children[i].parent = node
            draw_folder_tree(&node.children[i])
        }
        imgui.TreePop()
    }
}

draw_asset_items :: proc() {
    max_items := int(imgui.GetWindowWidth() / 100)
    for i := 0; i < len(assets_list); i += 1 {
        if assets_list[i].name == "" {
            continue
        }
        cursorPos := imgui.GetCursorPos()
        if imgui.Selectable(fmt.ctprintf("##%s", assets_list[i].name), i == selected_asset_idx, nil, imgui.Vec2{85, 70}) {
            selected_asset_idx = i
            selected_asset = &assets_list[i]
            switch selected_asset.type {
            case .Sprite:
                sprite_props = meta_load_sprite(assets_list[i].path)
            case .Sound:
                audio_props = meta_load_audio(assets_list[i].path, true)
            case .Entity:
                entity_props = meta_load_entity(assets_list[i].path)
            case .Script:
            case .Unknown:
                //Do nothing atm
            }
        }
        ratio := f32(assets_list[i].texture.size.x) / f32(assets_list[i].texture.size.y)
        if ratio > 1.0 {
            imgui.SetCursorPos({cursorPos.x + 17.5, cursorPos.y})
            imgui.Image(texture_to_image(assets_list[i].texture.texture), imgui.Vec2{50, 50 / ratio})
        } else {
            x_offset := (85 - (50 * ratio)) / 2
            imgui.SetCursorPos({cursorPos.x + x_offset, cursorPos.y})
            imgui.Image(texture_to_image(assets_list[i].texture.texture), imgui.Vec2{50 * ratio, 50})
        }

        imgui.SetCursorPos(imgui.Vec2{cursorPos.x, cursorPos.y + 50})
        pos := imgui.GetCursorScreenPos()
        imgui.RenderTextEllipsis(imgui.GetWindowDrawList(), pos, pos + imgui.Vec2{85, 20}, 50, assets_list[i].name, nil, nil)

        imgui.SetCursorPos(imgui.Vec2{cursorPos.x + 100, cursorPos.y})
        if i % max_items == max_items - 1 {
            imgui.SetCursorPos(imgui.Vec2{0, cursorPos.y + 80})
        }
    }
}

texture_to_image :: proc(tex: u32) -> imgui.TextureRef {
    ref: imgui.TextureRef
    ref._TexID = (imgui.TextureID(uintptr(textures[tex].texture)))
    return ref
}

ui_show_welcome :: proc() {
    imgui.SetNextWindowPos(viewport.Pos + viewport.Size / 2, .Always, imgui.Vec2{0.5, 0.5})
    imgui.SetNextWindowSize(imgui.Vec2{253, 75})
    if imgui.BeginPopupModal("Welcome", nil, window_flags) {
        if imgui.Button("New Project") {
            show_new_project = true
            imgui.CloseCurrentPopup()
        }
        imgui.SameLine(140, 0)
        if imgui.Button("Open Project") {
            show_open_project = true
            imgui.CloseCurrentPopup()
        }
        imgui.EndPopup()
    }
}

ui_draw_line :: proc(pos1: imgui.Vec2, pos2: imgui.Vec2) {
    draw_list := imgui.GetWindowDrawList()
    thickness: f32 = 2.0
    imgui.DrawList_AddLine(draw_list, pos1, pos2, 0xFF4c4542, thickness)
}

@(private="file")
new_project_name: [30]u8
@(private="file")
path_error: bool = false
@(private="file")
project_path: string = ""
@(private="file")
project_name: cstring

ui_show_new_project :: proc() {
    imgui.SetNextWindowPos(viewport.Pos + viewport.Size / 2, .Always, imgui.Vec2{0.5, 0.5})
    imgui.SetNextWindowSize(imgui.Vec2{300, 300})
    if imgui.BeginPopupModal("New Project", nil, window_flags) {
        imgui.Text("Project name:")
        if imgui.InputText("##ProjectName", cstring(&new_project_name[0]), len(new_project_name)) {
            base := os.dir(project_path)
            if(base != ".") {
                delete(project_path)
                project_path = fmt.aprintf("%s\\%s", base, cstring(&new_project_name[0]))
            }
        }
        imgui.Spacing()
        if imgui.Button("Select folder") {
            sdl.ShowOpenFolderDialog(load_callback, nil, nil, nil, false)
        }
        imgui.Text("Current path:")
        imgui.TextWrapped(strings.clone_to_cstring(project_path, context.temp_allocator))
        imgui.SetCursorPosY(230)
        if path_error {
            imgui.TextColored(imgui.Vec4{1, 0, 0, 1}, "Path already exists")
        } else {
            imgui.Text("")
        }
        if imgui.Button("Create project") {
            if project_path != "" {
                if os.exists(project_path) == true {
                    path_error = true
                } else {
                    path_error = false
                    err := os.make_directory(project_path)
                    if err != nil {
                        panic("Failed to create project directory.")
                    }
                    
                    src, _ := os.get_executable_directory(context.temp_allocator)
                    err = os.copy_directory_all(project_path, fmt.tprintf("%s\\resources", src))
                    if err != nil {
                        panic("Failed to copy resources.")
                    }

                    get_project_name()
                    file_path := fmt.tprintf("%s\\%s.2de", project_path, project_name)
                    fd, _ := os.open(file_path, os.O_WRONLY | os.O_CREATE)
                    os.write_string(fd, VERSION)
                    os.close(fd)
                    
                    create_folder_tree()
                    selected_node = &root_folder
                    recent_add(file_path)
                    delete(selected_folder)
                    selected_folder = strings.clone(project_path)
                    project_loaded = true
                    imgui.CloseCurrentPopup()
                }
            }
        }
        imgui.SameLine(140, 0)
        if imgui.Button("Back") {
            imgui.CloseCurrentPopup()
            show_welcome = true
        }
        
        imgui.EndPopup()
    }
}

load_callback :: proc "c" (userdata: rawptr, filelist: [^]cstring, filter: i32) {
    context = runtime.default_context()
    if filelist[0] == "" {
        return
    }
    delete(project_path)
    project_path = fmt.aprintf("%s\\%s", filelist[0], cstring(&new_project_name[0]))
}

ui_show_open_project :: proc() {
    imgui.SetNextWindowPos(viewport.Pos + viewport.Size / 2, .Always, imgui.Vec2{0.5, 0.5})
    imgui.SetNextWindowSize(imgui.Vec2{300, 300})
    if imgui.BeginPopupModal("Open Project", nil, window_flags) {
        if imgui.Button("Select project") {
            sdl.ShowOpenFileDialog(open_callback, nil, nil, &filter_2de, 1, nil, false)
        }
        imgui.SameLine(140, 0)
        if imgui.Button("Back") {
            imgui.CloseCurrentPopup()
            show_welcome = true
        }
        imgui.Spacing()
        imgui.Text("Recent:")
        for item in recent_list {
            if item.path != "" {
                if imgui.TextLink(strings.clone_to_cstring(os.base(item.path), context.temp_allocator)) {
                    open_project(item.path)
                }
                imgui.SetItemTooltip(fmt.ctprintf("%s\n%s", item.path, item.date))
            }
        }
        imgui.EndPopup()
    }
}

open_callback :: proc "c" (userdata: rawptr, filelist: [^]cstring, filter: i32) {
    context = runtime.default_context()
    if filelist[0] == "" {
        return
    }
    open_project(string(filelist[0]))
}

open_project :: proc(path: string) {
    if !os.exists(path) {
        file_not_found = path
        return
    }
    //show_working = true
    project_path = os.dir(path)
    get_project_name()
    create_folder_tree()
    selected_node = &root_folder

    idx := strings.last_index(project_path, "\\")
    name, _ := strings.substring(project_path, 0, idx)
    build_asset_list(name)

    err: fsw.Error
    file_watcher, err = fsw.watch_dir_recursive(project_path)
    assert(err == nil)

    recent_add(path)
    delete(selected_folder)
    selected_folder = strings.clone(project_path)
    show_working = false
    imgui.ClosePopupToLevel(0, true)
    project_loaded = true
}

ui_show_working :: proc() {
    imgui.SetNextWindowPos(viewport.Pos + viewport.Size / 2, .Always, imgui.Vec2{0.5, 0.5})
    imgui.SetNextWindowSize(imgui.Vec2{300, 100})
    if imgui.BeginPopupModal("Working", nil, window_flags) {
        imgui.Text("Please wait...")
        imgui.EndPopup()
    }
}

ui_show_file_not_found :: proc() {
    imgui.SetNextWindowPos(viewport.Pos + viewport.Size / 2, .Always, imgui.Vec2{0.5, 0.5})
    imgui.SetNextWindowSize(imgui.Vec2{300, 100})
    if imgui.BeginPopupModal("File not found", nil, window_flags) {
        imgui.TextWrapped("The file you are trying to open does not exist and will be removed.")
        if imgui.Button("OK") {
            for i := 0; i < len(recent_list); i += 1 {
                if recent_list[i].path == file_not_found {
                    copy(recent_list[i:], recent_list[i + 1:])
                    recent_write()
                    break
                }
            }
            file_not_found = ""
            imgui.CloseCurrentPopup()
            show_open_project = true
        }
        imgui.EndPopup()
    }
}

create_folder_tree :: proc() {
    root_folder.name = project_name
    root_folder.selected = true
    root_folder.parent = nil
    clean_folder(&root_folder)
    clear(&root_folder.children)
    scan_folder(project_path, &root_folder)
}

get_project_name :: proc() {
    idx := strings.last_index(project_path, "\\")
    name, _ := strings.substring(project_path, idx + 1, len(project_path))
    delete(project_name)
    project_name = strings.clone_to_cstring(name)
    sdl.SetWindowTitle(window, fmt.ctprintf("2d engine - %s", project_name))
}

scan_folder :: proc(path: string, node: ^Folder_node) {
    fd, _ := os.open(path)
    info, _ := os.read_dir(fd, -1, context.temp_allocator)
    length := len(info)

    for i := 0; i < length; i += 1 {
        if info[i].type == os.File_Type.Directory && strings.starts_with(info[i].name, ".") == false {
            node2: Folder_node
            node2.name = strings.clone_to_cstring(info[i].name)
            node2.parent = node
            scan_folder(fmt.tprintf("%s\\%s", path, info[i].name), &node2)
            append(&node.children, node2)
        } else if info[i].type == os.File_Type.Regular {
            ext := os.ext(info[i].name)
            switch ext {
            case ".png":
                meta_create_sprite(info[i].fullpath)
                name := strings.clone_to_cstring(os.short_stem(info[i].fullpath))
                item: Asset_list_item= {strings.clone(info[i].fullpath), name}
                append(&full_assets_list.textures, item)
            case ".wav":
                meta_create_audio(info[i].fullpath)
                append(&full_assets_list.audio, strings.clone(info[i].fullpath))
            case ".odin":
                file_name := os.short_stem(info[i].fullpath)
                name: cstring
                list: [dynamic]cstring
                append(&list, strings.clone_to_cstring("None"))
                if strings.starts_with(file_name, "e2d") {
                    name = strings.clone_to_cstring("")
                } else {
                    name = strings.clone_to_cstring(file_name)
                    data, _ := os.read_entire_file(info[i].fullpath, context.temp_allocator)
                    it := string(data)
                    for line in strings.split_lines_iterator(&it) {
                        if strings.contains(line, " :: proc(") {
                            if strings.starts_with(line, "/*") || strings.starts_with(line, "//") {
                                continue
                            }
                            substr, _ := strings.substring(line, 0, strings.index(line, " "))
                            append(&list, strings.clone_to_cstring(substr))
                        }  
                    }
                }
                item: Asset_list_script = {strings.clone(info[i].fullpath), name, list}
                append(&full_assets_list.scripts, item)
            case ".ent":
                append(&full_assets_list.entities, strings.clone(info[i].fullpath))
            }
        }
    }
    os.close(fd)
}

clean_folder :: proc(node: ^Folder_node) {
    for i := 0; i < len(node.children); i += 1 {
        clean_folder(&node.children[i])
        delete(node.children[i].name)
    }
    if node.children != nil {
        delete(node.children)
    }
}

folder_add :: proc(path: string, name: string, node: ^Folder_node) -> bool {
    if string(node.name) == path {
        node2: Folder_node
        node2.name = strings.clone_to_cstring(name)
        node2.parent = node
        append(&node.children, node2)
        return true
    }

    for &child in node.children {
        if folder_add(path, name, &child) {
            return true
        }
    }
    return false
}

folder_remove :: proc(path: string, node: ^Folder_node) -> bool {
    if string(node.name) == path {
        delete(node.name)
        return true
    }

    for i := len(node.children) - 1; i >= 0; i -= 1 {
        if folder_remove(path, &node.children[i]) {
            unordered_remove(&node.children, i)
            return true
        }
    }
    return false
}

folder_rename :: proc(path: string, new_name: string, node: ^Folder_node) -> bool {
    if string(node.name) == path {
        delete(node.name)
        node.name = strings.clone_to_cstring(new_name)
        return true
    }

    for &child in node.children {
        if folder_rename(path, new_name, &child) {
            return true
        }
    }
    return false
}

rebuild_asset_list :: proc() {
    if selected_folder != "" {
        build_asset_list(selected_folder)
    }
}

build_asset_list :: proc(path: string) {
    for i := len(assets_list) - 1; i >= 0; i -= 1 {
        if assets_list[i].type == .Sprite {
            texture_destroy(assets_list[i].texture.texture)
            unordered_remove(&textures, assets_list[i].texture.texture)
        }
        delete(assets_list[i].name)
        delete(assets_list[i].path)
    }
    delete(assets_list)
    assets_list = {}
    selected_asset = nil

    if !os.exists(path) {
        return
    }
    fd, _ := os.open(path)
    info, _ := os.read_dir(fd, -1, context.temp_allocator)
    length := len(info)
    for i := 0; i < length; i += 1 {
        if info[i].type != os.File_Type.Regular {
            continue
        }
        ext := os.ext(info[i].name)
        switch ext {
        case ".png":
            asset: Asset
            asset.name = strings.clone_to_cstring(info[i].name)
            asset.texture.texture, asset.texture.size = texture_from_name(info[i].fullpath)
            asset.type = .Sprite
            asset.path = strings.clone(info[i].fullpath)
            append(&assets_list, asset)
        case ".wav":
            asset: Asset
            asset.name = strings.clone_to_cstring(info[i].name)
            asset.texture.texture = audio_texture
            asset.texture.size = {50, 50}
            asset.type = .Sound
            asset.path = strings.clone(info[i].fullpath)
            append(&assets_list, asset)
        case ".odin":
            asset: Asset
            asset.name = strings.clone_to_cstring(info[i].name)
            asset.texture.texture = odin_texture
            asset.texture.size = {50, 50}
            asset.type = .Script
            asset.path = strings.clone(info[i].fullpath)
            append(&assets_list, asset)
        case ".ent":
            asset: Asset
            asset.name = strings.clone_to_cstring(info[i].name)
            asset.texture.texture = entity_texture
            asset.texture.size = {50, 50}
            asset.type = .Entity
            asset.path = strings.clone(info[i].fullpath)
            append(&assets_list, asset)
        }
    }
    if len(assets_list) > 0 {
        selected_asset = &assets_list[0]
    }   
}

build_assets :: proc() {
    file_path := fmt.tprintf("%s\\source\\e2d_resources.odin", project_path)
    sprites_count := 1
    tilemaps_count := 1
    fonts_count := 1
    sounds_count := 1
    sprite_map: map[cstring]int
    tilemap_map: map[string]int
    font_map: map[string]int
    sound_map: map[string]int

    fd, _ := os.open(file_path, os.O_WRONLY | os.O_CREATE | os.O_TRUNC)
    os.write_string(fd, "#+feature dynamic-literals\n")
    os.write_string(fd, "package main\n\nload_textures :: proc() {\n")
    for i := 0; i < len(full_assets_list.textures); i += 1 {
        meta := meta_load_sprite(full_assets_list.textures[i].path)
        path, _ := os.get_relative_path(project_path, full_assets_list.textures[i].path, context.temp_allocator)
        path, _ = strings.replace(path, "\\", "/", -1, context.temp_allocator)
        switch meta.type {
        case .Sprite:
            os.write_string(fd, fmt.tprintf("\tsprites[%d] = sprite_create(#load(\"../%s\"), {{%d, %d}})\n", sprites_count - 1, path, meta.frames[0], meta.frames[1]))
            if meta.is_slice9 {
                os.write_string(fd, fmt.tprintf("\tsprites[%d].slice9 = {{%d, %d, %d, %d}}\n", sprites_count - 1, meta.slice9[0], meta.slice9[1], meta.slice9[2], meta.slice9[3]))
            }
            sprite_map[full_assets_list.textures[i].name] = sprites_count - 1
            sprites_count += 1
        case .Tilemap:
            os.write_string(fd, fmt.tprintf("\ttilemaps[%d] = tilemap_load_tileset(#load(\"../%s\"))\n", tilemaps_count - 1, path))
            tilemap_map[os.short_stem(path)] = tilemaps_count - 1
            tilemaps_count += 1
        case .Font:
            os.write_string(fd, fmt.tprintf("\tfonts[%d] = font_create(#load(\"../%s\"), {{%d, %d}})\n", fonts_count - 1, path, meta.frames[0], meta.frames[1]))
            font_map[os.short_stem(path)] = fonts_count - 1
            fonts_count += 1
        }
    }
    os.write_string(fd, "}\n\n")

    os.write_string(fd, "load_audio :: proc() {\n")
    for i := 0; i < len(full_assets_list.audio); i += 1 {
        meta := meta_load_audio(full_assets_list.audio[i], false)
        path, _ := os.get_relative_path(project_path, full_assets_list.audio[i], context.temp_allocator)
        path, _ = strings.replace(path, "\\", "/", -1, context.temp_allocator)
        os.write_string(fd, fmt.tprintf("\tsounds[%d] = audio_create_sound(#load(\"../%s\"), %t)\n", sounds_count - 1, path, meta.preload))
        sound_map[os.short_stem(path)] = sounds_count - 1
        sounds_count += 1
    }
    os.write_string(fd, "}\n\n")

    os.write_string(fd, fmt.tprintf("sprite_map := map[string]int {{\n"))
    for key, value in sprite_map {
        os.write_string(fd, fmt.tprintf("\t\"%s\" = %d,\n", key, value))
    }
    os.write_string(fd, fmt.tprintf("}}\n"))

    os.write_string(fd, fmt.tprintf("tilemap_map := map[string]int {{\n"))
    for key, value in tilemap_map {
        os.write_string(fd, fmt.tprintf("\t\"%s\" = %d,\n", key, value))
    }
    os.write_string(fd, fmt.tprintf("}}\n"))

    os.write_string(fd, fmt.tprintf("font_map := map[string]int {{\n"))
    for key, value in font_map {
        os.write_string(fd, fmt.tprintf("\t\"%s\" = %d,\n", key, value))
    }
    os.write_string(fd, fmt.tprintf("}}\n\n"))

    os.write_string(fd, fmt.tprintf("sound_map := map[string]int {{\n"))
    for key, value in sound_map {
        os.write_string(fd, fmt.tprintf("\t\"%s\" = %d,\n", key, value))
    }
    os.write_string(fd, fmt.tprintf("}}\n\n"))

    os.write_string(fd, fmt.tprintf("TILEMAP_COUNT :: %d\n", tilemaps_count))
    os.write_string(fd, fmt.tprintf("SPRITE_COUNT :: %d\n", sprites_count))
    os.write_string(fd, fmt.tprintf("FONT_COUNT :: %d\n", fonts_count))
    os.write_string(fd, fmt.tprintf("SOUND_COUNT :: %d\n", sounds_count))
    os.close(fd)
    delete(sprite_map)
    delete(tilemap_map)
    delete(font_map)
    delete(sound_map)
}

add_asset :: proc(path: string, ext: string) {
    switch ext {
    case ".png":    
        append(&full_assets_list.textures, Asset_list_item{strings.clone(path), strings.clone_to_cstring(os.short_stem(path))})
    case ".wav":
        append(&full_assets_list.audio, strings.clone(path))
    case ".odin":
        append(&full_assets_list.scripts, Asset_list_script{strings.clone(path), strings.clone_to_cstring(os.short_stem(path)), {}})
    case ".ent":
        append(&full_assets_list.entities, strings.clone(path))
    }
}

remove_asset :: proc(path: string, ext: string) {
    for i := 0; i < len(full_assets_list.textures); i += 1 {
        if full_assets_list.textures[i].path == path {
            switch ext {
            case ".png":
                unordered_remove(&full_assets_list.textures, i)
            case ".wav":
                unordered_remove(&full_assets_list.audio, i)
            case ".odin":
                unordered_remove(&full_assets_list.scripts, i)
            case ".ent":
                unordered_remove(&full_assets_list.entities, i)
            }
            break
        }
    }
}