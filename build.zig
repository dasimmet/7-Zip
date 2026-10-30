const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const src = b.dependency("sevenzip_src", .{});
    const ubsan = b.option(bool, "ubsan", "force enable ubsan") orelse false;
    const strip = b.option(bool, "strip", "strip debug symbols");
    const linkage: std.builtin.LinkMode = b.option(
        std.builtin.LinkMode,
        "linkage",
        "std.builtin.LinkMode of lib7z",
    ) orelse .static;

    const res = buildOptions(.{
        .b = b,
        .src = src,
        .target = target,
        .optimize = optimize,
        .ubsan = ubsan,
        .strip = strip,
        .linkage = linkage,
    });

    b.installArtifact(res.exe);

    // override install lib dir to bin for windows-style dlopen to work
    const install_so = b.addInstallArtifact(res.libsevenzip, .{
        .dest_dir = .{ .override = switch (linkage) {
            .dynamic => .bin,
            .static => .lib,
        } },
        .dest_sub_path = switch (linkage) {
            .static => null,
            .dynamic => switch (target.result.os.tag) {
                .windows => null,
                else => "7z.so",
            },
        },
    });
    b.getInstallStep().dependOn(&install_so.step);

    const install_sfx_con = b.addInstallArtifact(res.sfx_con, .{
        .dest_dir = .{ .override = .bin },
        .dest_sub_path = "7zCon.sfx",
    });
    b.getInstallStep().dependOn(&install_sfx_con.step);

    const sfx = b.step("sfx", "build sfx modules");
    sfx.dependOn(&install_sfx_con.step);

    if (res.sfx_s2) |s2| {
        const install_s2 = b.addInstallArtifact(s2, .{
            .dest_dir = .{ .override = .bin },
            .dest_sub_path = "7zS2.sfx",
        });
        b.getInstallStep().dependOn(&install_s2.step);
        sfx.dependOn(&install_s2.step);
    }

    if (res.sfx_s2con) |s2con| {
        const install_s2con = b.addInstallArtifact(s2con, .{
            .dest_dir = .{ .override = .bin },
            .dest_sub_path = "7zS2con.sfx",
        });
        b.getInstallStep().dependOn(&install_s2con.step);
        sfx.dependOn(&install_s2con.step);
    }

    const gui_step = b.step("gui", "build GUI");
    if (res.gui) |gui| {
        const install_gui = b.addInstallArtifact(gui, .{
            .dest_dir = .{ .override = .bin },
            .dest_sub_path = "7zG.exe",
        });
        b.getInstallStep().dependOn(&install_gui.step);
        gui_step.dependOn(&install_gui.step);
    }

    const fm_step = b.step("fm", "build File Manager");
    const filemanager_step = b.step("filemanager", "build File Manager");
    if (res.fm) |fm| {
        const install_fm = b.addInstallArtifact(fm, .{
            .dest_dir = .{ .override = .bin },
            .dest_sub_path = "7zFM.exe",
        });
        b.getInstallStep().dependOn(&install_fm.step);
        fm_step.dependOn(&install_fm.step);
        filemanager_step.dependOn(&install_fm.step);
    }

    const ci = b.step("ci", "ci target");
    inline for (&.{
        "x86_64-linux-musl",
        "x86_64-linux-gnu",
        "aarch64-linux-musl",
        "aarch64-linux-gnu",
        "x86_64-macos-none",
        "aarch64-macos-none",
        "x86_64-windows-gnu",
        // "aarch64-windows-gnu",
    }) |target_str| {
        const ci_wf = b.addWriteFiles();
        for (@as([]const std.builtin.LinkMode, &.{
            .dynamic,
            .static,
        })) |ci_linkage| {
            const parsed_query = std.Build.parseTargetQuery(.{
                .arch_os_abi = target_str,
            }) catch @panic("invalid target query: " ++ target_str);

            const ci_target = b.resolveTargetQuery(parsed_query);
            const ci_res = buildOptions(.{
                .b = b,
                .src = src,
                .target = ci_target,
                .optimize = optimize,
                .ubsan = ubsan,
                .linkage = ci_linkage,
            });

            const arc_base = "7z-" ++ target_str;

            _ = ci_wf.addCopyFile(
                ci_res.exe.getEmittedBin(),
                b.fmt("{s}/bin/{s}{s}", .{
                    arc_base,
                    ci_res.exe.name,
                    ci_target.result.exeFileExt(),
                }),
            );

            _ = ci_wf.addCopyFile(
                ci_res.libsevenzip.getEmittedBin(),
                b.fmt("{s}/{s}/7z{s}", .{
                    arc_base,
                    switch (ci_linkage) {
                        .static => "lib",
                        .dynamic => "bin",
                    },
                    switch (ci_linkage) {
                        .static => ci_target.result.staticLibSuffix(),
                        .dynamic => switch (ci_target.result.os.tag) {
                            .windows => ci_target.result.dynamicLibSuffix(),
                            else => ".so",
                        },
                    },
                }),
            );

            _ = ci_wf.addCopyFile(
                ci_res.sfx_con.getEmittedBin(),
                b.fmt("{s}/bin/7zCon.sfx", .{arc_base}),
            );

            if (ci_res.sfx_s2) |s2| {
                _ = ci_wf.addCopyFile(
                    s2.getEmittedBin(),
                    b.fmt("{s}/bin/7zS2.sfx", .{arc_base}),
                );
            }

            if (ci_res.sfx_s2con) |s2con| {
                _ = ci_wf.addCopyFile(
                    s2con.getEmittedBin(),
                    b.fmt("{s}/bin/7zS2con.sfx", .{arc_base}),
                );
            }

            if (ci_res.gui) |gui| {
                _ = ci_wf.addCopyFile(
                    gui.getEmittedBin(),
                    b.fmt("{s}/bin/7zG.exe", .{arc_base}),
                );
            }

            if (ci_res.fm) |fm| {
                _ = ci_wf.addCopyFile(
                    fm.getEmittedBin(),
                    b.fmt("{s}/bin/7zFM.exe", .{arc_base}),
                );
            }

            const run = b.addRunArtifact(res.exe);
            run.addArg("a");
            run.addArg("-tzip");

            const archive = b.addInstallFile(
                run.addOutputFileArg(
                    arc_base ++ ".zip",
                ),
                arc_base ++ ".zip",
            );

            run.addDirectoryArg(ci_wf.getDirectory().path(b, arc_base));

            ci.dependOn(&archive.step);
        }
    }
}

pub const BuildOptions = struct {
    b: *std.Build,
    src: *std.Build.Dependency,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    ubsan: bool,
    linkage: std.builtin.LinkMode,
    strip: ?bool = null,
};

pub const BuildResults = struct {
    exe: *std.Build.Step.Compile,
    libsevenzip: *std.Build.Step.Compile,
    sfx_con: *std.Build.Step.Compile,
    sfx_s2: ?*std.Build.Step.Compile = null,
    sfx_s2con: ?*std.Build.Step.Compile = null,
    gui: ?*std.Build.Step.Compile = null,
    fm: ?*std.Build.Step.Compile = null,
};

pub fn buildOptions(opt: BuildOptions) BuildResults {
    const cppflags: []const []const u8 = if (opt.ubsan)
        &Common.cppflags
    else
        &(Common.cppflags ++ Common.ubsan_flags);

    const cflags: []const []const u8 = if (opt.ubsan)
        &Common.cflags
    else
        &(Common.cflags ++ Common.ubsan_flags);

    const libsevenzip = blk: {
        const mod = opt.b.createModule(.{
            .target = opt.target,
            .optimize = opt.optimize,
            .link_libc = true,
            .link_libcpp = true,
            .strip = opt.strip,
        });

        mod.addCSourceFiles(.{
            .root = opt.src.path("C"),
            .files = &Lib7zip.c_src,
            .flags = cflags,
        });

        mod.addCSourceFiles(.{
            .root = opt.src.path("CPP"),
            .files = &Lib7zip.cpp_src,
            .flags = cppflags,
        });
        inline for (Lib7zip.defs) |def| {
            mod.addCMacro(def[0], def[1]);
        }

        mod.addWin32ResourceFile(.{
            .file = opt.src.path("CPP/7zip/Bundles/Format7z/resource.rc"),
        });

        if (opt.target.result.os.tag == .windows) {
            mod.addCSourceFiles(.{
                .root = opt.src.path("CPP"),
                .files = &Lib7zip.Win.cpp_src,
                .flags = cppflags,
            });

            inline for (Lib7zip.Win.defs) |def| {
                mod.addCMacro(def[0], def[1]);
            }
            mod.linkSystemLibrary("oleaut32", .{});
        }

        const lib = opt.b.addLibrary(.{
            .name = "7z",
            .root_module = mod,
            .linkage = opt.linkage,
            .win32_module_definition = opt.src.path("CPP/7zip/Archive/Archive2.def"),
        });

        break :blk lib;
    };

    const exe = blk: {
        const mod = opt.b.createModule(.{
            .target = opt.target,
            .optimize = opt.optimize,
            .link_libc = true,
            .link_libcpp = true,
            .strip = opt.strip,
        });

        if (opt.linkage == .dynamic) {
            mod.addCSourceFiles(.{
                .root = opt.src.path("C"),
                .files = &Client.c_src,
                .flags = cflags,
            });

            mod.addCSourceFiles(.{
                .root = opt.src.path("CPP"),
                .files = &Client.cpp_src,
                .flags = cppflags,
            });
            inline for (Client.defs) |def| {
                mod.addCMacro(def[0], def[1]);
            }
            if (opt.target.result.os.tag == .windows) {
                mod.addCSourceFiles(.{
                    .root = opt.src.path("C"),
                    .files = &Client.Win.c_src,
                    .flags = cflags,
                });

                mod.addCSourceFiles(.{
                    .root = opt.src.path("CPP"),
                    .files = &Client.Win.cpp_src,
                    .flags = cppflags,
                });

                inline for (Client.Win.defs) |def| {
                    mod.addCMacro(def[0], def[1]);
                }
                mod.linkSystemLibrary("oleaut32", .{});
            }

            const exe = opt.b.addExecutable(.{
                .name = "7z",
                .root_module = mod,
            });
            exe.step.dependOn(&libsevenzip.step);

            break :blk exe;
        } else {
            mod.addCSourceFiles(.{
                .root = opt.src.path("C"),
                .files = &SevenZipZ.c_src,
                .flags = cflags,
            });

            mod.addCSourceFiles(.{
                .root = opt.src.path("CPP"),
                .files = &SevenZipZ.cpp_src,
                .flags = cppflags,
            });
            inline for (SevenZipZ.defs) |def| {
                mod.addCMacro(def[0], def[1]);
            }
            if (opt.target.result.os.tag == .windows) {
                mod.addCSourceFiles(.{
                    .root = opt.src.path("CPP"),
                    .files = &SevenZipZ.Win.cpp_src,
                    .flags = cppflags,
                });

                inline for (SevenZipZ.Win.defs) |def| {
                    mod.addCMacro(def[0], def[1]);
                }
                mod.linkSystemLibrary("oleaut32", .{});
            }

            const exe = opt.b.addExecutable(.{
                .name = "7zz",
                .root_module = mod,
            });

            break :blk exe;
        }
    };

    const sfx_con = blk: {
        const mod = opt.b.createModule(.{
            .target = opt.target,
            .optimize = opt.optimize,
            .link_libc = true,
            .link_libcpp = true,
            .strip = opt.strip orelse true,
        });

        mod.addCSourceFiles(.{
            .root = opt.src.path("C"),
            .files = &SfxCon.c_src,
            .flags = cflags,
        });

        mod.addCSourceFiles(.{
            .root = opt.src.path("CPP"),
            .files = &SfxCon.cpp_src,
            .flags = cppflags,
        });

        inline for (SfxCon.defs) |def| {
            mod.addCMacro(def[0], def[1]);
        }

        if (opt.target.result.os.tag == .windows) {
            mod.addCSourceFiles(.{
                .root = opt.src.path("C"),
                .files = &SfxCon.Win.c_src,
                .flags = cflags,
            });

            mod.addCSourceFiles(.{
                .root = opt.src.path("CPP"),
                .files = &SfxCon.Win.cpp_src,
                .flags = cppflags,
            });

            inline for (SfxCon.Win.defs) |def| {
                mod.addCMacro(def[0], def[1]);
            }

            mod.addWin32ResourceFile(.{
                .file = opt.src.path("CPP/7zip/Bundles/SFXCon/resource.rc"),
            });

            mod.linkSystemLibrary("oleaut32", .{});
        }

        const sfx_exe = opt.b.addExecutable(.{
            .name = "7zCon.sfx",
            .root_module = mod,
        });

        break :blk sfx_exe;
    };

    const sfx_s2 = if (opt.target.result.os.tag == .windows) blk: {
        const s2_cflags: []const []const u8 = if (opt.ubsan)
            &(Common.cflags ++ SfxS2.cflags)
        else
            &(Common.cflags ++ Common.ubsan_flags ++ SfxS2.cflags);

        const mod = opt.b.createModule(.{
            .target = opt.target,
            .optimize = opt.optimize,
            .link_libc = true,
            .strip = opt.strip orelse true,
        });

        mod.addCSourceFiles(.{
            .root = opt.src.path("C"),
            .files = &SfxS2.c_src,
            .flags = s2_cflags,
        });

        inline for (SfxS2.defs) |def| {
            mod.addCMacro(def[0], def[1]);
        }

        mod.addWin32ResourceFile(.{
            .file = opt.src.path("C/Util/SfxSetup/resource.rc"),
        });

        const s2_exe = opt.b.addExecutable(.{
            .name = "7zS2.sfx",
            .root_module = mod,
        });
        s2_exe.subsystem = .windows;

        break :blk s2_exe;
    } else null;

    const sfx_s2con = if (opt.target.result.os.tag == .windows) blk: {
        const s2_cflags: []const []const u8 = if (opt.ubsan)
            &(Common.cflags ++ SfxS2.cflags)
        else
            &(Common.cflags ++ Common.ubsan_flags ++ SfxS2.cflags);

        const mod = opt.b.createModule(.{
            .target = opt.target,
            .optimize = opt.optimize,
            .link_libc = true,
            .strip = opt.strip orelse true,
        });

        mod.addCSourceFiles(.{
            .root = opt.src.path("C"),
            .files = &SfxS2.c_src,
            .flags = s2_cflags,
        });

        inline for (SfxS2.defs ++ .{.{ "_CONSOLE", "" }}) |def| {
            mod.addCMacro(def[0], def[1]);
        }

        mod.addWin32ResourceFile(.{
            .file = opt.src.path("C/Util/SfxSetup/resource.rc"),
        });

        const s2con_exe = opt.b.addExecutable(.{
            .name = "7zS2con.sfx",
            .root_module = mod,
        });
        s2con_exe.subsystem = .console;

        break :blk s2con_exe;
    } else null;

    const win_headers = if (opt.target.result.os.tag == .windows) blk: {
        const wf = opt.b.addWriteFiles();
        inline for (&.{
            .{ "CommCtrl.h", "commctrl.h" },
            .{ "HtmlHelp.h", "htmlhelp.h" },
            .{ "MAPI.h", "mapi.h" },
            .{ "NTSecAPI.h", "ntsecapi.h" },
            .{ "OleCtl.h", "olectl.h" },
            .{ "Psapi.h", "psapi.h" },
            .{ "ShObjIdl.h", "shobjidl.h" },
            .{ "ShlGuid.h", "shlguid.h" },
            .{ "ShlObj.h", "shlobj.h" },
            .{ "Shlwapi.h", "shlwapi.h" },
            .{ "TlHelp32.h", "tlhelp32.h" },
        }) |h| {
            _ = wf.add(h[0], "#pragma once\n#include <" ++ h[1] ++ ">\n");
        }
        break :blk wf;
    } else null;

    const gui = if (opt.target.result.os.tag == .windows) blk: {
        const mod = opt.b.createModule(.{
            .target = opt.target,
            .optimize = opt.optimize,
            .link_libc = true,
            .link_libcpp = true,
            .strip = opt.strip,
        });

        mod.addIncludePath(win_headers.?.getDirectory());

        mod.addCSourceFiles(.{
            .root = opt.src.path("C"),
            .files = &Gui.c_src,
            .flags = cflags,
        });

        mod.addCSourceFiles(.{
            .root = opt.src.path("CPP"),
            .files = &Gui.cpp_src,
            .flags = cppflags,
        });

        inline for (Gui.defs) |def| {
            mod.addCMacro(def[0], def[1]);
        }

        mod.addWin32ResourceFile(.{
            .file = opt.src.path("CPP/7zip/UI/GUI/resource.rc"),
            .include_paths = &.{
                win_headers.?.getDirectory(),
                opt.src.path("CPP"),
                opt.src.path("CPP/7zip/UI/GUI"),
                opt.src.path("CPP/7zip/UI/FileManager"),
            },
        });

        mod.linkSystemLibrary("comctl32", .{});
        mod.linkSystemLibrary("comdlg32", .{});
        mod.linkSystemLibrary("gdi32", .{});
        mod.linkSystemLibrary("htmlhelp", .{});
        mod.linkSystemLibrary("ole32", .{});
        mod.linkSystemLibrary("oleaut32", .{});
        mod.linkSystemLibrary("shell32", .{});
        mod.linkSystemLibrary("uuid", .{});

        const gui_exe = opt.b.addExecutable(.{
            .name = "7zG",
            .root_module = mod,
        });
        gui_exe.subsystem = .windows;
        if (opt.linkage == .dynamic) {
            gui_exe.step.dependOn(&libsevenzip.step);
        }

        break :blk gui_exe;
    } else null;

    const fm = if (opt.target.result.os.tag == .windows) blk: {
        const mod = opt.b.createModule(.{
            .target = opt.target,
            .optimize = opt.optimize,
            .link_libc = true,
            .link_libcpp = true,
            .strip = opt.strip,
        });

        mod.addIncludePath(win_headers.?.getDirectory());

        mod.addCSourceFiles(.{
            .root = opt.src.path("C"),
            .files = &Fm.c_src,
            .flags = cflags,
        });

        mod.addCSourceFiles(.{
            .root = opt.src.path("CPP"),
            .files = &Fm.cpp_src,
            .flags = cppflags,
        });

        inline for (Fm.defs) |def| {
            mod.addCMacro(def[0], def[1]);
        }

        mod.addWin32ResourceFile(.{
            .file = opt.src.path("CPP/7zip/Bundles/Fm/resource.rc"),
            .include_paths = &.{
                win_headers.?.getDirectory(),
                opt.src.path("CPP"),
                opt.src.path("CPP/7zip/Bundles/Fm"),
                opt.src.path("CPP/7zip/UI/FileManager"),
                opt.src.path("CPP/7zip/UI/GUI"),
            },
        });

        mod.linkSystemLibrary("comctl32", .{});
        mod.linkSystemLibrary("comdlg32", .{});
        mod.linkSystemLibrary("gdi32", .{});
        mod.linkSystemLibrary("htmlhelp", .{});
        mod.linkSystemLibrary("mpr", .{});
        mod.linkSystemLibrary("ole32", .{});
        mod.linkSystemLibrary("oleaut32", .{});
        mod.linkSystemLibrary("shell32", .{});
        mod.linkSystemLibrary("uuid", .{});

        const fm_exe = opt.b.addExecutable(.{
            .name = "7zFM",
            .root_module = mod,
        });
        fm_exe.subsystem = .windows;

        break :blk fm_exe;
    } else null;

    return .{
        .exe = exe,
        .libsevenzip = libsevenzip,
        .sfx_con = sfx_con,
        .sfx_s2 = sfx_s2,
        .sfx_s2con = sfx_s2con,
        .gui = gui,
        .fm = fm,
    };
}

const Common = struct {
    const ubsan_flags = .{
        "-fno-sanitize=undefined",
        "-fno-sanitize=integer",
    };

    const cflags = commonflags;

    const commonflags = .{
        "-Werror",
        "-Wall",
        "-Wextra",
        "-Weverything",
        "-Wfatal-errors",
        "-Wno-error=alloca",
        "-Wno-error=unused-command-line-argument",
    };

    const cppflags = commonflags ++ .{
        "-Wno-error=cast-qual",
        "-Wno-error=disabled-macro-expansion",
        "-Wno-missing-prototypes",
        "-Wno-strict-prototypes",
        "-Wno-unused-macros",
        "-Wno-error=undef",
    };

    const sfx_s2_core_c_src = .{
        "7zCrc.c",
        "7zCrcOpt.c",
        "CpuArch.c",
    };

    const core_c_src = sfx_s2_core_c_src ++ .{
        "Alloc.c",
        "Threads.c",
    };

    const sfx_s2_dec_c_src = .{
        "7zStream.c",
        "Bcj2.c",
        "Bra.c",
        "Bra86.c",
        "BraIA64.c",
        "Delta.c",
        "Lzma2Dec.c",
        "LzmaDec.c",
    };

    const sfx_c_src = sfx_s2_dec_c_src ++ .{
        "Aes.c",
        "AesOpt.c",
        "Lzma2DecMt.c",
        "MtDec.c",
        "Ppmd7.c",
        "Ppmd7Dec.c",
        "Sha256.c",
        "Sha256Opt.c",
    };

    const codecs_c_src = .{
        "7zBuf2.c",
        "Bcj2Enc.c",
        "Blake2s.c",
        "BwtSort.c",
        "HuffEnc.c",
        "LzFind.c",
        "LzFindMt.c",
        "LzFindOpt.c",
        "Lzma2Enc.c",
        "LzmaEnc.c",
        "Md5.c",
        "MtCoder.c",
        "Ppmd7Enc.c",
        "Ppmd7aDec.c",
        "Ppmd8.c",
        "Ppmd8Dec.c",
        "Ppmd8Enc.c",
        "Sha1.c",
        "Sha1Opt.c",
        "Sha3.c",
        "Sha512.c",
        "Sha512Opt.c",
        "Sort.c",
        "SwapBytes.c",
        "Xxh64.c",
        "Xz.c",
        "XzCrc64.c",
        "XzCrc64Opt.c",
        "XzDec.c",
        "XzEnc.c",
        "XzIn.c",
        "ZstdDec.c",
    };

    const sfx_core_cpp_src = .{
        "Windows/Synchronization.cpp",
        "Common/CRC.cpp",
        "Common/IntToString.cpp",
        "Common/MyString.cpp",
        "Common/MyVector.cpp",
        "Common/NewHandler.cpp",
        "Common/StringConvert.cpp",
        "Common/UTFConvert.cpp",
        "Common/Wildcard.cpp",
        "Windows/FileDir.cpp",
        "Windows/FileFind.cpp",
        "Windows/FileIO.cpp",
        "Windows/FileName.cpp",
        "Windows/PropVariant.cpp",
        "Windows/PropVariantConv.cpp",
        "Windows/System.cpp",
        "Windows/TimeUtils.cpp",
        "7zip/Common/CreateCoder.cpp",
        "7zip/Common/CWrappers.cpp",
        "7zip/Common/InBuffer.cpp",
        "7zip/Common/FilterCoder.cpp",
        "7zip/Common/LimitedStreams.cpp",
        "7zip/Common/OutBuffer.cpp",
        "7zip/Common/ProgressUtils.cpp",
        "7zip/Common/PropId.cpp",
        "7zip/Common/StreamObjects.cpp",
        "7zip/Common/StreamUtils.cpp",
        "7zip/Archive/Common/ItemNameUtils.cpp",
        "7zip/Compress/CopyCoder.cpp",
        "Common/MyWindows.cpp",
    };

    const core_extra_cpp_src = .{
        "Common/CrcReg.cpp",
        "Common/DynLimBuf.cpp",
        "Common/StringToInt.cpp",
        "7zip/Common/InOutTempBuffer.cpp",
        "7zip/Common/MethodId.cpp",
        "7zip/Common/MethodProps.cpp",
        "7zip/Common/OffsetStream.cpp",
        "7zip/Common/UniqBlocks.cpp",
    };

    const core_cpp_src = sfx_core_cpp_src ++ core_extra_cpp_src;

    const sfx_codecs_common_cpp_src = .{
        "7zip/Common/StreamBinder.cpp",
        "7zip/Common/VirtThread.cpp",
        "Common/Sha256Prepare.cpp",
    };

    const codecs_common_extra_cpp_src = .{
        "7zip/Common/MemBlocks.cpp",
        "7zip/Common/OutMemStream.cpp",
        "7zip/Common/ProgressMt.cpp",
        "Common/LzFindPrepare.cpp",
        "Common/Md5Reg.cpp",
        "Common/MyMap.cpp",
        "Common/MyXml.cpp",
        "Common/Sha1Prepare.cpp",
        "Common/Sha1Reg.cpp",
        "Common/Sha256Reg.cpp",
        "Common/Sha3Reg.cpp",
        "Common/Sha512Prepare.cpp",
        "Common/Sha512Reg.cpp",
        "Common/Xxh64Reg.cpp",
        "Common/XzCrc64Init.cpp",
        "Common/XzCrc64Reg.cpp",
        "Windows/PropVariantUtils.cpp",
        "7zip/Common/LockedStream.cpp",
    };

    const codecs_common_cpp_src = sfx_codecs_common_cpp_src ++ codecs_common_extra_cpp_src;

    const out_stream_with_crc_cpp_src = .{
        "7zip/Archive/Common/OutStreamWithCRC.cpp",
    };

    const sfx_archive_cpp_src = out_stream_with_crc_cpp_src ++ .{
        "7zip/Archive/SplitHandler.cpp",
        "7zip/Archive/Common/CoderMixer2.cpp",
        "7zip/Archive/Common/MultiStream.cpp",
        "7zip/Archive/7z/7zDecode.cpp",
        "7zip/Archive/7z/7zExtract.cpp",
        "7zip/Archive/7z/7zHandler.cpp",
        "7zip/Archive/7z/7zIn.cpp",
        "7zip/Archive/7z/7zRegister.cpp",
    };

    const archive_extra_cpp_src = .{
        "7zip/Archive/ApfsHandler.cpp",
        "7zip/Archive/ApmHandler.cpp",
        "7zip/Archive/ArHandler.cpp",
        "7zip/Archive/ArjHandler.cpp",
        "7zip/Archive/Base64Handler.cpp",
        "7zip/Archive/Bz2Handler.cpp",
        "7zip/Archive/ComHandler.cpp",
        "7zip/Archive/CpioHandler.cpp",
        "7zip/Archive/CramfsHandler.cpp",
        "7zip/Archive/DeflateProps.cpp",
        "7zip/Archive/DmgHandler.cpp",
        "7zip/Archive/ElfHandler.cpp",
        "7zip/Archive/ExtHandler.cpp",
        "7zip/Archive/FatHandler.cpp",
        "7zip/Archive/FlvHandler.cpp",
        "7zip/Archive/GzHandler.cpp",
        "7zip/Archive/GptHandler.cpp",
        "7zip/Archive/HandlerCont.cpp",
        "7zip/Archive/HfsHandler.cpp",
        "7zip/Archive/IhexHandler.cpp",
        "7zip/Archive/LpHandler.cpp",
        "7zip/Archive/LzhHandler.cpp",
        "7zip/Archive/LzmaHandler.cpp",
        "7zip/Archive/MachoHandler.cpp",
        "7zip/Archive/MbrHandler.cpp",
        "7zip/Archive/MslzHandler.cpp",
        "7zip/Archive/MubHandler.cpp",
        "7zip/Archive/NtfsHandler.cpp",
        "7zip/Archive/PeHandler.cpp",
        "7zip/Archive/PpmdHandler.cpp",
        "7zip/Archive/QcowHandler.cpp",
        "7zip/Archive/RpmHandler.cpp",
        "7zip/Archive/SparseHandler.cpp",
        "7zip/Archive/SquashfsHandler.cpp",
        "7zip/Archive/SwfHandler.cpp",
        "7zip/Archive/UefiHandler.cpp",
        "7zip/Archive/VdiHandler.cpp",
        "7zip/Archive/VhdHandler.cpp",
        "7zip/Archive/VhdxHandler.cpp",
        "7zip/Archive/VmdkHandler.cpp",
        "7zip/Archive/XarHandler.cpp",
        "7zip/Archive/XzHandler.cpp",
        "7zip/Archive/ZHandler.cpp",
        "7zip/Archive/ZstdHandler.cpp",
        "7zip/Archive/Common/DummyOutStream.cpp",
        "7zip/Archive/Common/FindSignature.cpp",
        "7zip/Archive/Common/InStreamWithCRC.cpp",
        "7zip/Archive/Common/OutStreamWithSha1.cpp",
        "7zip/Archive/Common/HandlerOut.cpp",
        "7zip/Archive/Common/ParseProperties.cpp",
        "7zip/Archive/7z/7zCompressionMode.cpp",
        "7zip/Archive/7z/7zEncode.cpp",
        "7zip/Archive/7z/7zFolderInStream.cpp",
        "7zip/Archive/7z/7zHandlerOut.cpp",
        "7zip/Archive/7z/7zHeader.cpp",
        "7zip/Archive/7z/7zOut.cpp",
        "7zip/Archive/7z/7zProperties.cpp",
        "7zip/Archive/7z/7zSpecStream.cpp",
        "7zip/Archive/7z/7zUpdate.cpp",
        "7zip/Archive/Cab/CabBlockInStream.cpp",
        "7zip/Archive/Cab/CabHandler.cpp",
        "7zip/Archive/Cab/CabHeader.cpp",
        "7zip/Archive/Cab/CabIn.cpp",
        "7zip/Archive/Cab/CabRegister.cpp",
        "7zip/Archive/Chm/ChmHandler.cpp",
        "7zip/Archive/Chm/ChmIn.cpp",
        "7zip/Archive/Iso/IsoHandler.cpp",
        "7zip/Archive/Iso/IsoHeader.cpp",
        "7zip/Archive/Iso/IsoIn.cpp",
        "7zip/Archive/Iso/IsoRegister.cpp",
        "7zip/Archive/Nsis/NsisDecode.cpp",
        "7zip/Archive/Nsis/NsisHandler.cpp",
        "7zip/Archive/Nsis/NsisIn.cpp",
        "7zip/Archive/Nsis/NsisRegister.cpp",
        "7zip/Archive/Rar/RarHandler.cpp",
        "7zip/Archive/Rar/Rar5Handler.cpp",
        "7zip/Archive/Tar/TarHandler.cpp",
        "7zip/Archive/Tar/TarHandlerOut.cpp",
        "7zip/Archive/Tar/TarHeader.cpp",
        "7zip/Archive/Tar/TarIn.cpp",
        "7zip/Archive/Tar/TarOut.cpp",
        "7zip/Archive/Tar/TarUpdate.cpp",
        "7zip/Archive/Tar/TarRegister.cpp",
        "7zip/Archive/Udf/UdfHandler.cpp",
        "7zip/Archive/Udf/UdfIn.cpp",
        "7zip/Archive/Wim/WimHandler.cpp",
        "7zip/Archive/Wim/WimHandlerOut.cpp",
        "7zip/Archive/Wim/WimIn.cpp",
        "7zip/Archive/Wim/WimRegister.cpp",
        "7zip/Archive/Zip/ZipAddCommon.cpp",
        "7zip/Archive/Zip/ZipHandler.cpp",
        "7zip/Archive/Zip/ZipHandlerOut.cpp",
        "7zip/Archive/Zip/ZipIn.cpp",
        "7zip/Archive/Zip/ZipItem.cpp",
        "7zip/Archive/Zip/ZipOut.cpp",
        "7zip/Archive/Zip/ZipUpdate.cpp",
        "7zip/Archive/Zip/ZipRegister.cpp",
    };

    const archive_cpp_src = sfx_archive_cpp_src ++ archive_extra_cpp_src;

    const sfx_compress_cpp_src = .{
        "7zip/Compress/Bcj2Coder.cpp",
        "7zip/Compress/Bcj2Register.cpp",
        "7zip/Compress/BcjCoder.cpp",
        "7zip/Compress/BcjRegister.cpp",
        "7zip/Compress/BranchMisc.cpp",
        "7zip/Compress/BranchRegister.cpp",
        "7zip/Compress/CopyRegister.cpp",
        "7zip/Compress/DeltaFilter.cpp",
        "7zip/Compress/Lzma2Decoder.cpp",
        "7zip/Compress/Lzma2Register.cpp",
        "7zip/Compress/LzmaDecoder.cpp",
        "7zip/Compress/LzmaRegister.cpp",
        "7zip/Compress/PpmdDecoder.cpp",
        "7zip/Compress/PpmdRegister.cpp",
    };

    const compress_extra_cpp_src = .{
        "7zip/Compress/BitlDecoder.cpp",
        "7zip/Compress/ByteSwap.cpp",
        "7zip/Compress/BZip2Crc.cpp",
        "7zip/Compress/BZip2Decoder.cpp",
        "7zip/Compress/BZip2Encoder.cpp",
        "7zip/Compress/BZip2Register.cpp",
        "7zip/Compress/Deflate64Register.cpp",
        "7zip/Compress/DeflateDecoder.cpp",
        "7zip/Compress/DeflateEncoder.cpp",
        "7zip/Compress/DeflateRegister.cpp",
        "7zip/Compress/ImplodeDecoder.cpp",
        "7zip/Compress/LzfseDecoder.cpp",
        "7zip/Compress/LzhDecoder.cpp",
        "7zip/Compress/Lzma2Encoder.cpp",
        "7zip/Compress/LzmaEncoder.cpp",
        "7zip/Compress/LzmsDecoder.cpp",
        "7zip/Compress/LzOutWindow.cpp",
        "7zip/Compress/LzxDecoder.cpp",
        "7zip/Compress/PpmdEncoder.cpp",
        "7zip/Compress/PpmdZip.cpp",
        "7zip/Compress/QuantumDecoder.cpp",
        "7zip/Compress/ShrinkDecoder.cpp",
        "7zip/Compress/XpressDecoder.cpp",
        "7zip/Compress/XzDecoder.cpp",
        "7zip/Compress/XzEncoder.cpp",
        "7zip/Compress/ZlibDecoder.cpp",
        "7zip/Compress/ZlibEncoder.cpp",
        "7zip/Compress/ZDecoder.cpp",
        "7zip/Compress/ZstdDecoder.cpp",
        "7zip/Compress/Rar1Decoder.cpp",
        "7zip/Compress/Rar2Decoder.cpp",
        "7zip/Compress/Rar3Decoder.cpp",
        "7zip/Compress/Rar3Vm.cpp",
        "7zip/Compress/Rar5Decoder.cpp",
        "7zip/Compress/RarCodecsRegister.cpp",
    };

    const compress_cpp_src = sfx_compress_cpp_src ++ compress_extra_cpp_src;

    const sfx_crypto_cpp_src = .{
        "7zip/Crypto/7zAes.cpp",
        "7zip/Crypto/7zAesRegister.cpp",
        "7zip/Crypto/MyAes.cpp",
    };

    const crypto_extra_cpp_src = .{
        "7zip/Crypto/HmacSha1.cpp",
        "7zip/Crypto/HmacSha256.cpp",
        "7zip/Crypto/MyAesReg.cpp",
        "7zip/Crypto/Pbkdf2HmacSha1.cpp",
        "7zip/Crypto/RandGen.cpp",
        "7zip/Crypto/WzAes.cpp",
        "7zip/Crypto/ZipCrypto.cpp",
        "7zip/Crypto/ZipStrong.cpp",
        "7zip/Crypto/Rar20Crypto.cpp",
        "7zip/Crypto/Rar5Aes.cpp",
        "7zip/Crypto/RarAes.cpp",
    };

    const crypto_cpp_src = sfx_crypto_cpp_src ++ crypto_extra_cpp_src;

    const sfx_codecs_cpp_src = sfx_codecs_common_cpp_src ++ sfx_archive_cpp_src ++ sfx_compress_cpp_src ++ sfx_crypto_cpp_src;

    const codecs_cpp_src = codecs_common_cpp_src ++ archive_cpp_src ++ compress_cpp_src ++ crypto_cpp_src;

    const ui_common_extract_cpp_src = .{
        "Common/CommandLineParser.cpp",
        "Windows/ErrorMsg.cpp",
        "7zip/Common/FilePathAutoRename.cpp",
        "7zip/Common/FileStreams.cpp",
        "7zip/UI/Common/ArchiveExtractCallback.cpp",
        "7zip/UI/Common/ArchiveOpenCallback.cpp",
        "7zip/UI/Common/DefaultName.cpp",
        "7zip/UI/Common/Extract.cpp",
        "7zip/UI/Common/ExtractingFilePath.cpp",
        "7zip/UI/Common/LoadCodecs.cpp",
        "7zip/UI/Common/OpenArchive.cpp",
        "7zip/UI/Common/PropIDUtils.cpp",
    };

    const ui_console_extract_cpp_src = .{
        "Common/StdInStream.cpp",
        "Common/StdOutStream.cpp",
        "7zip/UI/Console/ConsoleClose.cpp",
        "7zip/UI/Console/ExtractCallbackConsole.cpp",
        "7zip/UI/Console/List.cpp",
        "7zip/UI/Console/MainAr.cpp",
        "7zip/UI/Console/OpenCallbackConsole.cpp",
        "7zip/UI/Console/PercentPrinter.cpp",
        "7zip/UI/Console/UserInputUtils.cpp",
    };

    const ui_extract_cpp_src = ui_common_extract_cpp_src ++ ui_console_extract_cpp_src;

    const ui_common_extra_cpp_src = .{
        "Common/ListFileUtils.cpp",
        "Windows/FileLink.cpp",
        "Windows/SystemInfo.cpp",
        "7zip/Common/MultiOutStream.cpp",
        "7zip/UI/Common/Bench.cpp",
        "7zip/UI/Common/EnumDirItems.cpp",
        "7zip/UI/Common/HashCalc.cpp",
        "7zip/UI/Common/SetProperties.cpp",
        "7zip/UI/Common/SortUtils.cpp",
        "7zip/UI/Common/TempFiles.cpp",
        "7zip/UI/Common/Update.cpp",
        "7zip/UI/Common/UpdateAction.cpp",
        "7zip/UI/Common/UpdateCallback.cpp",
        "7zip/UI/Common/UpdatePair.cpp",
        "7zip/UI/Common/UpdateProduce.cpp",
    };

    const ui_cmdline_cpp_src = .{
        "7zip/UI/Common/ArchiveCommandLine.cpp",
    };

    const ui_console_extra_cpp_src = .{
        "7zip/UI/Console/BenchCon.cpp",
        "7zip/UI/Console/HashCon.cpp",
        "7zip/UI/Console/Main.cpp",
        "7zip/UI/Console/UpdateCallbackConsole.cpp",
    };

    const ui_extra_cpp_src = ui_common_extra_cpp_src ++ ui_cmdline_cpp_src ++ ui_console_extra_cpp_src;

    const ui_cpp_src = ui_extract_cpp_src ++ ui_extra_cpp_src;
    const ui_common_cpp_src = ui_common_extract_cpp_src ++ ui_common_extra_cpp_src;

    const dll_cpp_src = .{
        "Windows/DLL.cpp",
    };

    const resource_string_cpp_src = .{
        "Windows/ResourceString.cpp",
    };

    const gui_shared_cpp_src = .{
        "7zip/UI/GUI/BenchmarkDialog.cpp",
        "7zip/UI/GUI/CompressDialog.cpp",
        "7zip/UI/GUI/ExtractDialog.cpp",
        "7zip/UI/GUI/ExtractGUI.cpp",
        "7zip/UI/GUI/HashGUI.cpp",
        "7zip/UI/GUI/UpdateCallbackGUI.cpp",
        "7zip/UI/GUI/UpdateCallbackGUI2.cpp",
        "7zip/UI/GUI/UpdateGUI.cpp",
        "Common/Lang.cpp",
        "Windows/Clipboard.cpp",
        "Windows/CommonDialog.cpp",
        "Windows/FileSystem.cpp",
        "Windows/MemoryGlobal.cpp",
        "Windows/Shell.cpp",
        "Windows/Window.cpp",
        "Windows/Control/ComboBox.cpp",
        "Windows/Control/Dialog.cpp",
        "Windows/Control/ListView.cpp",
        "7zip/UI/Common/WorkDir.cpp",
        "7zip/UI/Common/ZipRegistry.cpp",
        "7zip/UI/FileManager/EditDialog.cpp",
        "7zip/UI/FileManager/ExtractCallback.cpp",
        "7zip/UI/FileManager/FormatUtils.cpp",
        "7zip/UI/FileManager/HelpUtils.cpp",
        "7zip/UI/FileManager/LangUtils.cpp",
        "7zip/UI/FileManager/ListViewDialog.cpp",
        "7zip/UI/FileManager/MemDialog.cpp",
        "7zip/UI/FileManager/OpenCallback.cpp",
        "7zip/UI/FileManager/ProgramLocation.cpp",
        "7zip/UI/FileManager/PropertyName.cpp",
        "7zip/UI/FileManager/RegistryUtils.cpp",
        "7zip/UI/FileManager/SplitUtils.cpp",
        "7zip/UI/FileManager/StringUtils.cpp",
        "7zip/UI/FileManager/OverwriteDialog.cpp",
        "7zip/UI/FileManager/PasswordDialog.cpp",
        "7zip/UI/FileManager/ProgressDialog2.cpp",
        "7zip/UI/FileManager/BrowseDialog.cpp",
        "7zip/UI/FileManager/ComboDialog.cpp",
        "7zip/UI/FileManager/SysIconUtils.cpp",
        "7zip/UI/Explorer/MyMessages.cpp",
    };

    const fm_specific_cpp_src = .{
        "7zip/UI/FileManager/App.cpp",
        "7zip/UI/FileManager/BrowseDialog2.cpp",
        "7zip/UI/FileManager/ClassDefs.cpp",
        "7zip/UI/FileManager/EnumFormatEtc.cpp",
        "7zip/UI/FileManager/FileFolderPluginOpen.cpp",
        "7zip/UI/FileManager/FilePlugins.cpp",
        "7zip/UI/FileManager/FoldersPage.cpp",
        "7zip/UI/FileManager/FSFolder.cpp",
        "7zip/UI/FileManager/FSFolderCopy.cpp",
        "7zip/UI/FileManager/MenuPage.cpp",
        "7zip/UI/FileManager/MyLoadMenu.cpp",
        "7zip/UI/FileManager/OptionsDialog.cpp",
        "7zip/UI/FileManager/Panel.cpp",
        "7zip/UI/FileManager/PanelCopy.cpp",
        "7zip/UI/FileManager/PanelCrc.cpp",
        "7zip/UI/FileManager/PanelDrag.cpp",
        "7zip/UI/FileManager/PanelFolderChange.cpp",
        "7zip/UI/FileManager/PanelItemOpen.cpp",
        "7zip/UI/FileManager/PanelItems.cpp",
        "7zip/UI/FileManager/PanelKey.cpp",
        "7zip/UI/FileManager/PanelListNotify.cpp",
        "7zip/UI/FileManager/PanelMenu.cpp",
        "7zip/UI/FileManager/PanelOperations.cpp",
        "7zip/UI/FileManager/PanelSelect.cpp",
        "7zip/UI/FileManager/PanelSort.cpp",
        "7zip/UI/FileManager/PanelSplitFile.cpp",
        "7zip/UI/FileManager/RegistryAssociations.cpp",
        "7zip/UI/FileManager/RootFolder.cpp",
        "7zip/UI/FileManager/TextPairs.cpp",
        "7zip/UI/FileManager/UpdateCallback100.cpp",
        "7zip/UI/FileManager/ViewSettings.cpp",
        "7zip/UI/FileManager/AboutDialog.cpp",
        "7zip/UI/FileManager/CopyDialog.cpp",
        "7zip/UI/FileManager/EditPage.cpp",
        "7zip/UI/FileManager/LangPage.cpp",
        "7zip/UI/FileManager/MessagesDialog.cpp",
        "7zip/UI/FileManager/SettingsPage.cpp",
        "7zip/UI/FileManager/SplitDialog.cpp",
        "7zip/UI/FileManager/SystemPage.cpp",
        "7zip/UI/FileManager/VerCtrl.cpp",
        "7zip/UI/FileManager/AltStreamsFolder.cpp",
        "7zip/UI/FileManager/FSDrives.cpp",
        "7zip/UI/FileManager/LinkDialog.cpp",
        "7zip/UI/FileManager/NetFolder.cpp",
        "Windows/Control/PropertyPage.cpp",
        "Windows/Control/Window2.cpp",
        "Windows/Menu.cpp",
        "Windows/Net.cpp",
        "Windows/ProcessUtils.cpp",
        "7zip/UI/Agent/Agent.cpp",
        "7zip/UI/Agent/AgentOut.cpp",
        "7zip/UI/Agent/AgentProxy.cpp",
        "7zip/UI/Agent/ArchiveFolder.cpp",
        "7zip/UI/Agent/ArchiveFolderOpen.cpp",
        "7zip/UI/Agent/ArchiveFolderOut.cpp",
        "7zip/UI/Agent/UpdateCallbackAgent.cpp",
        "7zip/UI/Explorer/ContextMenu.cpp",
        "7zip/UI/Explorer/RegistryContextMenu.cpp",
        "7zip/UI/Common/ArchiveName.cpp",
        "7zip/UI/Common/CompressCall2.cpp",
        "Common/Random.cpp",
    };

    pub const Win = struct {
        const c_src = .{
            "DllSecur.c",
        };

        const cpp_src = .{
            "Windows/Registry.cpp",
            "Windows/SecurityUtils.cpp",
            "Windows/MemoryLock.cpp",
        };

        const extra_cpp_src = dll_cpp_src ++ resource_string_cpp_src;

        const defs = .{
            .{ "ENV_HAVE_WCTYPE_H", "" },
        };
    };
};

const SevenZipZ = struct {
    const defs = .{
        .{ "_FILE_OFFSET_BITS", "64" },
        .{ "_LARGEFILE_SOURCE", "" },
        .{ "_REENTRANT", "" },
        .{ "_7ZIP_LARGE_PAGES", "" },
        .{ "BREAK_HANDLER", "" },
        .{ "UNICODE", "" },
        .{ "_UNICODE", "" },
    };

    const c_src = Common.core_c_src ++ Common.sfx_c_src ++ Common.codecs_c_src ++ .{
        "DllSecur.c",
    };

    const cpp_src = Common.core_cpp_src ++ Common.codecs_cpp_src ++ Common.ui_cpp_src;

    pub const Win = struct {
        const cpp_src = Common.Win.cpp_src ++ Common.Win.extra_cpp_src;

        const defs = Common.Win.defs;
    };
};

const Lib7zip = struct {
    const defs = .{
        .{ "_FILE_OFFSET_BITS", "64" },
        .{ "_LARGEFILE_SOURCE", "" },
        .{ "_REENTRANT", "" },
        .{ "Z7_NO_LARGE_PAGES", "" },
        .{ "BREAK_HANDLER", "" },
        .{ "UNICODE", "" },
        .{ "_UNICODE", "" },
    };

    const c_src = Common.core_c_src ++ Common.sfx_c_src ++ Common.codecs_c_src;

    const cpp_src = Common.core_cpp_src ++ Common.codecs_cpp_src ++ .{
        "7zip/Archive/ArchiveExports.cpp",
        "7zip/Archive/DllExports2.cpp",
        "7zip/Compress/CodecExports.cpp",
    };

    pub const Win = struct {
        const cpp_src = Common.Win.cpp_src ++ .{
            "Windows/System.cpp",
        };

        const defs = Common.Win.defs;
    };
};

const Client = struct {
    const defs = .{
        .{ "_FILE_OFFSET_BITS", "64" },
        .{ "_LARGEFILE_SOURCE", "" },
        .{ "_REENTRANT", "" },
        .{ "BREAK_HANDLER", "" },
        .{ "UNICODE", "" },
        .{ "_UNICODE", "" },
        .{ "Z7_EXTERNAL_CODECS", "" },
    };

    const c_src = Common.core_c_src ++ .{
        "Sort.c",
    };

    const cpp_src = Common.core_cpp_src ++ Common.ui_cpp_src ++ Common.dll_cpp_src;

    pub const Win = struct {
        const c_src = Common.Win.c_src;

        const cpp_src = Common.Win.cpp_src;

        const defs = Common.Win.defs;
    };
};

const SfxCon = struct {
    const defs = .{
        .{ "_FILE_OFFSET_BITS", "64" },
        .{ "_LARGEFILE_SOURCE", "" },
        .{ "_REENTRANT", "" },
        .{ "BREAK_HANDLER", "" },
        .{ "UNICODE", "" },
        .{ "_UNICODE", "" },
        .{ "Z7_EXTRACT_ONLY", "" },
        .{ "Z7_NO_READ_FROM_CODER", "" },
        .{ "Z7_SFX", "" },
        .{ "Z7_NO_LARGE_PAGES", "" },
    };

    const c_src = Common.core_c_src ++ Common.sfx_c_src;

    const cpp_src = Common.sfx_core_cpp_src ++ Common.ui_extract_cpp_src ++ Common.sfx_codecs_cpp_src ++ .{
        "7zip/Bundles/SFXCon/SfxCon.cpp",
    };

    pub const Win = struct {
        const c_src = Common.Win.c_src;

        const cpp_src = Common.dll_cpp_src;

        const defs = Common.Win.defs ++ .{
            .{ "Z7_NO_LONG_PATH", "" },
        };
    };
};

const SfxS2 = struct {
    const c_src = Common.sfx_s2_core_c_src ++ Common.sfx_s2_dec_c_src ++ .{
        "7zBuf2.c",
        "DllSecur.c",
        "7zAlloc.c",
        "7zArcIn.c",
        "7zBuf.c",
        "7zFile.c",
        "7zDec.c",
        "Util/SfxSetup/SfxSetup.c",
    };

    const defs = .{
        .{ "UNICODE", "" },
        .{ "_UNICODE", "" },
        .{ "Z7_EXTRACT_ONLY", "" },
    };

    const cflags = .{
        "-Wno-error=extra-semi-stmt",
    };
};

const Gui = struct {
    const defs = Client.defs ++ Common.Win.defs ++ .{
        .{ "Z7_LANG", "" },
        .{ "Z7_DEVICE_FILE", "" },
    };

    const c_src = Client.c_src ++ Client.Win.c_src;

    const cpp_src = Common.core_cpp_src ++ Common.ui_common_cpp_src ++ Common.ui_cmdline_cpp_src ++ Common.gui_shared_cpp_src ++ Common.Win.cpp_src ++ Common.Win.extra_cpp_src ++ Common.out_stream_with_crc_cpp_src ++ .{
        "7zip/UI/GUI/GUI.cpp",
    };
};

const Fm = struct {
    const defs = SevenZipZ.defs ++ Common.Win.defs ++ .{
        .{ "Z7_LANG", "" },
        .{ "Z7_DEVICE_FILE", "" },
    };

    const c_src = SevenZipZ.c_src;

    const cpp_src = Common.core_cpp_src ++ Common.codecs_cpp_src ++ Common.ui_common_cpp_src ++ Common.gui_shared_cpp_src ++ Common.fm_specific_cpp_src ++ Common.Win.cpp_src ++ Common.Win.extra_cpp_src ++ .{
        "7zip/UI/FileManager/FM.cpp",
    };
};
