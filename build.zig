const std = @import("std");
const sokol = @import("lib/sokol-zig/build.zig");
const zstbi = @import("lib/zstbi/build.zig");
const zmath = @import("lib/zmath/build.zig");

pub fn build(b: *std.Build) void {
    // Standard target options allows the person running `zig build` to choose
    // what target to build for. Here we do not override the defaults, which
    // means any target is allowed, and the default is native. Other options
    // for restricting supported target set are available.
    const target = b.standardTargetOptions(.{});

    // Standard release options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall.
    const optimize = b.standardOptimizeOption(.{});

    const sokol_build = sokol.buildSokol(b, target, optimize, .{}, "lib/sokol-zig/");
    const zstbi_pkg = zstbi.package(b, target, optimize, .{});
    const zmath_pkg = zmath.package(b, target, optimize, .{
        .options = .{ .enable_cross_platform_determinism = true },
    });

    const exe = b.addExecutable(.{
        .name = "cards",
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });

    exe.addAnonymousModule("sokol", .{ .source_file = .{ .path = "lib/sokol-zig/src/sokol/sokol.zig" } });
    exe.linkLibrary(sokol_build);
    const sokol_path = "lib/sokol-zig/src/sokol/c/";

    // Build imgui
    exe.addIncludePath(sokol_path ++ "imgui");
    exe.addSystemIncludePath(sokol_path ++ "imgui");
    exe.addIncludePath(sokol_path);
    exe.addSystemIncludePath(sokol_path);

    exe.addCSourceFiles(&[_][]const u8{
        sokol_path ++ "cimgui.cpp",
        sokol_path ++ "imgui/imgui.cpp",
        sokol_path ++ "imgui/imgui_demo.cpp",
        sokol_path ++ "imgui/imgui_draw.cpp",
        sokol_path ++ "imgui/imgui_widgets.cpp",
        sokol_path ++ "imgui/imgui_tables.cpp",
    }, &[_][]const u8{});
    exe.linkLibCpp();

    zstbi_pkg.link(exe);
    zmath_pkg.link(exe);

    exe.install();

    const run_cmd = exe.run();
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);
}
