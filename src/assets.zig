const zstbi = @import("zstbi");
const sg = @import("sokol").gfx;

pub const root = "/assets";

fn loadImage(path: [:0]u8, desc: sg.ImageDesc) sg.Image {
    var image_src: zstbi.Image = zstbi.Image.loadFromFile(path, 4) catch unreachable;
    defer zstbi.Image.deinit(&image_src);

    var image_desc: sg.ImageDesc = .{ .width = 16, .height = 16 };
    desc.data.subimage[0][0] = sg.asRange(image_src.data);
    return sg.makeImage(image_desc);
}

pub const bpfp = loadImage("./assets", .{ .width = 16, .height = 16 });
