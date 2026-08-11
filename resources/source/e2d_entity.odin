package main

import "core:fmt"
import "core:mem"
import "core:math"

ENTITY_COUNT :: 150
ANIMATION_FRAME_TIME :: 0.125

EntityType :: enum {
    empty,
    player,
}

EntityTag :: enum {
    none,
    player,
}

Entity :: struct {
    type: EntityType,
    tag: EntityTag,
    sprite: Sprite,
    position: Vector2,
    velocity: Vector2,
    size: Vector2,
    anim: Animation,
    flip: Vector2,
    physics: Physics,
    background: bool,
    
    update: proc(self: ^Entity, dt: f32),
    on_collide_entity: proc(self: ^Entity, other: ^Entity),
    on_collide_tile: proc(self: ^Entity, collide_info: Vector2),
    marked_for_destruction: bool,
}

Animation :: struct {
    time: f32,
    loop: bool,
    running: bool,
    clip: f32,
}

Physics :: struct {
    collider: Rect,
    mass: f32,
    friction: f32,
    bounciness: f32,
    trigger: bool,
    no_gravity: bool,
}

EntityId :: distinct u64

entities: [ENTITY_COUNT]Entity

entity_spawn :: proc() -> ^Entity {
    entity: ^Entity
    // NOTE: Linear search, not ideal
    for &e, i in entities {
        if e.type == .empty {
            entity = &entities[i]
            break
        }
    }
    assert(entity != nil)
    return entity
}

entity_destroy :: proc(entity: ^Entity) {
    entity.marked_for_destruction = true
}

// For internal use. Not an API, hence the name.
actually_destroy_entity :: proc(entity: ^Entity) {
    index := mem.ptr_sub(entity, &entities[0])
    entities[index] = {}
}

entity_init :: proc(entity: ^Entity, e_type: EntityType, pos: Vector2, sprite_id: i32) {
    // Derive size from sprite
    sprite := sprites[sprite_id]

    entity^ = {
        sprite = sprite,
        size = sprite.size / sprite.frames,
        position = pos,
        type = e_type,
    }
}

entity_animate :: proc(entity: ^Entity, time_delta: f32) {
    if(entity.anim.running) {
        entity.anim.time += time_delta / ANIMATION_FRAME_TIME
        frame_x := entity.sprite.frames.x
        if entity.anim.time > frame_x && !entity.anim.loop{
            entity.anim.running = false
            entity.sprite.offset = {entity.sprite.frames.x - 1, entity.anim.clip}
        }
    }
}

entity_anim_run :: proc(entity: ^Entity, clip: f32, loop: bool) {
    if clip < entity.sprite.frames.y {
        entity.anim.clip = clip
        entity.anim.time = 0
        entity.anim.running = true
        entity.anim.loop = loop
    }
}

entity_anim_stop :: proc(entity: ^Entity) {
    entity.anim.running = false
}

entity_hitbox :: proc(entity: ^Entity) -> Rect {
    return rect_offset(entity.physics.collider, entity.position)
}

entity_collide_point :: proc(point: Vector2) -> ^Entity {
    for &e in entities {
        if e.type != .empty {
            rect := entity_hitbox(&e)
            if point.x > rect.left && point.x < rect.right &&
               point.y > rect.bottom && point.y < rect.top {
                return &e
            }
        }
    }
    return nil
}

entity_exists_point :: proc(point: Vector2) -> ^Entity {
    for &e in entities {
        if e.type != .empty {
            size :Rect= {0, e.size.y / QUAD_SIZE, 0, e.size.x / QUAD_SIZE}
            rect := rect_offset(size, e.position)
            if point.x > rect.left && point.x < rect.right &&
               point.y > rect.bottom && point.y < rect.top {
                return &e
            }
        }
    }
    return nil
}

entity_overlap_tile :: proc(entity: ^Entity) -> bool {
    rect := entity_hitbox(entity)
    xs := int(rect.left)
    xe := int(rect.right)
    ys := int(rect.bottom)
    ye := int(rect.top)

    for y in ys..=ye {
        for x in xs..=xe {
            if !tilemap_get_tile(x, y).walkable {
                return true
            }
        }
    }
    return false
}

entity_render :: proc(entity: ^Entity) {
    offset: Vector2
    
    if entity.anim.running {
        frame_x := entity.sprite.frames.x
        anim_frame := i32(entity.anim.time) % i32(frame_x)
        offset_y := ((entity.sprite.frames.y - entity.anim.clip) / entity.sprite.frames.y)
        offset = {(f32(anim_frame) / frame_x), 1 - offset_y}
    } else {
        offset_y := ((entity.sprite.frames.y - entity.sprite.offset.y) / entity.sprite.frames.y)
        offset = {entity.sprite.offset.x / entity.sprite.frames.x, 1 - offset_y}
    }

    if is_inside_screen(entity.position, entity.size) {
        render_quad({
            texture = entity.sprite.texture,
            position = QUAD_SIZE * entity.position,
            size = entity.size,
            scale = 1 / entity.sprite.frames,
            offset = offset,
            flip = entity.flip,
            color = entity.sprite.color,
            slice9 = entity.sprite.slice9,
            tex_size = {0, 0},
        },)
    }
}

entity_verify :: proc(entity: ^Entity) {
    assert(entity.physics.collider.bottom < entity.physics.collider.top)
    assert(entity.physics.collider.left < entity.physics.collider.right)

    assert(entity.physics.friction >= 0)
    assert(entity.physics.bounciness >= 0)
    assert(entity.physics.bounciness <= 1)
}

entity_clear_all :: proc() {
    entities = {}
}

entity_center :: proc(entity: ^Entity) -> Vector2 {
    return entity.position + entity.size / QUAD_SIZE / 2
}

entity_distance :: proc(entity1: ^Entity, entity2: ^Entity) -> (f32, Vector2) {
    center1 :Vector2 = entity_center(entity1)
    center2 :Vector2 = entity_center(entity2)
    center_dir := center1 - center2
    return math.sqrt_f32(center_dir.x * center_dir.x + center_dir.y * center_dir.y), center_dir
}

entity_create :: proc(type: EntityType, pos: Vector2) -> ^Entity {
    e: ^Entity
    if type != .empty {
        e = entity_spawn()
    }
    switch type {
    case .empty:
        //Ignore
    case .player:
        player_init(e, pos)
    }
    return e
}

Sprite :: struct {
    texture: u32,
    size: Vector2,
    frames: Vector2,
    offset: Vector2,
    slice9: Vector4,
    color: Vector4,
}

sprites: [SPRITE_COUNT]Sprite

sprite_create :: proc(data: []u8, frames: Vector2) -> Sprite {
    texture, size := texture_create(data)
    return Sprite{texture, size, frames, {0, 0}, {0, 0, 0, 0}, COLOR_WHITE}
}

sprite_destroy :: proc(sprite: ^Sprite) {
    texture_destroy(sprite.texture)
}

sprite_destroy_all :: proc() {
    for i in 0..<len(sprites) {
        sprite_destroy(&sprites[i])
    }
}