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
    apa: bool,
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
    props.preload = string_to_bool(ini_map[""]["preload"])

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

meta_create_entity :: proc(asset: string) {
}

meta_save_entity :: proc(asset: string, props: Entity_props) {
}

meta_load_entity :: proc(asset: string) -> Entity_props {
    props: Entity_props
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

string_to_bool :: proc(value: string) -> bool {
    switch value {
    case "true":
        return true
    case "false":
        return false
    }
    return false
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