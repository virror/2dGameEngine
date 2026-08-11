package main

import "core:math"
import "core:math/linalg"
import "core:fmt"

USE_GRAVITY :: false
GRAVITY :: 9.8

Rect :: struct {
    bottom: f32,
    top: f32,
    left: f32,
    right: f32,
}

gravity :f32= GRAVITY

@(private="file")
rect_offset_vec2 :: proc(rect: Rect, offset: Vector2) -> Rect {
    return rect_offset_xy(rect, offset.x, offset.y)
}

@(private="file")
rect_offset_xy :: proc(rect: Rect, x: f32 = 0, y: f32 = 0) -> Rect {
    return {
        top = rect.top + y,
        right = rect.right + x,
        bottom = rect.bottom + y,
        left = rect.left + x,
    }
}

rect_offset :: proc{rect_offset_vec2, rect_offset_xy}

@(private="file")
rect_overlap :: proc(a: Rect, b: Rect) -> (bool, Vector4) {
    x := a.right - b.left
    y := b.right - a.left
    z := a.top - b.bottom
    w := b.top - a.bottom
    if x > 0 && y > 0 && z > 0 && w > 0 {
        return true, {x, y, z, w}
    }
    return false, {0, 0, 0, 0}
}

collide_tiles :: proc(e: ^Entity, time_delta:f32) {
    move := time_delta * e.velocity
    hitbox := entity_hitbox(e)
    collide_info: Vector2
    // Repeat at most two times until move is spent
    for tries_left := 2; linalg.vector_length(move) > 0 && tries_left > 0; tries_left -= 1 {
        // Does the new position cause a collision?
        if collides_with_tiles(rect_offset(hitbox, move)) {
            // Nudge forward along move vector in small steps the collision is found
            step := move / linalg.vector_length(move) / 64.0
            partial: Vector2 = {0, 0}
            for !collides_with_tiles(rect_offset(hitbox, partial + step)) {
                partial += step
            }
            // Spend part of the move
            e.position += partial
            move -= partial
            // Stop velocity and movement in any blocked axis
            // TODO: Fix subtle bug when hitting a corner
            hitbox = entity_hitbox(e)
            if collides_with_tiles(rect_offset(rect = hitbox, x = math.sign(e.velocity.x) * 1/32.0)) {
                collide_info.x = e.velocity.x
                if !e.physics.trigger {
                    e.velocity.x = -e.velocity.x * e.physics.bounciness
                } else {
                    e.position += move
                }
                move.x = 0
            }
            if collides_with_tiles(rect_offset(rect = hitbox, y = math.sign(e.velocity.y) * 1/32.0)) {
                collide_info.y = e.velocity.y
                if !e.physics.trigger {
                    e.velocity.y = -e.velocity.y * e.physics.bounciness
                    if e.velocity.y < 0.1 {
                        e.velocity.y = 0
                    } else {
                        e.position += move
                    }
                }
                move.y = 0
            }
        } else {
            // Spend what's left of the move
            e.position += move
            move = {0, 0}
        }
    }

    if e.on_collide_tile != nil && collide_info != {0, 0}{
        e->on_collide_tile(collide_info)
    }

    when USE_GRAVITY {
        // Apply gravity if not grounded
        if !e.physics.no_gravity {
            if !collides_with_tiles(rect_offset(rect = hitbox, y = -1/32.0)) {
                e.velocity.y -= time_delta * gravity
            } else { // Else calculate friction
                e.velocity.x -= math.sign(e.velocity.x) *
                        math.min(e.physics.friction, math.abs(e.velocity.x))
            }
        }
    }
}

collide_entities :: proc() {
    // Collide
    for i in 0..<(ENTITY_COUNT - 1) {
        if entities[i].type != .empty {
            for j in (i + 1)..<ENTITY_COUNT {
                if entities[j].type != .empty {
                    if (entities[i].physics.collision_layer & entities[j].physics.collision_mask) == 0 {
                        continue
                    }
                    if (entities[j].physics.collision_layer & entities[i].physics.collision_mask) == 0 {
                        continue
                    }
                    if do_collide_entities(&entities[i], &entities[j]) {
                        if entities[i].on_collide_entity != nil {
                            entities[i]->on_collide_entity(&entities[j])
                        }
                        if entities[j].on_collide_entity != nil {
                            entities[j]->on_collide_entity(&entities[i])
                        }
                    }
                }
            }
        }
    }
}

@(private="file")
do_collide_entities :: proc(first: ^Entity, second: ^Entity) -> bool {
    collide, b := rect_overlap(entity_hitbox(first), entity_hitbox(second))
    if collide && !first.physics.trigger && !second.physics.trigger {
        if b.x < b.y && b.x < b.z && b.x < b.w {    //Right
            collide_move_entities(first, second, b.x)
        }
        if b.y < b.x && b.y < b.z && b.y < b.w {    //Left
            collide_move_entities(first, second, b.y)
        }
        if b.z < b.x && b.z < b.y && b.z < b.w {    //Top
            collide_move_entities(first, second, b.z)
        }
        if b.w < b.x && b.w < b.y && b.w < b.z {    //Down
            collide_move_entities(first, second, b.w)
        }
    }
    return collide
}

@(private="file")
//Calculate the velocity ratio incase both entities moves
collide_move_entities :: proc(first: ^Entity, second: ^Entity, dist: f32) {
    tot_vel :Vector2= first.velocity + second.velocity
    first_vel: Vector2
    second_vel: Vector2
    if tot_vel.x != 0 {
        if first.velocity.x > 0 {
            first_vel.x = first.velocity.x / tot_vel.x
        } else {
            first_vel.x = -first.velocity.x / tot_vel.x
        }
        if second.velocity.x > 0 {
            second_vel.x = second.velocity.x / tot_vel.x
        } else {
            second_vel.x = -second.velocity.x / tot_vel.x
        }
    }
    if tot_vel.y != 0 {
        if first.velocity.y > 0 {
            first_vel.y = first.velocity.y / tot_vel.y
        } else {
            first_vel.y = -first.velocity.y / tot_vel.y
        }
        if second.velocity.y > 0 {
            second_vel.y = second.velocity.y / tot_vel.y
        } else {
            second_vel.y = -second.velocity.y / tot_vel.y
        }
    }
    first.position += dist * -first_vel
    second.position += dist * -second_vel
}

@(private="file")
// TODO: Fix bug: off by one pixel
collides_with_tiles :: proc(rect: Rect) -> bool {
    if tilemap_enabled() == false {
        return false
    }
    first_row := clamp(TILE_ROWS - 1 - int(math.floor(rect.top)), 0, TILE_ROWS)
    last_row  := clamp(TILE_ROWS - int(math.floor(rect.bottom)), 0, TILE_ROWS)
    first_col := clamp(int(math.floor(rect.left)), 0, TILE_COLS)
    last_col  := clamp(int(math.floor(rect.right) + 1), 0, TILE_COLS)

    for r in first_row..<last_row {
        for c in first_col..<last_col {
            if !tiles[tile_array[r][c]].walkable {   //First row of tilemap is walkable always
                return true
            }
        }
    }
    return false
}