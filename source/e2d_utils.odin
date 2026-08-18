package main

import "core:fmt"

Vector2 :: distinct [2]f32
Vector4 :: distinct [4]f32

mouse_to_pos :: proc() -> Vector2 {
    ratio := resolution.y / WIN_HEIGHT
    cam_pos := render_get_camera()
    return (((mouse_state.position - resolution / 2) / ratio) + cam_pos) / QUAD_SIZE
}

pos_to_screen :: proc(world_pos: Vector2) -> Vector2 {
    ratio := resolution.y / WIN_HEIGHT
    adjust :Vector2= {resolution.x / ratio, WIN_HEIGHT} / 2
    cam_pos := render_get_camera()
    return (((world_pos * QUAD_SIZE - cam_pos)) + adjust)
}

is_inside_screen :: proc(pos: Vector2, size: Vector2) -> bool {
    screen_size :Vector2= {resolution.x / QUAD_SIZE / 2, resolution.y / QUAD_SIZE / 2}
    cam := render_get_camera() / QUAD_SIZE
    size1 :=size / QUAD_SIZE
    return pos.x > cam.x - screen_size.x - size1.x && pos.x < cam.x + screen_size.x &&
           pos.y > cam.y - screen_size.y - size1.y && pos.y < cam.y + screen_size.y
}

get_screen_size :: proc() -> (Vector2) {
    return {resolution.x / QUAD_SIZE, resolution.y / QUAD_SIZE}
}