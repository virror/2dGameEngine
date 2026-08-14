package main

import "core:fmt"
import "core:os"
import "core:strings"
import "core:strconv"
import "core:encoding/ini"
import sdl "vendor:sdl3"
import mix "vendor:sdl3/mixer"

Sprite_props :: struct {
    type: Sprite_type,
    frames: [2]i32,
    slice9: [4]i32,
    is_slice9: bool,
}

Audio_props :: struct {
    preload: bool,
    duration: string,
    channels: i32,
    sample_rate: i32,
}

Entity_props :: struct {
    sprite: cstring,
    collider: [4]i32,
    mass: f32,
    friction: f32,
    bounciness: f32,
    trigger: bool,
    no_gravity: bool,
    script_file1: cstring,
    script_file2: cstring,
    script_file3: cstring,
    update: cstring,
    on_collide_entity: cstring,
    on_collide_tile: cstring,
}

meta_create_sprite :: proc(asset: string) {
    path := fmt.tprintf("%s.meta", asset)
    if !os.exists(path) {
        fd, err := os.create(path)
        defer os.close(fd)
        if err != nil {
            panic(fmt.tprintf("Failed to create sprite %s.", path))
        }
        
        writer := os.to_writer(fd)
        ini.write_pair(writer, "type", int(Sprite_type.Sprite))
        ini.write_pair(writer, "frames", [2]i32{1, 1})
        ini.write_pair(writer, "slice9", [4]i32{0, 0, 0, 0})
    }
}

meta_save_sprite :: proc(asset: string, props: Sprite_props) {
    path := fmt.tprintf("%s.meta", asset)
    fd, err := os.open(path, os.O_WRONLY)
    defer os.close(fd)
    if err != nil {
        panic(fmt.tprintf("Failed to open sprite meta %s.", path))
    }
    writer := os.to_writer(fd)
    ini.write_pair(writer, "type", i32(props.type))
    ini.write_pair(writer, "frames", props.frames)
    ini.write_pair(writer, "slice9", props.slice9)
}

meta_load_sprite :: proc(asset: string) -> Sprite_props {
    path := fmt.tprintf("%s.meta", asset)
    if !os.exists(path) {
        panic(fmt.tprintf("Sprite %s does not exist.", path))
    }
    fd, err := os.open(path)
    defer os.close(fd)
    if err != nil {
        panic(fmt.tprintf("Failed to open sprite %s.", path))
    }
    
    props: Sprite_props
    ini_map, _, _ := ini.load_map_from_path(path, context.temp_allocator)
    props.type = string_to_type(ini_map[""]["type"])
    props.frames = string_to_i32_2(ini_map[""]["frames"])
    props.slice9 = string_to_i32_4(ini_map[""]["slice9"])
    props.is_slice9 = props.slice9 != [4]i32{0, 0, 0, 0}
    return props
}

meta_create_audio :: proc(asset: string) {
    path := fmt.tprintf("%s.meta", asset)
    if !os.exists(path) {
        fd, err := os.create(path)
        defer os.close(fd)
        if err != nil {
            panic(fmt.tprintf("Failed to create audio %s.", path))
        }
        
        writer := os.to_writer(fd)
        ini.write_pair(writer, "preload", false)
    }
}

meta_save_audio :: proc(asset: string, props: Audio_props) {
    path := fmt.tprintf("%s.meta", asset)
    fd, err := os.open(path, os.O_WRONLY)
    defer os.close(fd)
    if err != nil {
        panic(fmt.tprintf("Failed to open audio meta %s.", path))
    }
    writer := os.to_writer(fd)
    ini.write_pair(writer, "preload", props.preload)
}

meta_load_audio :: proc(asset: string, load_audio_data: bool) -> Audio_props {
    path := fmt.tprintf("%s.meta", asset)
    if !os.exists(path) {
        panic(fmt.tprintf("Audio %s does not exist.", path))
    }
    fd, err := os.open(path)
    defer os.close(fd)
    if err != nil {
        panic(fmt.tprintf("Failed to open audio %s.", path))
    }

    props: Audio_props
    ini_map, _, _ := ini.load_map_from_path(path, context.temp_allocator)
    props.preload, _ = strconv.parse_bool(ini_map[""]["preload"])

    if load_audio_data {
        delete(props.duration)
        get_audio_data(asset, &props)
    }
    return props
}

get_audio_data :: proc(path: string, props: ^Audio_props) {
    mix.DestroyAudio(mix.GetTrackAudio(loaded_track))
    audio := mix.LoadAudio(mixer, strings.clone_to_cstring(path, context.temp_allocator), false)
    loaded_track = mix.CreateTrack(mixer)
    if !mix.SetTrackAudio(loaded_track, audio) {
        panic("Failed to set track audio.")
    }
    spec: sdl.AudioSpec
    if !mix.GetAudioFormat(audio, &spec) {
        panic("Failed to get audio format.")
    }

    total_seconds := mix.AudioFramesToMS(audio, mix.GetAudioDuration(audio))
    minutes := total_seconds / 1000 / 60
    seconds := total_seconds / 1000 % 60
    props.duration = fmt.aprintf("%02d:%02d.%03d", minutes, seconds, total_seconds % 1000)
    props.channels = spec.channels
    props.sample_rate = spec.freq
}

meta_create_entity :: proc(path: string) {
    if !os.exists(path) {
        fd, err := os.create(path)
        defer os.close(fd)
        if err != nil {
            panic(fmt.tprintf("Failed to create entity %s.", path))
        }
        
        writer := os.to_writer(fd)
        ini.write_pair(writer, "sprite", "")
        ini.write_pair(writer, "collider", [4]i32{0, 1, 0, 1})
        ini.write_pair(writer, "mass", 1.0)
        ini.write_pair(writer, "friction", 0.0)
        ini.write_pair(writer, "bounciness", 0.0)
        ini.write_pair(writer, "trigger", false)
        ini.write_pair(writer, "no_gravity", false)

        ini.write_pair(writer, "script_file1", "None")
        ini.write_pair(writer, "script_file2", "None")
        ini.write_pair(writer, "script_file3", "None")
        ini.write_pair(writer, "update", "None")
        ini.write_pair(writer, "on_collide_entity", "None")
        ini.write_pair(writer, "on_collide_tile", "None")
    }
}

meta_save_entity :: proc(path: string, props: Entity_props) {
    fd, err := os.open(path, os.O_WRONLY)
    defer os.close(fd)
    if err != nil {
        panic(fmt.tprintf("Failed to open entity %s.", path))
    }
    writer := os.to_writer(fd)
    ini.write_pair(writer, "sprite", props.sprite)
    ini.write_pair(writer, "collider", props.collider)
    ini.write_pair(writer, "mass", props.mass)
    ini.write_pair(writer, "friction", props.friction)
    ini.write_pair(writer, "bounciness", props.bounciness)
    ini.write_pair(writer, "trigger", props.trigger)
    ini.write_pair(writer, "no_gravity", props.no_gravity)

    ini.write_pair(writer, "script_file1", props.script_file1)
    ini.write_pair(writer, "script_file2", props.script_file2)
    ini.write_pair(writer, "script_file3", props.script_file3)
    ini.write_pair(writer, "update", props.update)
    ini.write_pair(writer, "on_collide_entity", props.on_collide_entity)
    ini.write_pair(writer, "on_collide_tile", props.on_collide_tile)
}

meta_load_entity :: proc(path: string) -> Entity_props {
    if !os.exists(path) {
        panic(fmt.tprintf("Entity %s does not exist.", path))
    }
    fd, err := os.open(path)
    defer os.close(fd)
    if err != nil {
        panic(fmt.tprintf("Failed to open entity %s.", path))
    }

    delete(entity_props.sprite)
    delete(entity_props.script_file1)
    delete(entity_props.script_file2)
    delete(entity_props.script_file3)
    delete(entity_props.update)
    delete(entity_props.on_collide_entity)
    delete(entity_props.on_collide_tile)

    props: Entity_props
    ini_map, _, _ := ini.load_map_from_path(path, context.temp_allocator)
    props.sprite = strings.clone_to_cstring(ini_map[""]["sprite"])
    props.collider = string_to_i32_4(ini_map[""]["collider"])
    props.mass, _ = strconv.parse_f32(ini_map[""]["mass"])
    props.friction, _ = strconv.parse_f32(ini_map[""]["friction"])
    props.bounciness, _ = strconv.parse_f32(ini_map[""]["bounciness"])
    props.trigger, _ = strconv.parse_bool(ini_map[""]["trigger"])
    props.no_gravity, _ = strconv.parse_bool(ini_map[""]["no_gravity"])

    props.script_file1 = strings.clone_to_cstring(ini_map[""]["script_file1"])
    props.script_file2 = strings.clone_to_cstring(ini_map[""]["script_file2"])
    props.script_file3 = strings.clone_to_cstring(ini_map[""]["script_file3"])
    props.update = strings.clone_to_cstring(ini_map[""]["update"])
    props.on_collide_entity = strings.clone_to_cstring(ini_map[""]["on_collide_entity"])
    props.on_collide_tile = strings.clone_to_cstring(ini_map[""]["on_collide_tile"])

    for i := 0; i < len(full_assets_list.scripts); i += 1 {
        if props.script_file1 == full_assets_list.scripts[i].name {
            script_idx1 = i
        }
        if props.script_file2 == full_assets_list.scripts[i].name {
            script_idx2 = i
        }
        if props.script_file3 == full_assets_list.scripts[i].name {
            script_idx3 = i
        }
    }
    return props
}

string_to_i32_2 :: proc(value: string) -> [2]i32 {
    val := strings.trim(value, "[]")
    parts := strings.split(val, ", ", context.temp_allocator)
    intval1, _ := strconv.parse_int(parts[0])
    intval2, _ := strconv.parse_int(parts[1])
    return [2]i32{i32(intval1), i32(intval2)}
}

string_to_i32_4 :: proc(value: string) -> [4]i32 {
    val := strings.trim(value, "[]")
    parts := strings.split(val, ", ", context.temp_allocator)
    intval1, _ := strconv.parse_int(parts[0])
    intval2, _ := strconv.parse_int(parts[1])
    intval3, _ := strconv.parse_int(parts[2])
    intval4, _ := strconv.parse_int(parts[3])
    return [4]i32{i32(intval1), i32(intval2), i32(intval3), i32(intval4)}
}

string_to_f32_4 :: proc(value: string) -> [4]f32 {
    val := strings.trim(value, "[]")
    parts := strings.split(val, ", ", context.temp_allocator)
    float1, _ := strconv.parse_f32(parts[0])
    float2, _ := strconv.parse_f32(parts[1])
    float3, _ := strconv.parse_f32(parts[2])
    float4, _ := strconv.parse_f32(parts[3])
    return [4]f32{float1, float2, float3, float4}
}

string_to_type :: proc(value: string) -> Sprite_type {
    switch value {
    case "0":
        return .Sprite
    case "1":
        return .Tilemap
    case "2":
        return .Font
    }
    return .Sprite
}