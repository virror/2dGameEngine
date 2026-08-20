package main

import "core:fmt"
import "core:os"

Tilemap :: struct {
    texture: u32,
    size: Vector2,
    frames: Vector2,
}

Tile :: struct {
    offset: Vector2,
    walkable: bool,
    farmable: bool,
}

TILE_ROWS :: 100
TILE_COLS :: 100
TILEMAP_COUNT :: 1

tile_array: ^[TILE_ROWS][TILE_COLS]u16
tilemaps: [TILEMAP_COUNT]Tilemap
@(private="file")
has_tilemap: bool
@(private="file")
tilemap: Tilemap

//Village tileset
tiles: [64]Tile

tilemap_load_tileset :: proc(data: []u8) -> Tilemap {
    if tilemap.texture != 0 {
        texture_destroy(tilemap.texture)
    }
    texture, tex_size := texture_create(data)
    frames: Vector2 = tex_size / QUAD_SIZE
    size: Vector2 = {1 / frames.x, 1 / frames.y}

    for _, i in tiles {
        tiles[i].offset = {f32(i % int(frames.x)), f32(i / int(frames.x))}
    }
    return {texture, size, frames}
}

tilemap_unload_tilemaps :: proc() {
    for i in 0..<TILEMAP_COUNT {
        texture_destroy(tilemaps[i].texture)
    }
}

tilemap_set :: proc(idx: int) {
    has_tilemap = true
    tilemap = tilemaps[idx]
}

tilemap_get :: proc() -> ^Tilemap {
    return &tilemap
}

tilemap_clear :: proc() {
    has_tilemap = false
}

tilemap_enabled :: proc() -> bool {
    return has_tilemap
}

tilemap_render :: proc() {
    if has_tilemap == false || tile_array == nil {
        return
    }

    y_length := len(tile_array)

    for y in 0..< y_length{
        for x in 0..<len(tile_array[0]) {
            if tile_array[y][x] > 0 {
                if is_inside_screen({f32(x), f32(y_length - 1 - y)}, {QUAD_SIZE, QUAD_SIZE}) {
                    offset: Vector2 = tiles[tile_array[y][x]].offset
                    frame_offset: Vector2 = {tilemap.size.x * offset.x, tilemap.size.y * offset.y}

                    render_quad({
                        texture = tilemap.texture,
                        position = {f32(x) * QUAD_SIZE, f32(y_length - 1 - y) * QUAD_SIZE},
                        size = {QUAD_SIZE, QUAD_SIZE},
                        offset = frame_offset,
                        scale = tilemap.size,
                        flip = {0, 0},
                        color = COLOR_WHITE,
                        slice9 = {0, 0, 0, 0},
                        tex_size = {0, 0},
                    },)
                }
            }
        }
    }
}

tilemap_get_tile :: proc(x: int, y: int) -> Tile {
    if !validate(x, y) {
        return tiles[0]
    }
    y2 := TILE_ROWS - y - 1
    return tiles[tile_array[y2][x]]
}

tilemap_set_tile :: proc(x: int, y: int, tile: u16) {
    if !validate(x, y) {
        return
    }
    y2 := TILE_ROWS - y - 1
    tile_array[y2][x] = tile
}

@(private="file")
validate :: proc(x: int, y: int) -> bool {
    if x < 0 || x >= TILE_COLS || y < 0 || y >= TILE_ROWS {
        return false
    } else {
        return true
    }
}

tilemap_load_map :: proc(path: string, map_array: ^[TILE_ROWS][TILE_COLS]u16) {
    file, err := os.open(path, os.O_RDONLY)
    if err != nil {
        has_tilemap = true
        return
    }
    tmp: [TILE_COLS * TILE_ROWS * size_of(u16)]u8
    os.read(file, tmp[:])
    map_array^ = (cast(^[TILE_ROWS][TILE_COLS]u16)&tmp[0])^
    tile_array = map_array

    tmp2: [ENTITY_COUNT * size_of(MapEntity)]u8
    os.read(file, tmp2[:])
    map_ents := (cast(^[ENTITY_COUNT]MapEntity)&tmp2[0])^
    for e in map_ents {
        if e.type != "" {
            create_entity(e.type, e.position)
        }
    }
    os.close(file)
    has_tilemap = true
}