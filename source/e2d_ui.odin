package main

import "core:fmt"

@(private="file")
UI_COUNT :: 200
FONT_COUNT :: 1

Ui_Anchor :: enum {
    top_left,
    top_center,
    top_right,
    middle_left,
    middle_center,
    middle_right,
    bottom_left,
    bottom_center,
    bottom_right,
}

Ui_element :: struct {
    size: Vector2,
    position: Vector2,
    color: Vector4,
    sprite: Sprite,
    anchor: Ui_Anchor,
    text: string,
    disabled: bool,
    parent: ^Ui_element,
    no_block: bool,
    value: f32,

    _input: ^Ui_element,
    _prev_hover: bool,
    _position: Vector2,
    _disabled: bool,

    on_mouse_enter: proc(element: ^Ui_element),
    on_mouse_leave: proc(element: ^Ui_element),
    on_mouse_move: proc(element: ^Ui_element, position: Vector2),
    on_mouse_down: proc(element: ^Ui_element, button: map[Mouse_button]bool),
    on_mouse_up: proc(element: ^Ui_element, button: map[Mouse_button]bool),
    on_mouse_click: proc(element: ^Ui_element),
    on_input_submit: proc(element: ^Ui_element, text: string),
    on_check_change: proc(element: ^Ui_element, value: bool),

    entity_ref: EntityId,
}

UI_Font :: struct {
    texture: u32,
    size: Vector2,
    frames: Vector2,
    ratio: f32,
}

@(private="file")
ui: [UI_COUNT]Ui_element
@(private="file")
ui_occupied: [UI_COUNT]bool
@(private="file")
ui_index: i32
mouse_state: Mouse_state
@(private="file")
ui_buttons: [20]^Ui_element
@(private="file")
prev_click: ^Ui_element
@(private="file")
button_index := 0
@(private="file")
last_index := -1
@(private="file")
ui_button_id := 0
fonts: [FONT_COUNT]UI_Font

ui_process :: proc() {
    blocking: bool
    input: bool
    //ui_process_keys()

    mouse_down: map[Mouse_button]bool
    mouse_up: map[Mouse_button]bool
    pos_scale := resolution.y / VIRTUAL_HEIGHT

    for i in Mouse_button {
        if mouse_pressed_raw(i) {
            mouse_down[i] = true
        }
        if mouse_released_raw(i) {
            mouse_up[i] = true
        }
    }

    for &e, i in ui {
        if ui_occupied[i] {
            ui_calc_parent(&e)
            if e._disabled || e.no_block {
                continue
            }
            hover := false
            pos := (e._position - (resolution / pos_scale / 2)) * -1
            if mouse_state.position.x / pos_scale > pos.x &&
               mouse_state.position.x / pos_scale < pos.x + e.size.x &&
               mouse_state.position.y / pos_scale > pos.y &&
               mouse_state.position.y / pos_scale < pos.y + e.size.y {
                    hover = true
                    blocking = true
            }
            set_blocking(blocking)
            if hover && !e._prev_hover {
                if e.on_mouse_enter != nil {
                    button := ui_buttons[button_index]
                    if button != nil && button.on_mouse_leave != nil {
                        button.on_mouse_leave(button)
                    }
                    e.on_mouse_enter(&e)
                }
            }
            if !hover && e._prev_hover {
                if e.on_mouse_leave != nil {
                    e.on_mouse_leave(&e)
                }
            }
            if hover && e._prev_hover {
                if mouse_down != nil {
                    if e.on_mouse_down != nil {
                        e.on_mouse_down(&e, mouse_down)
                    }
                    prev_click = &e
                    if e._input != nil {
                        input = true
                    }
                }
                if mouse_up != nil {
                    if e.on_mouse_up != nil {
                        e.on_mouse_up(&e, mouse_up)
                    }
                    if prev_click == &e {
                        if e.on_mouse_click != nil {
                            e.on_mouse_click(&e)
                        }
                    }
                }
            }
            if e.on_mouse_move != nil {
                e.on_mouse_move(&e, mouse_state.position)
            }
            e._prev_hover = hover
        }
    }
    if mouse_up != nil {
        prev_click = nil
    }
    if mouse_pressed_raw(.left) && !input && text_input_active() {
        text_input_stop()
    }
}

@(private="file")
ui_calc_parent :: proc(e: ^Ui_element) {
    e._disabled = (e.parent != nil && e.parent.disabled) || e.disabled
}

@(private="file")
ui_process_keys :: proc() {
    button := ui_buttons[button_index]
    if button == nil || button.disabled {
        return
    }
    if text_input_active() {
        return
    }
    if key_pressed("down") {
        if button.on_mouse_leave != nil && ui_buttons[button_index + 1] != nil{
            button.on_mouse_leave(button)
            button_index += 1
            button = ui_buttons[button_index]
            if button.on_mouse_enter != nil {
                button.on_mouse_enter(button)
            }
        }
    }
    if key_pressed("up") {
        if button.on_mouse_leave != nil && button_index > 0 {
            button.on_mouse_leave(button)
            button_index -= 1
            button = ui_buttons[button_index]
            if button.on_mouse_enter != nil {
                button.on_mouse_enter(button)
            }
        }
    }
    if key_pressed("action") {
        button.on_mouse_click(button)
    }
    last_index = button_index
}

ui_clear :: proc() {
    ui = {}
    ui_occupied = {}
    ui_buttons = {}
    button_index = 0
    ui_button_id = 0
    last_index = -1
    ui_index = 0
}

ui_get_by_id :: proc(id: i32) -> ^Ui_element {
    if id < 0 || id >= UI_COUNT {
        return nil
    }
    if !ui_occupied[id] {
        return nil
    }
    return &ui[id]
}

ui_image :: proc(position: Vector2, size: Vector2, sprite: int,
        anchor: Ui_Anchor, parent: ^Ui_element = nil) -> ^Ui_element {
    element := &ui[ui_index]
    ui_occupied[ui_index] = true
    ui_index += 1
    element.size = size
    element.position = position
    element.color = COLOR_WHITE
    element.sprite = sprites[sprite]
    element.anchor = anchor
    element.parent = parent
    return element
}

ui_container :: proc(position: Vector2, anchor: Ui_Anchor, 
        parent: ^Ui_element = nil) -> ^Ui_element {
    element := ui_image(position, {0, 0}, 0, anchor, parent)
    return element
}

ui_text :: proc(position: Vector2, size: f32, text: string, 
        anchor: Ui_Anchor, parent: ^Ui_element = nil, font: int = 0) -> ^Ui_element {
    element := ui_image(position, {size, fonts[font].ratio * size}, 0, anchor, parent)
    element.color = {0, 0, 0, 1}
    element.text = text
    element.no_block = true
    element.sprite = {
        texture = fonts[font].texture,
        size = fonts[font].size,
        frames = fonts[font].frames,
        offset = {0, 0},
    }
    return element
}

ui_button :: proc(position: Vector2, size: Vector2, on_click: proc(element: ^Ui_element),
        anchor: Ui_Anchor, parent: ^Ui_element = nil) -> ^Ui_element {
    element := ui_image(position, size, 45, anchor)
    element.on_mouse_enter = button_enter
    element.on_mouse_leave = button_leave
    element.on_mouse_down = button_down
    element.on_mouse_up = button_up
    element.on_mouse_click = on_click
    element.parent = parent
    ui_buttons[ui_button_id] = element
    ui_button_id += 1
    return element
}

ui_input :: proc(position: Vector2, size: Vector2, anchor: Ui_Anchor, 
        parent: ^Ui_element = nil) -> ^Ui_element {
    element := ui_image(position, size, 0, anchor)
    element._input = ui_text({2, 0}, size.y - 10, "", .middle_left, element)
    element.parent = parent
    element.on_mouse_click = text_input_click
    ui_buttons[ui_button_id] = element
    ui_button_id += 1
    return element
}

ui_checkbox :: proc(position: Vector2, size: f32, anchor: Ui_Anchor, 
        parent: ^Ui_element = nil) -> ^Ui_element {
    element := ui_image(position, {size, size}, 45, anchor)
    element._input = ui_text({0, 2}, size, " ", .middle_left, element)
    element.parent = parent
    element.on_mouse_click = proc(element: ^Ui_element) {
        if element.value == 1 {
            element.value = 0
            element._input.text = " "
        } else {
            element.value = 1
            element._input.text = "x"
        }
        if element.on_check_change != nil {
            element.on_check_change(element, element.value == 1)
        }
    }
    ui_buttons[ui_button_id] = element
    ui_button_id += 1
    return element
}

ui_render :: proc() {
    old_cam := render_get_camera()
    for &e, i in ui {
        if ui_occupied[i] {
            if (e.parent != nil && e.parent._disabled) || e.disabled {
                continue
            }
            pos: Vector2
            if e.parent != nil {
                pos = e.parent._position
            } else {
                pos = ui_get_render_pos(e.anchor)
            }
            render_set_camera(pos.x, pos.y)
            e._position = pos

            eposition := e.position
            switch e.anchor {
            case .top_left:
                eposition.y -= e.size.y
                if e.parent != nil {
                    eposition.y += e.parent.size.y
                }
            case .top_center:
                if e.text != "" {
                    eposition.x -= ui_get_text_width(&e) / 2
                } else {
                    eposition.x -= e.size.x / 2
                }
                eposition.y -= e.size.y
                if e.parent != nil {
                    eposition.x += e.parent.size.x / 2
                    eposition.y += e.parent.size.y
                }
            case .top_right:
                if e.text != "" {
                    eposition.x -= ui_get_text_width(&e)
                } else {
                    eposition.x -= e.size.x
                }
                eposition.y -= e.size.y
                if e.parent != nil {
                    eposition.x += e.parent.size.x
                    eposition.y += e.parent.size.y
                }
            case .middle_left:
                eposition.y -= e.size.y / 2
                if e.parent != nil {
                    eposition.y += e.parent.size.y / 2
                }
            case .middle_center:
                if e.text != "" {
                    eposition.x -= ui_get_text_width(&e) / 2
                } else {
                    eposition.x -= e.size.x / 2
                }
                eposition.y -= e.size.y / 2
                if e.parent != nil {
                    eposition.x += e.parent.size.x / 2
                    eposition.y += e.parent.size.y / 2
                }
            case .middle_right:
                if e.text != "" {
                    eposition.x -= ui_get_text_width(&e)
                } else {
                    eposition.x -= e.size.x
                }
                eposition.y -= e.size.y / 2
                if e.parent != nil {
                    eposition.x += e.parent.size.x
                    eposition.y += e.parent.size.y / 2
                }
            case .bottom_left:
                //Do nothing
            case .bottom_center:
                if e.text != "" {
                    eposition.x -= ui_get_text_width(&e) / 2
                } else {
                    eposition.x -= e.size.x / 2
                }
                if e.parent != nil {
                    eposition.x += e.parent.size.x / 2
                }
            case .bottom_right:
                if e.text != "" {
                    eposition.x -= ui_get_text_width(&e)
                } else {
                    eposition.x -= e.size.x
                }
                if e.parent != nil {
                    eposition.x += e.parent.size.x
                }
            }
            e._position -= eposition
            if e.size.x == 0 {
                continue
            }

            if e.text == "" {
                offset_y := ((e.sprite.frames.y - e.sprite.offset.y) / e.sprite.frames.y)
                offset :Vector2= {e.sprite.offset.x / e.sprite.frames.x, 1 - offset_y}
                render_quad({
                    texture = e.sprite.texture,
                    position = eposition,
                    size = e.size,
                    scale = 1 / e.sprite.frames,
                    offset = offset,
                    flip = {0, 0},
                    color = e.color,
                    slice9 = e.sprite.slice9,
                    tex_size = e.sprite.size,
                })
            } else {
                render_text(e.sprite, e.text, eposition, e.size, e.color)
            }
        }
    }
    render_set_camera(old_cam.x, old_cam.y)
}

@(private="file")
ui_get_render_pos :: proc(anchor: Ui_Anchor) -> Vector2 {
    pos_scale := resolution.y / VIRTUAL_HEIGHT
    half_res := resolution / 2 / pos_scale

    switch anchor {
    case .top_left:
        return {half_res.x, -half_res.y}
    case .top_center:
        return {0, -half_res.y}
    case .top_right:
        return {-half_res.x, -half_res.y}
    case .middle_left:
        return {half_res.x, 0}
    case .middle_center:
        return {0, 0}
    case .middle_right:
        return {-half_res.x, 0}
    case .bottom_left:
        return {half_res.x, half_res.y}
    case .bottom_center:
        return {0, half_res.y}
    case .bottom_right:
        return {-half_res.x, half_res.y}
    }
    return {0, 0}
}

ui_get_text_width :: proc(text: ^Ui_element) -> f32 {
    return f32(len(text.text)) * text.size.x
}

@(private="file")
button_enter :: proc(element: ^Ui_element) {
    element.color = {0.8, 0.8, 0.8, 1}
}

@(private="file")
button_leave :: proc(element: ^Ui_element) {
    element.color = COLOR_WHITE
}

@(private="file")
button_down :: proc(element: ^Ui_element, button: map[Mouse_button]bool) {
    if button[Mouse_button.left] {
        element.color = {0.6, 0.6, 0.6, 1}
    }
}

@(private="file")
button_up :: proc(element: ^Ui_element, button: map[Mouse_button]bool) {
    if button[Mouse_button.left] {
        element.color = {0.8, 0.8, 0.8, 1}
    }
}

font_create :: proc(data: []u8, frames: Vector2) -> UI_Font {
    texture, size := texture_create(data)
    ratio := (size.y / frames.y) / (size.x / frames.x)
    return UI_Font{texture, size, frames, ratio}
}

font_destroy_all :: proc() {
    for i in 0..<len(fonts) {
        texture_destroy(fonts[i].texture)
    }
}