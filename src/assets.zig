const zstbi = @import("zstbi");
const sg = @import("sokol").gfx;
const Color = @import("./color.zig").Color;

pub const root = "/assets";

fn loadImage(path: [:0]const u8, desc: sg.ImageDesc) sg.Image {
    var image_src: zstbi.Image = zstbi.Image.loadFromFile(path, 4) catch unreachable;
    defer zstbi.Image.deinit(&image_src);

    var image_desc: sg.ImageDesc = desc;
    image_desc.data.subimage[0][0] = sg.asRange(image_src.data);
    return sg.makeImage(image_desc);
}

pub var card: sg.Image = undefined;
pub var card_outline: sg.Image = undefined;
pub var card_back: sg.Image = undefined;
pub var card_back_lines: sg.Image = undefined;
pub var clubs: sg.Image = undefined;
pub var diamonds: sg.Image = undefined;
pub var hearts: sg.Image = undefined;
pub var spades: sg.Image = undefined;

pub fn loadAssets() void {
    card = loadImage("./assets/card.png", .{ .width = 400, .height = 560 });
    card_outline = loadImage("./assets/card_outline.png", .{ .width = 424, .height = 584 });
    card_back = loadImage("./assets/card_back.png", .{ .width = 368, .height = 528 });
    card_back_lines = loadImage("./assets/card_back_lines.png", .{ .width = 368, .height = 528 });
    clubs = loadImage("./assets/clubs.png", .{ .width = 64, .height = 64 });
    diamonds = loadImage("./assets/diamonds.png", .{ .width = 64, .height = 64 });
    hearts = loadImage("./assets/hearts.png", .{ .width = 64, .height = 64 });
    spades = loadImage("./assets/spades.png", .{ .width = 64, .height = 64 });
}

pub const colors = struct {
    pub const white = Color.rgb255(0xff, 0xff, 0xff);
    pub const black = Color.rgb255(0x5c, 0x6a, 0x72);
    pub const red = Color.rgb255(0xf8, 0x55, 0x52);
    pub const blue = Color.rgb255(0x3a, 0x94, 0xc5);
    pub const bg_dim = Color.rgb255(0xef, 0xeb, 0xd4);
};
