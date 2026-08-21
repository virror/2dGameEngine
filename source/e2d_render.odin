package main

import sdl "vendor:sdl3"
import imgui "../../imgui"
import "../../imgui/imgui_impl_sdlgpu3"
import "base:runtime"
import "core:math/linalg"
import "core:log"
import "core:image/png"
import "core:mem"
import libimage "core:image"
import "core:fmt"
import "core:slice"

// Same as in shader
WIN_WIDTH :: 1400
WIN_HEIGHT :: 800
QUAD_SIZE :: 16
VIRTUAL_HEIGHT :: 480.0
COLOR_WHITE :Vector4: {1, 1, 1, 1}

@(private="file")
Shader_type :: enum {
    game_shader,
    ui_shader,
}

@(private="file")
Ui_frag_uniform :: struct {
    coordScale: Vector2,
    coordOffset: Vector2,
    color: Vector4,
    slice9: Vector4,
    size: Vector2,
    tex_size: Vector2,
}

@(private="file")
Ui_vert_uniform :: struct #packed {
    model: matrix[4, 4]f32,
    resolution: Vector2,
    cameraPos: Vector2,
    flip: Vector2,
}

@(private="file")
Light_frag_uniform :: struct {
    diffuse: f32,
    ambient: f32,
}

@(private="file")
Vertex_Data :: struct {
    pos: Vector2,
    tex: Vector2,
}

@(private="file")
Render_data :: struct {
    texture: u32,
    position: Vector2,
    size: Vector2,
    scale: Vector2,
    offset: Vector2,
    flip: Vector2,
    color: Vector4,
    slice9: Vector4,
    tex_size: Vector2,
}

Render :: struct {
    gpu: ^sdl.GPUDevice,
    win: ^sdl.Window,
    vertex_buf: ^sdl.GPUBuffer,
    index_buf: ^sdl.GPUBuffer,
    cmd_buf: ^sdl.GPUCommandBuffer,
    render_pass: ^sdl.GPURenderPass,
}

@(private="file")
active_shader: Shader_type
@(private="file")
camera_position: Vector2
resolution: Vector2 = {WIN_WIDTH, WIN_HEIGHT}
@(private="file")
pipeline_ui: ^sdl.GPUGraphicsPipeline
@(private="file")
pipeline_game: ^sdl.GPUGraphicsPipeline
renderer: Render
textures: [dynamic]sdl.GPUTextureSamplerBinding

@(private="file")
texture_id: u32
@(private="file")
light_frag_uniform: Light_frag_uniform
@(private="file")
render_list: [ENTITY_COUNT]^Entity

default_context: runtime.Context

render_init :: proc(window: ^sdl.Window) {
    context.logger = log.create_console_logger()
    default_context = context

    sdl.SetLogPriorities(.ERROR)
    sdl.SetLogOutputFunction(proc "c" (userdata: rawptr, category: sdl.LogCategory, priority: sdl.LogPriority, message: cstring) {
        context = default_context
        log.debugf("SDL {} [{}] {}", category, priority, message)
    }, nil)

    renderer.gpu = sdl.CreateGPUDevice({.SPIRV, .METALLIB}, false, nil)
    if !sdl.ClaimWindowForGPUDevice(renderer.gpu, window) {
        panic("GPU failed to claim window")
    }
    renderer.win = window

    create_quad()

    when ODIN_OS == .Darwin {
        vert_shader := shader_create(#load("../shaders/ui_vert.metal"), .VERTEX, 1, 0, {.MSL}, "main0")
        frag_shader := shader_create(#load("../shaders/ui_frag.metal"), .FRAGMENT, 1, 1, {.MSL}, "main0")
        pipeline_ui = pipeline_create(vert_shader, frag_shader)

        vert_shader = shader_create(#load("../shaders/shader_vert.metal"), .VERTEX, 1, 0, {.MSL}, "main0")
        frag_shader = shader_create(#load("../shaders/shader_frag.metal"), .FRAGMENT, 2, 1, {.MSL}, "main0")
        pipeline_game = pipeline_create(vert_shader, frag_shader)
    } else {
        vert_shader := shader_create(#load("../shaders/ui.spv.vert"), .VERTEX, 1, 0, {.SPIRV})
        frag_shader := shader_create(#load("../shaders/ui.spv.frag"), .FRAGMENT, 1, 1, {.SPIRV})
        pipeline_ui = pipeline_create(vert_shader, frag_shader)

        vert_shader = shader_create(#load("../shaders/shader.spv.vert"), .VERTEX, 1, 0, {.SPIRV})
        frag_shader = shader_create(#load("../shaders/shader.spv.frag"), .FRAGMENT, 2, 1, {.SPIRV})
        pipeline_game = pipeline_create(vert_shader, frag_shader)
    }
    render_sort_init()
    render_set_light(1, 0)
}

get_gpu :: proc() -> ^sdl.GPUDevice {
    return renderer.gpu
}

@(private="file")
pipeline_create :: proc(vert_shader: ^sdl.GPUShader, frag_shader: ^sdl.GPUShader, ) -> ^sdl.GPUGraphicsPipeline {
    vert_attrs := []sdl.GPUVertexAttribute {
        {
            location = 0,
            buffer_slot = 0,
            format = .FLOAT2,
            offset = u32(offset_of(Vertex_Data, pos)),
        },
        {
            location = 1,
            buffer_slot = 0,
            format = .FLOAT2,
            offset = u32(offset_of(Vertex_Data, tex)),
        },
    }

    pipeline := sdl.CreateGPUGraphicsPipeline(renderer.gpu, {
        vertex_shader = vert_shader,
        fragment_shader = frag_shader,
        primitive_type = .TRIANGLELIST,
        vertex_input_state = {
            num_vertex_buffers = 1,
            vertex_buffer_descriptions = &(sdl.GPUVertexBufferDescription {
                slot = 0,
                pitch = size_of(Vertex_Data),
            }),
            num_vertex_attributes = u32(len(vert_attrs)),
            vertex_attributes = raw_data(vert_attrs),
        },
        target_info = {
            num_color_targets = 1,
            color_target_descriptions = &(sdl.GPUColorTargetDescription {
                format = sdl.GetGPUSwapchainTextureFormat(renderer.gpu, renderer.win),
                blend_state = {
                    src_color_blendfactor = .SRC_ALPHA,
                    dst_color_blendfactor = .ONE_MINUS_SRC_ALPHA,
                    color_blend_op = .ADD,
                    src_alpha_blendfactor = .ONE,
                    dst_alpha_blendfactor = .ONE_MINUS_SRC_ALPHA,
                    alpha_blend_op = .ADD,
                    enable_blend = true,
                },
            }),
        },
    })
    sdl.ReleaseGPUShader(renderer.gpu, vert_shader)
    sdl.ReleaseGPUShader(renderer.gpu, frag_shader)
    return pipeline
}

render_deinit :: proc() {
    sdl.ReleaseGPUBuffer(renderer.gpu, renderer.vertex_buf)
    sdl.ReleaseGPUBuffer(renderer.gpu, renderer.index_buf)
    sdl.ReleaseGPUGraphicsPipeline(renderer.gpu, pipeline_ui)
    sdl.ReleaseGPUGraphicsPipeline(renderer.gpu, pipeline_game)
    sdl.ReleaseWindowFromGPUDevice(renderer.gpu, renderer.win)
    sdl.DestroyGPUDevice(renderer.gpu)
    log.destroy_console_logger(context.logger)
}

render_set_shader :: proc(shader: Shader_type) {
    active_shader = shader
    switch shader {
    case .ui_shader:
        sdl.BindGPUGraphicsPipeline(renderer.render_pass, pipeline_ui)
    case .game_shader:
        sdl.BindGPUGraphicsPipeline(renderer.render_pass, pipeline_game)
    }
}

render_set_light :: proc(diffuse: f32, ambient: f32) {
    light_frag_uniform = {diffuse, ambient}
}

render_update_viewport :: proc(width, height: i32) {
    resolution = {f32(width), f32(height)}
    sdl.ReleaseGPUTexture(renderer.gpu, rt_texture.texture)
    sdl.ReleaseGPUSampler(renderer.gpu, rt_texture.sampler)
    texture_create_rt()
}

@(private="file")
create_quad :: proc() {
    vertices := []Vertex_Data {
        {{0, 1}, {0, 0}},
        {{1, 1}, {1, 0}},
        {{0, 0}, {0, 1}},
        {{1, 0}, {1, 1}},
    }

    indices := []u16 {
        0, 1, 2,
        2, 1, 3,
     }

    vert_size := u32(len(vertices) * size_of(vertices[0]))
    renderer.vertex_buf = sdl.CreateGPUBuffer(renderer.gpu, {
        usage = {.VERTEX},
        size = vert_size,
    })
    index_size := u32(len(indices) * size_of(indices[0]))
    renderer.index_buf = sdl.CreateGPUBuffer(renderer.gpu, {
        usage = {.INDEX},
        size = index_size,
    })
    trans_buf := sdl.CreateGPUTransferBuffer(renderer.gpu, {
        usage = .UPLOAD,
        size = vert_size + index_size,
    })
    trans_mem := transmute([^]byte)sdl.MapGPUTransferBuffer(renderer.gpu, trans_buf, false)
    mem.copy(trans_mem, raw_data(vertices), int(vert_size))
    mem.copy(trans_mem[vert_size:], raw_data(indices), int(index_size))
    sdl.UnmapGPUTransferBuffer(renderer.gpu, trans_buf)
    copy_cmd_buf := sdl.AcquireGPUCommandBuffer(renderer.gpu)
    copy_pass := sdl.BeginGPUCopyPass(copy_cmd_buf)
    sdl.UploadToGPUBuffer(copy_pass, {trans_buf, 0}, {renderer.vertex_buf, 0, vert_size}, false)
    sdl.UploadToGPUBuffer(copy_pass, {trans_buf, vert_size}, {renderer.index_buf, 0, index_size}, false)
    sdl.EndGPUCopyPass(copy_pass)
    if !sdl.SubmitGPUCommandBuffer(copy_cmd_buf) {
        panic("Cant submit GPU cmd buffer")
    }
    sdl.ReleaseGPUTransferBuffer(renderer.gpu, trans_buf)
}

@(private="file")
shader_create :: proc(shader_data: []u8, stage: sdl.GPUShaderStage, buffers: u32,
                      samplers: u32, format: sdl.GPUShaderFormat, entrypoint: cstring = "main") -> ^sdl.GPUShader {
    shader := sdl.CreateGPUShader(renderer.gpu, {
        code_size = len(shader_data),
        code = raw_data(shader_data),
        entrypoint = entrypoint,
        format = format,
        stage = stage,
        num_uniform_buffers = buffers,
        num_samplers = samplers,
    })
    return shader
}

texture_from_name :: proc(file_name: string) -> (u32, Vector2) {
    image, err := png.load_from_file(file_name)
    tex, size := texture_create2(image, err)
    return tex, size
}

texture_create :: proc(data: []u8) -> (u32, Vector2) {
    image, err := png.load_from_bytes(data)
    return texture_create2(image, err)
}

texture_create2 :: proc(image: ^png.Image, err: png.Error) -> (u32, Vector2) {
    assert(err == nil, "Failed to load image.")
    alpha_ok := libimage.alpha_add_if_missing(image)
    assert(alpha_ok, "Failed to guarantee there's an alpha channel.")
    assert(image.channels == 4 && image.depth == 8, "Bad image format.")
    assert(image.pixels.off == 0, "Probably not good, whatever it means.")
    defer png.destroy(image)

    w := image.width
    h := image.height
    gpu_texture := sdl.CreateGPUTexture(renderer.gpu, {
        type = .D2,
        format = .R8G8B8A8_UNORM,
        usage = {.SAMPLER},
        width = u32(w),
        height = u32(h),
        layer_count_or_depth = 1,
        num_levels = 1,
    })

    append(&textures, sdl.GPUTextureSamplerBinding {
        texture = gpu_texture,
        sampler = sdl.CreateGPUSampler(renderer.gpu, {}),
    })
    texture_id = u32(len(textures)) - 1
    tex_size := u32(w * h * 4)
    trans_buf := sdl.CreateGPUTransferBuffer(renderer.gpu, {
        usage = .UPLOAD,
        size = tex_size,
    })
    trans_mem := sdl.MapGPUTransferBuffer(renderer.gpu, trans_buf, false)
    mem.copy(trans_mem, &image.pixels.buf[0], int(tex_size))
    sdl.UnmapGPUTransferBuffer(renderer.gpu, trans_buf)
    copy_cmd_buf := sdl.AcquireGPUCommandBuffer(renderer.gpu)
    copy_pass := sdl.BeginGPUCopyPass(copy_cmd_buf)
    sdl.UploadToGPUTexture(copy_pass, {transfer_buffer = trans_buf},
        {
            texture = gpu_texture,
            w = u32(w),
            h = u32(h),
            d = 1,
        }, false)
    sdl.EndGPUCopyPass(copy_pass)
    if !sdl.SubmitGPUCommandBuffer(copy_cmd_buf) {
        panic("Cant submit GPU cmd buffer")
    }
    sdl.ReleaseGPUTransferBuffer(renderer.gpu, trans_buf)
    texture_id += 1
    return texture_id - 1, {f32(w), f32(h)}
}

texture_destroy :: proc(texture: u32) {
    sdl.ReleaseGPUSampler(renderer.gpu, textures[texture].sampler)
    sdl.ReleaseGPUTexture(renderer.gpu, textures[texture].texture)
}

render_quad :: proc(data: Render_data) {
    if renderer.render_pass != nil {
        ui_frag_uniform :Ui_frag_uniform= {data.scale, data.offset, data.color, data.slice9, data.size, data.tex_size}
        sdl.PushGPUFragmentUniformData(renderer.cmd_buf, 0, &ui_frag_uniform, size_of(ui_frag_uniform))
        if active_shader == .game_shader {
            sdl.PushGPUFragmentUniformData(renderer.cmd_buf, 1, &light_frag_uniform, size_of(light_frag_uniform))
        }

        model_matrix := linalg.matrix4_scale_f32({data.size.x, data.size.y, 0})
        model_matrix = linalg.matrix4_translate_f32({data.position.x, data.position.y, 0}) * model_matrix
        ui_vert_uniform :Ui_vert_uniform= {model_matrix, resolution, camera_position, data.flip}
        sdl.PushGPUVertexUniformData(renderer.cmd_buf, 0, &ui_vert_uniform, size_of(ui_vert_uniform))
        
        sdl.BindGPUFragmentSamplers(renderer.render_pass, 0, &textures[data.texture], 1)
        sdl.DrawGPUIndexedPrimitives(renderer.render_pass, 6, 1, 0, 0, 0)
    }
}

// Doesn't rely on Open GL, but still a natural place here.
render_text :: proc(font: Sprite, text: string, position: Vector2, 
      size: Vector2 = {0, 0}, color: Vector4 = COLOR_WHITE) {
    assert(font.frames.x * font.frames.y > 96, "Has all printable ASCII characters")

    real_size := font.size / font.frames
    scale: Vector2 = real_size / font.size
    if linalg.vector_length(size) != 0 {
        real_size = size
    }

    bytes := raw_data(text)[:len(text)]
    new_pos := position
    for b, _ in bytes {
        x := (b - 32) % u8(font.frames.x)
        y := (b - 32) / u8(font.frames.x)
        if b == 10 {
            new_pos.y -= size.y + 2
            new_pos.x = position.x
            continue
        }

        render_quad({
            texture = font.texture,
            position = {new_pos.x, new_pos.y},
            size = real_size,
            scale = scale,
            offset = {scale.x * f32(x), scale.y * f32(y)},
            flip = {0, 0},
            color = color,
            slice9 = {0, 0, 0, 0},
            tex_size = {0, 0},
        },)
        new_pos.x += real_size.x
    }
}

render_set_camera :: proc(x: f32 = camera_position.x, y: f32 = camera_position.y) {
    camera_position = {x, y}
}

render_get_camera :: proc() -> Vector2 {
    return camera_position
}

render_sort_init :: proc() {
    for _, i in entities {
        render_list[i] = &entities[i]
    }
}

render_sort_and_render :: proc() {
    tmp_slice := render_list[:]
    slice.sort_by(tmp_slice, sort_func)

    for e, i in render_list {
        if render_list[i].type != "" {
            entity_render(e)
        }
    }
}

@(private="file")
sort_func :: proc(i: ^Entity, j: ^Entity) -> bool {
    return i.background || i.position.y > j.position.y
}

render_set_fullscreen :: proc(fullscreen: bool) {
    sdl.SetWindowFullscreen(renderer.win, fullscreen)
}