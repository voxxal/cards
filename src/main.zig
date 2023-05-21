const std = @import("std");
const time = std.time;
const ArrayList = std.ArrayList; // TODO convert to MultiArrayList
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
    clubs,
    diamonds,
    hearts,
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
    card: struct { id: CardId, flipped: bool },
    stack: struct { cards: ArrayList(EntityData) },
    hand: struct { cards: ArrayList(EntityData) },
};

const Entity = struct {
    collider: AABB = .{},
    position: zm.Vec = zm.f32x4s(0),
    rotation: f32 = 0,
    velocity: zm.Vec = zm.f32x4s(0),
    size: zm.Vec = zm.f32x4s(1),
    data: EntityData,
};

const Mouse = struct {
    position: zm.Vec = zm.f32x4s(0),
    velocity: zm.Vec = zm.f32x4s(0),
    dragging: ?*Entity = null,
    drag_timer: time.Timer = undefined,
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
    assets.loadAssets();

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

    state.gfx.bind.fs_images[0] = assets.card;

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
        .collider = .{ .tl = zm.f32x4(-50, 70, 0, 0), .br = zm.f32x4(50, -70, 0, 0) },
        .position = zm.f32x4s(0),
        .rotation = 0,
        .size = zm.f32x4(100, 140, 0, 0),
        .data = .{
            .card = .{
                .id = .{ .suit = Suit.hearts, .rank = 2 },
                .flipped = false,
            },
        },
    }) catch unreachable;

    state.world.entities.append(Entity{
        .collider = .{ .tl = zm.f32x4(-50, 70, 0, 0), .br = zm.f32x4(50, -70, 0, 0) },
        .position = zm.f32x4s(0),
        .rotation = 0,
        .size = zm.f32x4(100, 140, 0, 0),
        .data = .{
            .card = .{
                .id = .{ .suit = Suit.clubs, .rank = 13 },
                .flipped = false,
            },
        },
    }) catch unreachable;

    state.gfx.projection = zm.orthographicRhGl(sapp.widthf(), sapp.heightf(), -1, 100);
    state.input.mouse.drag_timer = time.Timer.start() catch @panic("timer not supported");
}

export fn frame() void {
    simgui.newFrame(.{
        .width = sapp.width(),
        .height = sapp.height(),
        .delta_time = sapp.frameDuration(),
        .dpi_scale = sapp.dpiScale(),
    });
    simgui.igSetNextWindowBgAlpha(0);
    simgui.igSetNextWindowPos(simgui.ImVec2{ .x = 0, .y = 0 }, 0, simgui.ImVec2{ .x = 0, .y = 0 });
    simgui.igSetNextWindowSize(simgui.ImVec2{ .x = sapp.widthf(), .y = sapp.heightf() }, 0);
    _ = simgui.igBegin("Window", null, 1 + 2 + 4 + 8 + 256 + 786944); // NoTitleBar|NoResize|NoMove|NoScrollbar|NoSavedSettings|NoInputs
    sg.beginDefaultPass(state.gfx.pass_action, sapp.width(), sapp.height());
    sg.applyPipeline(state.gfx.pip);
    sg.applyBindings(state.gfx.bind);
    for (state.world.entities.items) |*entity| {
        entity.collider.tl = zm.f32x4(-(entity.size[0] / 2) + entity.position[0], entity.size[1] / 2 + entity.position[1], 0, 0);
        entity.collider.br = zm.f32x4(entity.size[0] / 2 + entity.position[0], -(entity.size[1] / 2) + entity.position[1], 0, 0);
        entity.position[0] += entity.velocity[0];
        entity.position[1] -= entity.velocity[1];
        entity.velocity[0] *= 0.8;
        entity.velocity[1] *= 0.8;

        renderEntity(entity.*);
    }
    simgui.igEnd();
    simgui.render();
    sg.endPass();
    sg.commit();
}

// TODO it would be more efficent to batch all of the card draws at the same time
fn renderEntity(entity: Entity) void {
    switch (entity.data) {
        EntityType.card => |data| {
            if (data.flipped) {
                state.gfx.bind.fs_images[0] = assets.card_back;
                sg.applyBindings(state.gfx.bind);

                var card_model = zm.scalingV(entity.size);

                card_model = zm.mul(card_model, zm.rotationZ(entity.rotation));
                card_model = zm.mul(card_model, zm.translationV(entity.position));

                const card_mvp = zm.mul(card_model, state.gfx.projection);

                sg.applyUniforms(.VS, 0, sg.asRange(&.{ .mvp = zm.matToArr(card_mvp) }));
                sg.draw(0, 6, 1);
            } else {
                // render base card
                state.gfx.bind.fs_images[0] = assets.card;
                sg.applyBindings(state.gfx.bind);
                var card_model = zm.scalingV(entity.size);

                card_model = zm.mul(card_model, zm.rotationZ(entity.rotation));
                card_model = zm.mul(card_model, zm.translationV(entity.position));

                const card_mvp = zm.mul(card_model, state.gfx.projection);

                sg.applyUniforms(.VS, 0, sg.asRange(&.{ .mvp = zm.matToArr(card_mvp) }));
                sg.draw(0, 6, 1);

                // render glyph
                state.gfx.bind.fs_images[0] = switch (data.id.suit) {
                    Suit.clubs => assets.clubs,
                    Suit.diamonds => assets.diamonds,
                    Suit.hearts => assets.hearts,
                    Suit.spades => assets.spades,
                };
                sg.applyBindings(state.gfx.bind);
                var glyph_max = std.math.min(entity.size[0], entity.size[1]);
                var glyph_model = zm.scaling(glyph_max / 3, glyph_max / 3, 0);
                glyph_model = zm.mul(glyph_model, zm.rotationZ(entity.rotation));
                glyph_model = zm.mul(glyph_model, zm.translationV(entity.position));
                const glyph_mvp = zm.mul(glyph_model, state.gfx.projection);

                sg.applyUniforms(.VS, 0, sg.asRange(&.{ .mvp = zm.matToArr(glyph_mvp) }));
                sg.draw(0, 6, 1);

                // render numbers
                const draw_list = simgui.igGetWindowDrawList();
                const num = switch (data.id.rank) {
                    1 => "A",
                    2...9 => |v| &[_:0]u8{@as(u8, v) + '0'},
                    10 => "10",
                    11 => "J",
                    12 => "Q",
                    13 => "K",
                    else => "B",
                };

                const color = switch (data.id.suit) {
                    Suit.diamonds, Suit.hearts => assets.suit_red,
                    Suit.clubs, Suit.spades => assets.suit_black,
                };

                simgui.ImDrawList_AddText_Vec2(
                    draw_list,
                    simgui.ImVec2{
                        .x = entity.position[0] + sapp.widthf() / 2 - entity.size[0] / 2 + 8,
                        .y = -entity.position[1] + sapp.heightf() / 2 - entity.size[1] / 2 + 8,
                    },
                    color,
                    &num[0],
                    &num[num.len],
                );
            }
        },
        else => {
            state.gfx.bind.fs_images[0] = assets.card;
            sg.applyBindings(state.gfx.bind);

            var model = zm.scalingV(entity.size);

            model = zm.mul(model, zm.rotationZ(entity.rotation));
            model = zm.mul(model, zm.translationV(entity.position));

            const mvp = zm.mul(model, state.gfx.projection);

            sg.applyUniforms(.VS, 0, sg.asRange(&.{ .mvp = zm.matToArr((mvp)) }));
            sg.draw(0, 6, 1);
        },
    }
}

export fn input(ev: ?*const sapp.Event) void {
    const event = ev.?;
    var mouse = &state.input.mouse;
    switch (event.type) {
        .MOUSE_DOWN => {
            // TODO make some z buffer so i can properly order the entities
            if (event.mouse_button == .LEFT) {
                var i: usize = state.world.entities.items.len;
                while (i > 0) {
                    i -= 1;
                    const entity: *Entity = &state.world.entities.items[i];
                    if (entity.collider.contains(mouse.position)) {
                        mouse.dragging = entity;
                        entity.velocity = zm.f32x4(0, 0, 0, 0);
                        mouse.drag_timer.reset();
                        break;
                    }
                }
            }
        },
        .MOUSE_UP => {
            if (mouse.dragging) |dragging| {
                switch (dragging.data) {
                    EntityType.card => |*data| {
                        dragging.velocity = mouse.velocity;
                        if (mouse.drag_timer.read() < 1.5e8) {
                            data.*.flipped = !data.flipped;
                        }
                    },
                    else => {},
                }
            }

            if (event.mouse_button == .LEFT) {
                mouse.dragging = null;
            }
        },
        .MOUSE_MOVE => {
            mouse.position = zm.f32x4(event.mouse_x - sapp.widthf() / 2, -(event.mouse_y - sapp.heightf() / 2), 0, 0);
            mouse.velocity = zm.f32x4(event.mouse_dx, event.mouse_dy, 0, 0);
            if (mouse.dragging) |drag| {
                drag.position[0] += event.mouse_dx;
                drag.position[1] -= event.mouse_dy;
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
