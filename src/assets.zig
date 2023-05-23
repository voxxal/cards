const zstbi = @import("zstbi");
const sg = @import("sokol").gfx;

pub const root = "/assets";

fn loadImage(path: [:0]const u8, desc: sg.ImageDesc) sg.Image {
    var image_src: zstbi.Image = zstbi.Image.loadFromFile(path, 4) catch unreachable;
    defer zstbi.Image.deinit(&image_src);

    var image_desc: sg.ImageDesc = desc;
    image_desc.data.subimage[0][0] = sg.asRange(image_src.data);
    return sg.makeImage(image_desc);
}

pub var card: sg.Image = undefined;
pub var card_back: sg.Image = undefined;
pub var card_outline: sg.Image = undefined;
pub var clubs: sg.Image = undefined;
pub var diamonds: sg.Image = undefined;
pub var hearts: sg.Image = undefined;
pub var spades: sg.Image = undefined;

pub fn loadAssets() void {
    card = loadImage("./assets/card.png", .{ .width = 100, .height = 140 });
    card_back = loadImage("./assets/card_back.png", .{ .width = 400, .height = 560 });
    card_outline = loadImage("./assets/card_outline.png", .{ .width = 100, .height = 140 });
    clubs = loadImage("./assets/clubs.png", .{ .width = 64, .height = 64 });
    diamonds = loadImage("./assets/diamonds.png", .{ .width = 64, .height = 64 });
    hearts = loadImage("./assets/hearts.png", .{ .width = 64, .height = 64 });
    spades = loadImage("./assets/spades.png", .{ .width = 64, .height = 64 });
}

pub const suit_black: u32 = 0xff2e2a23;
pub const suit_red: u32 = 0xff5255f8;
