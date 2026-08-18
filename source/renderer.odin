package main

import sdl "vendor:sdl3"
import imgui "../../imgui"
import "../../imgui/imgui_impl_sdlgpu3"
import fmt "core:fmt"

rt_texture: sdl.GPUTextureSamplerBinding

render_all :: proc(io: ^imgui.IO) {
    draw_data := imgui.GetDrawData()
	is_minimized := draw_data.DisplaySize.x == 0 || draw_data.DisplaySize.y == 0
    renderer.cmd_buf = sdl.AcquireGPUCommandBuffer(renderer.gpu)

    //Render pass 1, entities and game UI
    if !is_minimized {
        color_info := sdl.GPUColorTargetInfo {
            texture = rt_texture.texture,
            load_op = .CLEAR,
            clear_color = sdl.FColor({0.298, 0.27, 0.259, 1.0}),
            store_op = .STORE,
        }
        renderer.render_pass = sdl.BeginGPURenderPass(renderer.cmd_buf, &color_info, 1, nil)
        sdl.BindGPUVertexBuffers(renderer.render_pass, 0, &(sdl.GPUBufferBinding {buffer = renderer.vertex_buf}), 1)
        sdl.BindGPUIndexBuffer(renderer.render_pass, {buffer = renderer.index_buf}, ._16BIT)
    } else {
        renderer.render_pass = nil
    }

    render_set_shader(.game_shader)
    for i in 0..<len(entities) {
        if entities[i].type != .empty {
            entity_render(&entities[i])
        }
    }

    render_set_shader(.ui_shader)
    ui_render()

    if (renderer.render_pass != nil) {
        sdl.EndGPURenderPass(renderer.render_pass)
    }

    //Render pass 2, Dear IMGUI
    swap_text: ^sdl.GPUTexture
    if !sdl.WaitAndAcquireGPUSwapchainTexture(renderer.cmd_buf, renderer.win, &swap_text, nil, nil) {
        panic("Failed to acquire swapchain texture")
    }
    if swap_text != nil && !is_minimized {
        imgui_impl_sdlgpu3.PrepareDrawData(draw_data, renderer.cmd_buf)

        color_info := sdl.GPUColorTargetInfo {
            texture = swap_text,
            load_op = .LOAD,
            clear_color = sdl.FColor({0.298, 0.27, 0.259, 1.0}),
            store_op = .STORE,
        }
        renderer.render_pass = sdl.BeginGPURenderPass(renderer.cmd_buf, &color_info, 1, nil)
        sdl.BindGPUVertexBuffers(renderer.render_pass, 0, &(sdl.GPUBufferBinding {buffer = renderer.vertex_buf}), 1)
        sdl.BindGPUIndexBuffer(renderer.render_pass, {buffer = renderer.index_buf}, ._16BIT)
        imgui_impl_sdlgpu3.RenderDrawData(draw_data, renderer.cmd_buf, renderer.render_pass, nil)
    } else {
        renderer.render_pass = nil
    }

    if (renderer.render_pass != nil) {
        sdl.EndGPURenderPass(renderer.render_pass)
    }

    if .ViewportsEnable in io.ConfigFlags {
        imgui.UpdatePlatformWindows()
        imgui.RenderPlatformWindowsDefault()
    }

    if !sdl.SubmitGPUCommandBuffer(renderer.cmd_buf) {
        panic("Cant submit GPU cmd buffer")
    }
}

texture_create_rt :: proc() -> () {
    gpu_texture := sdl.CreateGPUTexture(renderer.gpu, {
        type = .D2,
        format = .R8G8B8A8_UNORM,
        usage = {.SAMPLER, .COLOR_TARGET},
        width = u32(resolution.x),
        height = u32(resolution.y),
        layer_count_or_depth = 1,
        num_levels = 1,
    })

    rt_texture.texture = gpu_texture
    rt_texture.sampler = sdl.CreateGPUSampler(renderer.gpu, {})
}