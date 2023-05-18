const std = @import("std");
const ArrayList = std.ArrayList;
const sokol = @import("sokol");
const zstbi = @import("zstbi");
const zm = @import("zmath");
const assets = @import("./assets.zig");
const sg = sokol.gfx;
const sapp = sokol.app;
const sgapp = sokol.app_gfx_glue;
const saudio = sokol.audio;
const slog = sokol.log;
const simgui = sokol.imgui;

var manager = std.heap.GeneralPurposeAllocator(.{}){};
const allocator = manager.allocator();

const AABB = struct {
    // top left
    tl: zm.Vec = zm.f32x4s(0),
    // bottom right
    br: zm.Vec = zm.f32x4s(0),

    const Self = @This();

    pub fn contains(self: Self, point: zm.Vec) bool {
        return if (point[0] > self.tl[0] and point[0] < self.br[0] and point[1] > self.br[1] and point[1] < self.tl[1]) true else false;
    }
};

const Suit = enum {
    hearts,
    clubs,
    diamonds,
    spades,
};

const CardId = struct {
    suit: Suit,
    rank: u4,
};

const EntityType = enum {
    card,
    stack,
    hand,
};

const EntityData = union(EntityType) {
    card: struct { id: CardId },
    stack: struct { cards: ArrayList(EntityData) },
    hand: struct { cards: ArrayList(EntityData) },
};

const Entity = struct {
    texture: sg.Image = .{},
    collider: AABB = .{},
    position: zm.Vec = zm.f32x4s(0),
    rotation: f32 = 0,
    size: zm.Vec = zm.f32x4s(1),
    data: EntityData,
};

const Mouse = struct {
    position: zm.Vec = zm.f32x4s(0),
    dragging: ?*Entity = null,
    drag_start: zm.Vec = zm.f32x4s(0),
    drag_entity_start: zm.Vec = zm.f32x4s(0),
};

const State = struct {
    gfx: struct {
        bind: sg.Bindings = .{},
        pip: sg.Pipeline = .{},
        pass_action: sg.PassAction = .{},
        projection: zm.Mat = zm.identity(),
    } = .{},
    world: struct {
        entities: ArrayList(Entity) = ArrayList(Entity).init(allocator),
    } = .{},
    input: struct {
        mouse: Mouse = .{},
    } = .{},
};

var state: State = .{};

export fn init() void {
    sg.setup(.{
        .context = sgapp.context(),
        .logger = .{ .func = slog.func },
    });

    simgui.setup(.{});

    state.gfx.bind.vertex_buffers[0] = sg.makeBuffer(.{ .data = sg.asRange(&[_]f32{
        -0.5, 0.5,  0.5, 1, 1, 1, 1, 0, 1,
        0.5,  0.5,  0.5, 1, 1, 1, 1, 1, 1,
        -0.5, -0.5, 0.5, 1, 1, 1, 1, 0, 0,
        0.5,  -0.5, 0.5, 1, 1, 1, 1, 1, 0,
    }) });

    state.gfx.bind.index_buffer = sg.makeBuffer(.{
        .type = .INDEXBUFFER,
        .data = sg.asRange(&[_]u16{ 0, 1, 2, 1, 2, 3 }),
    });

    var image_src: zstbi.Image = zstbi.Image.loadFromFile("/home/voxal/code/cards/assets/bpfp-steam.png", 4) catch unreachable;

    var image_desc: sg.ImageDesc = .{ .width = 16, .height = 16 };
    image_desc.data.subimage[0][0] = sg.asRange(image_src.data);
    state.gfx.bind.fs_images[0] = sg.makeImage(image_desc);
    zstbi.Image.deinit(&image_src);

    const shd = sg.makeShader(glShaderDesc());

    var pip_desc: sg.PipelineDesc = .{
        .index_type = .UINT16,
        .shader = shd,
        .blend_color = .{ .r = 1, .g = 0, .b = 0, .a = 1 },
    };
    pip_desc.layout.attrs[0].format = .FLOAT3;
    pip_desc.layout.attrs[1].format = .FLOAT4;
    pip_desc.layout.attrs[2].format = .FLOAT2;
    pip_desc.colors[0].blend = .{
        .enabled = true,
        .src_factor_rgb = .SRC_ALPHA,
        .dst_factor_rgb = .ONE_MINUS_SRC_ALPHA,
    };

    state.gfx.pip = sg.makePipeline(pip_desc);
    state.gfx.pass_action.colors[0] = .{
        .action = .CLEAR,
        .value = .{ .r = 1, .g = 1, .b = 1, .a = 1 },
    };

    state.world.entities.append(Entity{
        .texture = state.gfx.bind.fs_images[0],
        .collider = .{ .tl = zm.f32x4(-100, 100, 0, 0), .br = zm.f32x4(100, -100, 0, 0) },
        .position = zm.f32x4s(0),
        .rotation = 0,
        .size = zm.f32x4(200, 200, 0, 0),
        .data = .{
            .card = .{
                .id = .{ .suit = Suit.hearts, .rank = 2 },
            },
        },
    }) catch unreachable;

    state.gfx.projection = zm.orthographicRhGl(sapp.widthf(), sapp.heightf(), -1, 100);
}

export fn frame() void {
    simgui.newFrame(.{
        .width = sapp.width(),
        .height = sapp.height(),
        .delta_time = sapp.frameDuration(),
        .dpi_scale = sapp.dpiScale(),
    });
    simgui.igText("Hello, world");
    sg.beginDefaultPass(state.gfx.pass_action, sapp.width(), sapp.height());
    sg.applyPipeline(state.gfx.pip);
    sg.applyBindings(state.gfx.bind);
    for (state.world.entities.items, 0..) |entity, i| {
        state.world.entities.items[i].collider.tl = zm.f32x4(-(entity.size[0] / 2) + entity.position[0], entity.size[0] / 2 + entity.position[1], 0, 0);
        state.world.entities.items[i].collider.br = zm.f32x4(entity.size[0] / 2 + entity.position[0], -(entity.size[0] / 2) + entity.position[1], 0, 0);
        renderEntity(entity);
    }
    simgui.render();
    sg.endPass();
    sg.commit();
}

// If we need to figure out where the vertices land for click interaction, we might as well do the matrix multiplication on the zig side
fn renderEntity(entity: Entity) void {
    if (entity.texture.id != state.gfx.bind.fs_images[0].id) {
        state.gfx.bind.fs_images[0] = entity.texture;
        sg.applyBindings(state.gfx.bind);
    }

    var model = zm.scalingV(entity.size);

    model = zm.mul(model, zm.rotationZ(entity.rotation));
    model = zm.mul(model, zm.translationV(entity.position));

    const mvp = zm.mul(model, state.gfx.projection);

    sg.applyUniforms(.VS, 0, sg.asRange(&.{ .mvp = zm.matToArr((mvp)) }));
    sg.draw(0, 6, 1);
}

// TODO Find point relative to entity to anchor cursor to
export fn input(ev: ?*const sapp.Event) void {
    const event = ev.?;
    var mouse = &state.input.mouse;
    switch (event.type) {
        .MOUSE_DOWN => {
            // std.debug.print("screen: ({d}, {d})\n", .{
            //     2 * (event.mouse_x / sapp.widthf()) - 1,
            //     -(2 * (event.mouse_y / sapp.heightf()) - 1),
            // });
            // std.debug.print("world: ({d}, {d})", .{ event.mouse_x - sapp.widthf() / 2, event.mouse_y - sapp.heightf() / 2 });
            // Check for entities that are under the cursor, taking the first one found
            // TODO make some z buffer so i can properly order the entities
            if (event.mouse_button == .LEFT) {
                for (state.world.entities.items, 0..) |entity, i| {
                    if (entity.collider.contains(mouse.position)) {
                        mouse.dragging = &state.world.entities.items[i];
                        mouse.drag_start = mouse.position;
                        mouse.drag_entity_start = entity.position;
                        break;
                    }
                }
            }
        },
        .MOUSE_UP => {
            if (event.mouse_button == .LEFT) {
                mouse.dragging = null;
            }
        },
        .MOUSE_MOVE => {
            mouse.position = zm.f32x4(event.mouse_x - sapp.widthf() / 2, -(event.mouse_y - sapp.heightf() / 2), 0, 0);
            if (mouse.dragging) |drag| {
                drag.position[0] = mouse.drag_entity_start[0] + mouse.position[0] - mouse.drag_start[0];
                drag.position[1] = mouse.drag_entity_start[1] + mouse.position[1] - mouse.drag_start[1];
            }
        },
        .RESIZED => {
            state.gfx.projection = zm.orthographicRhGl(sapp.widthf(), sapp.heightf(), -1, 100);
        },
        else => {},
    }
}

export fn cleanup() void {
    sg.shutdown();
    zstbi.deinit();
}

pub fn main() !void {
    zstbi.init(allocator);
    zstbi.setFlipVerticallyOnLoad(true);

    sapp.run(.{
        .init_cb = init,
        .frame_cb = frame,
        .event_cb = input,
        .cleanup_cb = cleanup,
        .width = 800,
        .height = 600,
        .window_title = "Cards",
        .logger = .{ .func = slog.func },
    });
}

fn glShaderDesc() sg.ShaderDesc {
    var desc: sg.ShaderDesc = .{};
    desc.attrs[0].name = "position";
    desc.attrs[1].name = "color0";
    desc.attrs[2].name = "texcoord0";
    desc.fs.images[0] = .{ .name = "tex", .image_type = ._2D };
    desc.vs.uniform_blocks[0].size = 64;
    desc.vs.uniform_blocks[0].uniforms[0].name = "mvp";
    desc.vs.uniform_blocks[0].uniforms[0].type = .MAT4;
    desc.vs.source = @embedFile("./shaders/vs.glsl");
    desc.fs.source = @embedFile("./shaders/fs.glsl");

    return desc;
}
