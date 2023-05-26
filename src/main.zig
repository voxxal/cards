const std = @import("std");
const time = std.time;
const ArrayList = std.ArrayList; // TODO convert to MultiArrayList
const sokol = @import("sokol");
const zstbi = @import("zstbi");
const zm = @import("zmath");
const Vec2 = @import("./vec2.zig").Vec2;
const assets = @import("./assets.zig");
const Color = @import("./color.zig").Color;
const sg = sokol.gfx;
const sapp = sokol.app;
const sgl = sokol.gl;
const sgapp = sokol.app_gfx_glue;
const saudio = sokol.audio;
const slog = sokol.log;
const simgui = sokol.imgui;
const sfons = sokol.fontstash;

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
    dragged: bool = false,
};

const Mouse = struct {
    position: zm.Vec = zm.f32x4s(0),
    velocity: zm.Vec = zm.f32x4s(0),
    dragging: ?*Entity = null,
    drag_start: zm.Vec = zm.f32x4s(0),
    drag_timer: time.Timer = undefined,
};

const Vertex = packed struct {
    position: zm.Vec,
    tint: Color,
    tex: Vec2,
};

const State = struct {
    gfx: struct {
        fons: sfons.Context = undefined,
        font_normal: i32 = -1,
        font_bold: i32 = -1,
        font_bind: sg.Bindings = .{},
        font_pip: sg.Pipeline = .{},
        bind: sg.Bindings = .{},
        quad_batch: [1024]Vertex = [_]Vertex{undefined} ** 1024,
        quad_batch_index: u16 = 0,
        quad_batch_index_buf: [1024 * 3 / 2]u16 = [_]u16{0} ** (1024 * 3 / 2),
        quad_batch_index_buf_index: u32 = 0,
        quad_batch_tex: sg.Image = .{ .id = 0 },
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

fn flushQuadBatch() void {
    const gfx = &state.gfx;
    if (gfx.quad_batch_tex.id == 0 or gfx.quad_batch_index == 0) return;
    gfx.bind.vertex_buffer_offsets[0] = sg.appendBuffer(gfx.bind.vertex_buffers[0], sg.asRange(&gfx.quad_batch));
    gfx.bind.index_buffer_offset = sg.appendBuffer(gfx.bind.index_buffer, sg.asRange(&gfx.quad_batch_index_buf));
    gfx.bind.fs_images[0] = gfx.quad_batch_tex;
    sg.applyBindings(gfx.bind);
    sg.draw(0, gfx.quad_batch_index_buf_index, 1);
    gfx.quad_batch = std.mem.zeroes([1024]Vertex);
    gfx.quad_batch_index = 0;
    gfx.quad_batch_index_buf = std.mem.zeroes([1024 * 3 / 2]u16);
    gfx.quad_batch_index_buf_index = 0;
}

fn pushQuad(mvp: zm.Mat, texture: sg.Image, tint: Color) void {
    if (texture.id != state.gfx.quad_batch_tex.id) {
        flushQuadBatch();
    }

    state.gfx.quad_batch_tex = texture;
    const tl = zm.mul(zm.f32x4(-0.5, 0.5, 0.5, 1), mvp);
    const tr = zm.mul(zm.f32x4(0.5, 0.5, 0.5, 1), mvp);
    const bl = zm.mul(zm.f32x4(-0.5, -0.5, 0.5, 1), mvp);
    const br = zm.mul(zm.f32x4(0.5, -0.5, 0.5, 1), mvp);
    state.gfx.quad_batch[state.gfx.quad_batch_index + 0] = Vertex{ .position = zm.vecToArr4(tl), .tint = tint, .tex = Vec2.init(0, 1) };
    state.gfx.quad_batch[state.gfx.quad_batch_index + 1] = Vertex{ .position = zm.vecToArr4(tr), .tint = tint, .tex = Vec2.init(1, 1) };
    state.gfx.quad_batch[state.gfx.quad_batch_index + 2] = Vertex{ .position = zm.vecToArr4(bl), .tint = tint, .tex = Vec2.init(0, 0) };
    state.gfx.quad_batch[state.gfx.quad_batch_index + 3] = Vertex{ .position = zm.vecToArr4(br), .tint = tint, .tex = Vec2.init(1, 0) };

    state.gfx.quad_batch_index_buf[state.gfx.quad_batch_index_buf_index + 0] = state.gfx.quad_batch_index + 0;
    state.gfx.quad_batch_index_buf[state.gfx.quad_batch_index_buf_index + 1] = state.gfx.quad_batch_index + 1;
    state.gfx.quad_batch_index_buf[state.gfx.quad_batch_index_buf_index + 2] = state.gfx.quad_batch_index + 2;
    state.gfx.quad_batch_index_buf[state.gfx.quad_batch_index_buf_index + 3] = state.gfx.quad_batch_index + 1;
    state.gfx.quad_batch_index_buf[state.gfx.quad_batch_index_buf_index + 4] = state.gfx.quad_batch_index + 2;
    state.gfx.quad_batch_index_buf[state.gfx.quad_batch_index_buf_index + 5] = state.gfx.quad_batch_index + 3;
    state.gfx.quad_batch_index += 4;
    state.gfx.quad_batch_index_buf_index += 6;
}

export fn init() void {
    sg.setup(.{
        .context = sgapp.context(),
        .logger = .{ .func = slog.func },
    });
    sgl.setup(.{ .logger = .{ .func = slog.func } });
    assets.loadAssets();

    var fons_context = sfons.create(.{
        .width = 512,
        .height = 512,
    });
    state.gfx.fons = fons_context;
    state.gfx.font_normal = state.gfx.fons.addFont("sans", "./assets/fonts/Inter-Regular.ttf") catch @panic("failed to load font");
    state.gfx.font_bold = state.gfx.fons.addFont("sans-bold", "./assets/fonts/Inter-Bold.ttf") catch @panic("failed to load font");

    simgui.setup(.{});
    state.gfx.bind.vertex_buffers[0] = sg.makeBuffer(.{
        .usage = .STREAM,
        .size = 1024 * 11400,
        .label = "quad-vertices",
    });

    state.gfx.bind.index_buffer = sg.makeBuffer(.{
        .type = .INDEXBUFFER,
        .usage = .STREAM,
        .size = 1024 * 11400,
    });

    state.gfx.bind.fs_images[0] = assets.card;

    const shd = sg.makeShader(glShaderDesc());

    var pip_desc: sg.PipelineDesc = .{
        .index_type = .UINT16,
        .shader = shd,
        .blend_color = .{ .r = 1, .g = 0, .b = 0, .a = 1 },
    };

    pip_desc.layout.attrs[0].format = .FLOAT4; // 16
    pip_desc.layout.attrs[1].format = .FLOAT4; // 16
    pip_desc.layout.attrs[2].format = .FLOAT2; // 8
    pip_desc.colors[0].blend = .{
        .enabled = true,
        .src_factor_rgb = .SRC_ALPHA,
        .dst_factor_rgb = .ONE_MINUS_SRC_ALPHA,
    };

    state.gfx.pip = sg.makePipeline(pip_desc);
    state.gfx.pass_action.colors[0] = .{
        .load_action = .CLEAR,
        //FDF6E3
        .clear_value = .{ .r = 0xfdp0 / 0xffp0, .g = 0xf6p0 / 0xffp0, .b = 0xe3p0 / 0xffp0, .a = 1 },
    };

    const suits = [4]Suit{ .spades, .clubs, .diamonds, .hearts };
    for (suits) |suit| {
        var rank: u4 = 1;
        while (rank <= 13) {
            state.world.entities.append(Entity{
                .position = zm.f32x4s(0),
                .rotation = 0,
                .size = zm.f32x4(125, 175, 0, 0),
                .data = .{
                    .card = .{
                        .id = .{ .suit = suit, .rank = @as(u4, rank) },
                        .flipped = true,
                    },
                },
            }) catch unreachable;
            rank += 1;
        }
    }
    const seed = @truncate(u64, @bitCast(u128, std.time.nanoTimestamp()));
    var prng = std.rand.DefaultPrng.init(seed);
    prng.random().shuffle(Entity, state.world.entities.items);

    state.gfx.projection = zm.orthographicRhGl(sapp.widthf(), sapp.heightf(), -1, 100);
    state.input.mouse.drag_timer = time.Timer.start() catch @panic("timer not supported");
}

export fn frame() void {
    sgl.defaults();
    sgl.matrixModeProjection();
    sgl.ortho(0, sapp.widthf(), sapp.heightf(), 0, -1, 1);
    state.gfx.fons.clearState();
    simgui.newFrame(.{
        .width = sapp.width(),
        .height = sapp.height(),
        .delta_time = sapp.frameDuration(),
        .dpi_scale = sapp.dpiScale(),
    });
    sg.beginDefaultPassf(state.gfx.pass_action, sapp.widthf(), sapp.heightf());
    sg.applyPipeline(state.gfx.pip);
    sg.applyBindings(state.gfx.bind);
    var i: i32 = 0;
    for (state.world.entities.items) |*entity| {
        buildFontTextures(entity.*, i);
        i += 1;
    }
    sfons.flush(state.gfx.fons);
    i = 0;
    for (state.world.entities.items) |*entity| {
        entity.collider.tl = zm.f32x4(-(entity.size[0] / 2) + entity.position[0], entity.size[1] / 2 + entity.position[1], 0, 0);
        entity.collider.br = zm.f32x4(entity.size[0] / 2 + entity.position[0], -(entity.size[1] / 2) + entity.position[1], 0, 0);
        entity.position[0] += entity.velocity[0];
        entity.position[1] -= entity.velocity[1];
        entity.velocity[0] *= 0.65;
        entity.velocity[1] *= 0.65;

        renderEntity(entity.*, i);
        i += 1;
    }
    flushQuadBatch();
    simgui.render();
    sg.endPass();
    sg.commit();
}

fn buildFontTextures(entity: Entity, i: i32) void {
    switch (entity.data) {
        EntityType.card => |data| {
            const color = switch (data.id.suit) {
                Suit.diamonds, Suit.hearts => assets.colors.red,
                Suit.clubs, Suit.spades => assets.colors.black,
            };

            const num = switch (data.id.rank) {
                1 => "A",
                2...9 => |v| &[_:0]u8{@as(u8, v) + '0'},
                10 => "10",
                11 => "J",
                12 => "Q",
                13 => "K",
                else => "B",
            };

            if (state.gfx.font_normal != -1) {
                sgl.layer(i);

                state.gfx.fons.setSize(entity.size[0] / 4);
                state.gfx.fons.setColor(color.toInt());
                _ = state.gfx.fons.drawText(
                    entity.position[0] + sapp.widthf() / 2 - entity.size[0] / 2 + 8,
                    -entity.position[1] + sapp.heightf() / 2 - entity.size[1] / 2 + 8 + entity.size[0] / 6,
                    num,
                );
            }
        },
        else => @panic("not impl"),
    }
}

fn renderEntity(entity: Entity, i: i32) void {
    switch (entity.data) {
        EntityType.card => |data| {
            if (entity.dragged) {
                var outline_model = zm.scalingV(zm.f32x4(entity.size[0] + 6, entity.size[1] + 6, entity.size[2], entity.size[3]));

                outline_model = zm.mul(outline_model, zm.rotationZ(entity.rotation));
                outline_model = zm.mul(outline_model, zm.translationV(entity.position));

                const mvp = zm.mul(outline_model, state.gfx.projection);
                pushQuad(mvp, assets.card_outline, assets.colors.blue);
            }

            var card_model = zm.scalingV(entity.size);

            card_model = zm.mul(card_model, zm.rotationZ(entity.rotation));
            card_model = zm.mul(card_model, zm.translationV(entity.position));

            const card_mvp = zm.mul(card_model, state.gfx.projection);

            pushQuad(card_mvp, assets.card, assets.colors.bg_dim);

            if (data.flipped) {
                var back_model = zm.scalingV(zm.f32x4(entity.size[0] - 8, entity.size[1] - 8, entity.size[2], entity.size[3]));

                back_model = zm.mul(back_model, zm.rotationZ(entity.rotation));
                back_model = zm.mul(back_model, zm.translationV(entity.position));

                const mvp = zm.mul(back_model, state.gfx.projection);

                pushQuad(mvp, assets.card_back, assets.colors.black);
                pushQuad(mvp, assets.card_back_lines, assets.colors.white);
            } else {
                // render glyph
                var glyph_max = std.math.min(entity.size[0], entity.size[1]);
                var glyph_model = zm.scaling(glyph_max / 3, glyph_max / 3, 0);
                glyph_model = zm.mul(glyph_model, zm.rotationZ(entity.rotation));
                glyph_model = zm.mul(glyph_model, zm.translationV(entity.position));
                const glyph_mvp = zm.mul(glyph_model, state.gfx.projection);

                const color = switch (data.id.suit) {
                    Suit.diamonds, Suit.hearts => assets.colors.red,
                    Suit.clubs, Suit.spades => assets.colors.black,
                };

                pushQuad(glyph_mvp, switch (data.id.suit) {
                    Suit.clubs => assets.clubs,
                    Suit.diamonds => assets.diamonds,
                    Suit.hearts => assets.hearts,
                    Suit.spades => assets.spades,
                }, color);

                // render numbers
                // const num = switch (data.id.rank) {
                //     1 => "A",
                //     2...9 => |v| &[_:0]u8{@as(u8, v) + '0'},
                //     10 => "10",
                //     11 => "J",
                //     12 => "Q",
                //     13 => "K",
                //     else => "B",
                // };

                sgl.defaults();
                sgl.matrixModeProjection();
                sgl.ortho(0, sapp.widthf(), sapp.heightf(), 0, -1, 1);
                sgl.drawLayer(i);
                sg.applyPipeline(state.gfx.pip);
                sg.applyBindings(state.gfx.bind);
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
            if (event.mouse_button == .LEFT) {
                var i: usize = state.world.entities.items.len;
                while (i > 0) {
                    i -= 1;
                    const entity: *Entity = &state.world.entities.items[i];
                    if (entity.collider.contains(mouse.position)) {
                        // memory inefficent? what???
                        state.world.entities.append(state.world.entities.orderedRemove(i)) catch unreachable;
                        const new = &state.world.entities.items[state.world.entities.items.len - 1];
                        mouse.dragging = new;
                        mouse.drag_start = new.position;
                        mouse.drag_timer.reset();
                        new.velocity = zm.f32x4(0, 0, 0, 0);
                        new.dragged = true;
                        break;
                    }
                }
            }
        },
        .MOUSE_UP => {
            if (mouse.dragging) |dragging| {
                if (event.mouse_button == .LEFT) {
                    dragging.dragged = false;
                    switch (dragging.data) {
                        EntityType.card => |*data| {
                            dragging.velocity = mouse.velocity;
                            if (std.math.hypot(
                                f32,
                                dragging.position[0] - mouse.drag_start[0],
                                dragging.position[1] - mouse.drag_start[1],
                            ) < 25 and mouse.drag_timer.read() < 5e8) {
                                data.*.flipped = !data.flipped;
                            }
                        },
                        else => {},
                    }
                    mouse.dragging = null;
                }
            }
        },
        .MOUSE_MOVE => {
            mouse.position = zm.f32x4(event.mouse_x - sapp.widthf() / 2, -(event.mouse_y - sapp.heightf() / 2), 0, 0);

            mouse.velocity = zm.f32x4(
                if (event.mouse_dx >= -2 and event.mouse_dx <= 2) 0 else event.mouse_dx,
                if (event.mouse_dy >= -2 and event.mouse_dx <= 2) 0 else event.mouse_dy,
                0,
                0,
            );
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
    simgui.shutdown();
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
        .sample_count = 4,
    });
}

fn glShaderDesc() sg.ShaderDesc {
    var desc: sg.ShaderDesc = .{};
    desc.attrs[0].name = "position";
    desc.attrs[1].name = "color0";
    desc.attrs[2].name = "texcoord0";
    desc.fs.images[0] = .{ .name = "tex", .image_type = ._2D };
    // desc.vs.uniform_blocks[0].size = 64;
    // desc.vs.uniform_blocks[0].uniforms[0].name = "mvp";
    // desc.vs.uniform_blocks[0].uniforms[0].type = .MAT4;
    desc.vs.source = @embedFile("./shaders/vs.glsl");
    desc.fs.source = @embedFile("./shaders/fs.glsl");

    return desc;
}
