package main

import "core:fmt"
import sdl "vendor:sdl3"
import mix "vendor:sdl3/mixer"

sounds: [SOUND_COUNT]^mix.Track
mixer: ^mix.Mixer

audio_init :: proc() {
    if !mix.Init() {
        panic("SDL3 mixer init failed")
    }
    mixer = mix.CreateMixerDevice(sdl.AUDIO_DEVICE_DEFAULT_PLAYBACK, nil)
    if mixer == nil {
        panic("SDL3 mixer device creation failed")
    }
}

audio_exit :: proc() {
    mix.Quit()
}

audio_create_sound :: proc(path: cstring, decompress: bool) -> ^mix.Track {
    audio := mix.LoadAudio(mixer, path, decompress)
    track := mix.CreateTrack(mixer)
    assert(track != nil, "Couldn't create a mixer track")
    if !mix.SetTrackAudio(track, audio) {
        panic("Couldn't set track audio")
    }
    return track
}

audio_play_sound :: proc(idx: int, loop: bool) {
    options := sdl.CreateProperties()
    if loop {
        sdl.SetNumberProperty(options, mix.PROP_PLAY_LOOPS_NUMBER, -1)
    }
    if (!mix.PlayTrack(sounds[idx], options)) {
        panic("Couldn't play sound")
    }
}

audio_stop_sound :: proc(idx: int) {
    if (!mix.StopTrack(sounds[idx], 0)) {
        panic("Couldn't stop sound")
    }
}

audio_stop_all :: proc() {
    if (!mix.StopAllTracks(mixer, 0)) {
        panic("Couldn't stop all sounds")
    }
}

audio_pause_all :: proc(pause: bool) {
    if pause {
        if (!mix.PauseAllTracks(mixer)) {
            panic("Couldn't pause all sounds")
        }
    } else {
        if (!mix.ResumeAllTracks(mixer)) {
            panic("Couldn't resume all sounds")
        }
    }
}

audio_set_volume :: proc(volume: f32) {
    if (!mix.SetMixerGain(mixer, volume)) {
        panic("Couldn't set sound volume")
    }
}
