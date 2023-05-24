const zm = @import("zmath");

pub const Vec2 = packed struct {
    x: f32,
    y: f32,

    pub fn init(x: f32, y: f32) Vec2 {
        return Vec2{
            .x = x,
            .y = y,
        };
    }

    pub fn add(self: Vec2, other: Vec2) Vec2 {
        return Vec2{
            .x = self.x + other.x,
            .y = self.y + self.y,
        };
    }

    pub fn sub(self: Vec2, other: Vec2) Vec2 {
        return Vec2{
            .x = self.x - other.x,
            .y = self.y - self.y,
        };
    }

    pub fn toZm(self: Vec2) zm.Vec {
        return zm.f32x4(self.x, self.y, 1, 1);
    }
};
