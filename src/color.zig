pub const Color = packed struct {
    r: f32,
    g: f32,
    b: f32,
    a: f32,

    pub fn rgba(r: f32, g: f32, b: f32, a: f32) Color {
        return Color{
            .r = r,
            .g = g,
            .b = b,
            .a = a,
        };
    }

    pub fn rgb255(r: f32, g: f32, b: f32) Color {
        return Color{
            .r = r / 0xff,
            .g = g / 0xff,
            .b = b / 0xff,
            .a = 1,
        };
    }

    pub fn rgba255(r: f32, g: f32, b: f32, a: f32) Color {
        return Color{
            .r = r / 0xff,
            .g = g / 0xff,
            .b = b / 0xff,
            .a = a / 0xff,
        };
    }

    pub fn toImColor(self: Color) u32 {
        return @floatToInt(u32, self.r * 255) << 0 |
            @floatToInt(u32, self.g * 255) << 8 |
            @floatToInt(u32, self.b * 255) << 16 |
            @floatToInt(u32, self.a * 255) << 24;
    }

    pub fn toArr(self: Color) [4]f32 {
        return .{ self.r, self.g, self.b, self.a };
    }
};
