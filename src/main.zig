const std = @import("std");
const ArrayList = std.ArrayList;
const sokol = @import("sokol");
const zstbi = @import("zstbi");
const zm = @import("zmath");
const sg = sokol.gfx;
const sapp = sokol.app;
const sgapp = sokol.app_gfx_glue;
const saudio = sokol.audio;
const slog = sokol.log;

var manager = std.heap.GeneralPurposeAllocator(.{}){};
const allocator = manager.allocator();

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

const Entity = struct { texture: sg.Image = .{}, position: zm.Vec = zm.f32x4(0.0, 0.0, 0.0, 0.0), rotation: f32 = 0.0, size: zm.Vec = zm.f32x4(1.0, 1.0, 1.0, 1.0), data: EntityData };

const State = struct {
    gfx: struct {
        bind: sg.Bindings = .{},
        pip: sg.Pipeline = .{},
        pass_action: sg.PassAction = .{},
    } = .{},
    world: struct {
        entities: ArrayList(Entity) = ArrayList(Entity).init(allocator),
    } = .{},
};

var state: State = .{};

export fn init() void {
    sg.setup(.{
        .context = sgapp.context(),
        .logger = .{ .func = slog.func },
    });

    state.gfx.bind.vertex_buffers[0] = sg.makeBuffer(.{ .data = sg.asRange(&[_]f32{
        -1, 1,  0.5, 1.0, 1.0, 1.0, 1.0, 0.0, 0.0,
        1,  1,  0.5, 1.0, 1.0, 1.0, 1.0, 1.0, 0.0,
        -1, -1, 0.5, 1.0, 1.0, 1.0, 1.0, 0.0, 1.0,
        1,  -1, 0.5, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0,
    }) });

    state.gfx.bind.index_buffer = sg.makeBuffer(.{
        .type = .INDEXBUFFER,
        .data = sg.asRange(&[_]u16{ 0, 1, 2, 1, 2, 3 }),
    });

    var image_src: zstbi.Image = zstbi.Image.loadFromFile("./assets/bpfp.png", 4) catch unreachable;

    var image_desc: sg.ImageDesc = .{ .width = 16, .height = 16 };
    image_desc.data.subimage[0][0] = sg.asRange(image_src.data);
    state.gfx.bind.fs_images[0] = sg.makeImage(image_desc);

    const shd = sg.makeShader(glShaderDesc());

    var pip_desc: sg.PipelineDesc = .{
        .index_type = .UINT16,
        .shader = shd,
        .blend_color = .{ .r = 1.0, .g = 0.0, .b = 0.0, .a = 1.0 },
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
        .position = zm.f32x4(1.0, 0.0, 0.0, 0.0),
        .rotation = std.math.pi * 0.25,
        .size = zm.f32x4(2.0, 2.0, 0.0, 0.0),
        .data = .{ .card = .{
            .id = .{ .suit = Suit.hearts, .rank = 2 },
        } },
    }) catch unreachable;
}

export fn frame() void {
    const projection = zm.perspectiveFovRhGl(0.5 * std.math.pi, sapp.widthf() / sapp.heightf(), 0.1, 100.0);
    // const view = zm.lookAtRh(zm.f32x4(0.0, 0.0, 0.0, 0.0), zm.f32x4(0.0, 0.0, 0.0, 0.0), zm.f32x4(0.0, 1.0, 0.0, 0.0));
    // const projection = zm.perspectiveFovRhGl(std.math.pi * 0.5, sapp.widthf() / sapp.heightf(), 0.1, 10.0);
    sg.beginDefaultPass(state.gfx.pass_action, sapp.width(), sapp.height());
    sg.applyPipeline(state.gfx.pip);
    sg.applyBindings(state.gfx.bind);
    for (state.world.entities.items) |entity| {
        renderEntity(entity, projection);
    }
    sg.endPass();
    sg.commit();
}

fn renderEntity(entity: Entity, projection: zm.Mat) void {
    var model = zm.scalingV(entity.size);

    model = zm.mul(model, zm.rotationZ(entity.rotation));
    model = zm.mul(model, zm.translationV(entity.position));

    const view = zm.lookAtRh(
        zm.f32x4(0.0, 0.0, 10.0, 1.0),
        zm.f32x4(0.0, 0.0, 0.0, 1.0),
        zm.f32x4(0.0, 1.0, 0.0, 0.0),
    );

    const object_to_view = zm.mul(model, view);
    const mvp = zm.mul(object_to_view, projection);

    sg.applyUniforms(.VS, 0, sg.asRange(&.{ .mvp = zm.matToArr((mvp)) }));
    sg.draw(0, 6, 1);
}

export fn cleanup() void {
    sg.shutdown();
    zstbi.deinit();
}

pub fn main() !void {
    zstbi.init(allocator);

    sapp.run(.{
        .init_cb = init,
        .frame_cb = frame,
        // .event_cb = input,
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
