const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const translate_llvm = b.addTranslateC(.{
        .root_source_file = b.path("src/llvm.h"),
        .target = target,
        .optimize = optimize,
    });

    const llvm_prefix = b.run(&.{ "llvm-config", "--prefix" });
    const llvm_include = b.fmt("{s}/include", .{std.mem.trim(u8, llvm_prefix, "\n")});
    translate_llvm.addIncludePath(.{
        .cwd_relative = llvm_include,
    });

    const exe = b.addExecutable(.{
        .name = "bok",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
            .imports = &.{
                .{
                    .name = "llvm",
                    .module = translate_llvm.createModule(),
                },
            },
        }),
    });

    b.installArtifact(exe);
    const run_step = b.step("run", "Run the app");
    const run_cmd = b.addRunArtifact(exe);
    run_step.dependOn(&run_cmd.step);
    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    exe.root_module.linkSystemLibrary("LLVM", .{});
    const exe_tests = b.addTest(.{
        .root_module = exe.root_module,
    });

    const run_exe_tests = b.addRunArtifact(exe_tests);
    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_exe_tests.step);
}
