const builtin = @import("builtin");
const sapp = @import("./app.zig");
const sg = @import("./gfx.zig");
pub usingnamespace @cImport({
    @cDefine("CIMGUI_DEFINE_ENUMS_AND_STRUCTS", "");
    @cInclude("cimgui.h");
});

fn cStrToZig(c_str: [*c]const u8) [:0]const u8 {
    return @import("std").mem.span(c_str);
}

pub const Allocator = extern struct {
    alloc: ?*const fn (usize, ?*anyopaque) callconv(.C) ?*anyopaque = null,
    free: ?*const fn (?*anyopaque, ?*anyopaque) callconv(.C) void = null,
    user_data: ?*anyopaque = null,
};

pub const Desc = extern struct {
    max_vertices: i32 = 65536,
    pixel_format: sg.PixelFormat = .DEFAULT,
    depth_format: sg.PixelFormat = .DEFAULT,
    sample_count: i32 = 0,
    ini_filename: [*c]const u8 = 0,
    no_default_font: bool = false,
    disable_paste_override: bool = false,
    disable_set_mouse_cursor: bool = false,
    disable_windows_resize_from_edges: bool = false,
    write_alpha_channel: bool = false,
    allocator: Allocator = .{},
};

pub const FrameDesc = extern struct {
    width: i32,
    height: i32,
    delta_time: f64,
    dpi_scale: f32,
};

pub extern fn simgui_setup([*c]const Desc) void;
pub fn setup(desc: Desc) void {
    simgui_setup(&desc);
}

pub extern fn simgui_shutdown() void;
pub fn shutdown() void {
    simgui_shutdown();
}

pub extern fn simgui_new_frame([*c]const FrameDesc) void;
pub fn newFrame(frame: FrameDesc) void {
    simgui_new_frame(&frame);
}

pub extern fn simgui_render() void;
pub fn render() void {
    simgui_render();
}

pub extern fn simgui_map_keycode([*c]const sapp.Keycode) i32;
pub fn mapKeycode(keycode: sapp.Keycode) i32 {
    simgui_map_keycode(&keycode);
}

pub extern fn simgui_handle_event([*c]const sapp.Event) bool;
pub fn handleEvent(ev: sapp.Event) bool {
    simgui_handle_event(&ev);
}
