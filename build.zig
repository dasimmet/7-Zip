const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const src = b.dependency("sevenzip_src", .{});

    const res = buildOptions(.{
        .b = b,
        .src = src,
        .target = target,
        .optimize = optimize,
    });

    b.installArtifact(res.sevenzipa);
    // b.installArtifact(res.libsevenzip);

    if (b.option(bool, "ci", "enable the ci step") orelse false) {
        const ci = b.step("ci", "ci target");
        inline for (&.{
            "x86_64-linux-musl",
            "x86_64-linux-gnu",
            "aarch64-linux-musl",
            "aarch64-linux-gnu",
            "x86_64-macos-none",
            "aarch64-macos-none",
        }) |target_str| {
            const parsed_query = std.Build.parseTargetQuery(.{
                .arch_os_abi = target_str,
            }) catch @panic("invalid target query");

            const ci_target = b.resolveTargetQuery(parsed_query);
            const ci_res = buildOptions(.{
                .b = b,
                .src = src,
                .target = ci_target,
                .optimize = optimize,
            });
            ci.dependOn(&ci_res.sevenzipa.step);
            ci.dependOn(&ci_res.libsevenzip.step);
        }
    }
}

pub const BuildOptions = struct {
    b: *std.Build,
    src: *std.Build.Dependency,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
};

pub const BuildResults = struct {
    sevenzipa: *std.Build.Step.Compile,
    libsevenzip: *std.Build.Step.Compile,
};

pub fn buildOptions(opt: BuildOptions) BuildResults {
    const sevenzipa = blk: {
        const sevenzipa = opt.b.createModule(.{
            .target = opt.target,
            .optimize = opt.optimize,
            .link_libc = true,
            .link_libcpp = true,
        });

        sevenzipa.addCSourceFiles(.{
            .root = opt.src.path("C"),
            .files = &SevenZipA.c_src,
        });

        sevenzipa.addCSourceFiles(.{
            .root = opt.src.path("CPP"),
            .files = &SevenZipA.cpp_src,
            .flags = &.{
                "-Werror",
                "-Wall",
                "-Wextra",
                "-Weverything",
                "-Wfatal-errors",
                "-Wno-error=alloca",
                "-Wno-error=cast-qual",
                "-Wno-error=disabled-macro-expansion",
            },
        });
        inline for (Common.includes) |inc| {
            sevenzipa.addIncludePath(opt.src.path(inc));
        }
        inline for (SevenZipA.defs) |def| {
            sevenzipa.addCMacro(def[0], def[1]);
        }
        if (opt.target.result.os.tag != .windows) {
            sevenzipa.addCSourceFiles(.{
                .root = opt.src.path("CPP"),
                .files = &SevenZipA.cpp_src_unix,
                .flags = &.{
                    "-Wno-error=c++11-narrowing",
                    "-Wno-error=increment-bool",
                },
            });
            inline for (Common.includes_unix) |inc| {
                sevenzipa.addIncludePath(opt.src.path(inc));
            }
            inline for (Common.defs_unix) |def| {
                sevenzipa.addCMacro(def[0], def[1]);
            }
        } else {
            sevenzipa.addCSourceFiles(.{
                .root = opt.src.path("C"),
                .files = &SevenZipA.c_src_win,
                .flags = &.{
                    "-Wno-error=c++11-narrowing",
                    "-Wno-error=increment-bool",
                },
            });
            sevenzipa.addCSourceFiles(.{
                .root = opt.src.path("CPP"),
                .files = &SevenZipA.cpp_src_win,
                .flags = &.{
                    "-Wno-error=c++11-narrowing",
                    "-Wno-error=increment-bool",
                },
            });
            inline for (Common.includes_win) |inc| {
                sevenzipa.addIncludePath(opt.src.path(inc));
            }

            inline for (Common.defs_win) |def| {
                sevenzipa.addCMacro(def[0], def[1]);
            }
            sevenzipa.linkSystemLibrary("oleaut32", .{});
        }

        const exe = opt.b.addExecutable(.{
            .name = "7za",
            .root_module = sevenzipa,
        });

        break :blk exe;
    };

    const libsevenzip = blk: {
        const modlibsevenzip = opt.b.createModule(.{
            .target = opt.target,
            .optimize = opt.optimize,
            .link_libc = true,
            .link_libcpp = true,
        });
        modlibsevenzip.addCSourceFiles(.{
            .root = opt.src.path("C"),
            .files = &LibSevenZip.c_src,
        });
        inline for (Common.includes) |inc| {
            modlibsevenzip.addIncludePath(opt.src.path(inc));
        }

        modlibsevenzip.addCSourceFiles(.{
            .root = opt.src.path("CPP"),
            .files = &LibSevenZip.cpp_src,
            .flags = &.{
                "-Wno-error=c++11-narrowing",
                "-Wno-error=increment-bool",
            },
        });
        inline for (LibSevenZip.defs) |def| {
            modlibsevenzip.addCMacro(def[0], def[1]);
        }

        if (opt.target.result.os.tag != .windows) {
            modlibsevenzip.addCSourceFiles(.{
                .root = opt.src.path("CPP"),
                .files = &LibSevenZip.cpp_src_unix,
                .flags = &.{
                    "-Wno-error=c++11-narrowing",
                    "-Wno-error=increment-bool",
                },
            });
            inline for (Common.includes_unix) |inc| {
                modlibsevenzip.addIncludePath(opt.src.path(inc));
            }
            inline for (Common.defs_unix) |def| {
                modlibsevenzip.addCMacro(def[0], def[1]);
            }
        } else {
            inline for (Common.includes_win) |inc| {
                modlibsevenzip.addIncludePath(opt.src.path(inc));
            }

            inline for (Common.defs_win) |def| {
                modlibsevenzip.addCMacro(def[0], def[1]);
            }
        }

        break :blk opt.b.addLibrary(.{
            .name = "7z",
            .root_module = modlibsevenzip,
        });
    };

    return .{
        .sevenzipa = sevenzipa,
        .libsevenzip = libsevenzip,
    };
}

const Common = struct {
    const includes = .{
        "CPP",
    };

    const includes_unix = .{
        "CPP/include_windows",
        "CPP/myWindows",
    };

    const includes_win = .{
        "CPP/Common",
        "CPP/Windows",
        "C",
    };

    const defs_unix = .{
        .{ "ENV_UNIX", "" },
        .{ "UNIX_USE_WIN_FILE", "" },
    };

    const defs_win = .{
        .{ "ENV_HAVE_WCTYPE_H", "" },
    };
};

const SevenZipA = struct {
    const defs = .{
        .{ "_FILE_OFFSET_BITS", "64" },
        .{ "_LARGEFILE_SOURCE", "" },
        .{ "NDEBUG", "" },
        .{ "_REENTRANT", "" },
        .{ "_7ZIP_LARGE_PAGES", "" },
        .{ "BREAK_HANDLER", "" },
        .{ "UNICODE", "" },
        .{ "_UNICODE", "" },
    };

    const c_src = .{
        "7zBuf2.c",
        "7zCrc.c",
        "7zCrcOpt.c",
        "7zStream.c",
        "Aes.c",
        "AesOpt.c",
        "Alloc.c",
        "Bcj2.c",
        "Bcj2Enc.c",
        "Blake2s.c",
        "Bra.c",
        "Bra86.c",
        "BraIA64.c",
        "BwtSort.c",
        "CpuArch.c",
        "Delta.c",
        "HuffEnc.c",
        "LzFind.c",
        "Lzma2Dec.c",
        "Lzma2DecMt.c",
        "Lzma2Enc.c",
        "LzmaDec.c",
        "LzmaEnc.c",
        "Md5.c",
        "MtCoder.c",
        "MtDec.c",
        "Ppmd7.c",
        "Ppmd7Dec.c",
        "Ppmd7aDec.c",
        "Ppmd7Enc.c",
        "Ppmd8.c",
        "Ppmd8Dec.c",
        "Ppmd8Enc.c",
        "Sha1.c",
        "Sha1Opt.c",
        "Sha256.c",
        "Sha256Opt.c",
        "Sha3.c",
        "Sha512.c",
        "Sha512Opt.c",
        "Sort.c",
        "SwapBytes.c",
        "Xxh64.c",
        "Xz.c",
        "XzDec.c",
        "XzEnc.c",
        "XzIn.c",
        "XzCrc64.c",
        "XzCrc64Opt.c",
        "ZstdDec.c",
        "LzFindMt.c",
        "LzFindOpt.c",
        "Threads.c",
    };

    const c_src_win = .{};

    const cpp_src = .{
        "7zip/Common/MemBlocks.cpp",
        "7zip/Common/OutMemStream.cpp",
        "7zip/Common/ProgressMt.cpp",
        "7zip/Common/StreamBinder.cpp",
        "Windows/Synchronization.cpp",
        "7zip/Common/VirtThread.cpp",
        "Common/CRC.cpp",
        "Common/CrcReg.cpp",
        "Common/DynLimBuf.cpp",
        "Common/IntToString.cpp",
        "Common/LzFindPrepare.cpp",
        "Common/Md5Reg.cpp",
        "Common/MyMap.cpp",
        "Common/MyString.cpp",
        "Common/MyVector.cpp",
        "Common/MyXml.cpp",
        "Common/NewHandler.cpp",
        "Common/Sha1Prepare.cpp",
        "Common/Sha1Reg.cpp",
        "Common/Sha256Prepare.cpp",
        "Common/Sha256Reg.cpp",
        "Common/Sha3Reg.cpp",
        "Common/Sha512Prepare.cpp",
        "Common/Sha512Reg.cpp",
        "Common/StringConvert.cpp",
        "Common/StringToInt.cpp",
        "Common/UTFConvert.cpp",
        "Common/Wildcard.cpp",
        "Common/Xxh64Reg.cpp",
        "Common/XzCrc64Init.cpp",
        "Common/XzCrc64Reg.cpp",
        "Windows/FileDir.cpp",
        "Windows/FileFind.cpp",
        "Windows/FileIO.cpp",
        "Windows/FileName.cpp",
        "Windows/PropVariant.cpp",
        "Windows/PropVariantConv.cpp",
        "Windows/PropVariantUtils.cpp",
        "Windows/System.cpp",
        "Windows/TimeUtils.cpp",
        "7zip/Common/CreateCoder.cpp",
        "7zip/Common/CWrappers.cpp",
        "7zip/Common/InBuffer.cpp",
        "7zip/Common/InOutTempBuffer.cpp",
        "7zip/Common/FilterCoder.cpp",
        "7zip/Common/LimitedStreams.cpp",
        "7zip/Common/LockedStream.cpp",
        "7zip/Common/MethodId.cpp",
        "7zip/Common/MethodProps.cpp",
        "7zip/Common/OffsetStream.cpp",
        "7zip/Common/OutBuffer.cpp",
        "7zip/Common/ProgressUtils.cpp",
        "7zip/Common/PropId.cpp",
        "7zip/Common/StreamObjects.cpp",
        "7zip/Common/StreamUtils.cpp",
        "7zip/Common/UniqBlocks.cpp",
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
        "7zip/Archive/SplitHandler.cpp",
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
        "7zip/Archive/Common/CoderMixer2.cpp",
        "7zip/Archive/Common/DummyOutStream.cpp",
        "7zip/Archive/Common/FindSignature.cpp",
        "7zip/Archive/Common/InStreamWithCRC.cpp",
        "7zip/Archive/Common/ItemNameUtils.cpp",
        "7zip/Archive/Common/MultiStream.cpp",
        "7zip/Archive/Common/OutStreamWithCRC.cpp",
        "7zip/Archive/Common/OutStreamWithSha1.cpp",
        "7zip/Archive/Common/HandlerOut.cpp",
        "7zip/Archive/Common/ParseProperties.cpp",
        "7zip/Archive/7z/7zCompressionMode.cpp",
        "7zip/Archive/7z/7zDecode.cpp",
        "7zip/Archive/7z/7zEncode.cpp",
        "7zip/Archive/7z/7zExtract.cpp",
        "7zip/Archive/7z/7zFolderInStream.cpp",
        "7zip/Archive/7z/7zHandler.cpp",
        "7zip/Archive/7z/7zHandlerOut.cpp",
        "7zip/Archive/7z/7zHeader.cpp",
        "7zip/Archive/7z/7zIn.cpp",
        "7zip/Archive/7z/7zOut.cpp",
        "7zip/Archive/7z/7zProperties.cpp",
        "7zip/Archive/7z/7zSpecStream.cpp",
        "7zip/Archive/7z/7zUpdate.cpp",
        "7zip/Archive/7z/7zRegister.cpp",
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
        "7zip/Compress/Bcj2Coder.cpp",
        "7zip/Compress/Bcj2Register.cpp",
        "7zip/Compress/BcjCoder.cpp",
        "7zip/Compress/BcjRegister.cpp",
        "7zip/Compress/BitlDecoder.cpp",
        "7zip/Compress/BranchMisc.cpp",
        "7zip/Compress/BranchRegister.cpp",
        "7zip/Compress/ByteSwap.cpp",
        "7zip/Compress/BZip2Crc.cpp",
        "7zip/Compress/BZip2Decoder.cpp",
        "7zip/Compress/BZip2Encoder.cpp",
        "7zip/Compress/BZip2Register.cpp",
        "7zip/Compress/CopyCoder.cpp",
        "7zip/Compress/CopyRegister.cpp",
        "7zip/Compress/Deflate64Register.cpp",
        "7zip/Compress/DeflateDecoder.cpp",
        "7zip/Compress/DeflateEncoder.cpp",
        "7zip/Compress/DeflateRegister.cpp",
        "7zip/Compress/DeltaFilter.cpp",
        "7zip/Compress/ImplodeDecoder.cpp",
        "7zip/Compress/LzfseDecoder.cpp",
        "7zip/Compress/LzhDecoder.cpp",
        "7zip/Compress/Lzma2Decoder.cpp",
        "7zip/Compress/Lzma2Encoder.cpp",
        "7zip/Compress/Lzma2Register.cpp",
        "7zip/Compress/LzmaDecoder.cpp",
        "7zip/Compress/LzmaEncoder.cpp",
        "7zip/Compress/LzmaRegister.cpp",
        "7zip/Compress/LzmsDecoder.cpp",
        "7zip/Compress/LzOutWindow.cpp",
        "7zip/Compress/LzxDecoder.cpp",
        "7zip/Compress/PpmdDecoder.cpp",
        "7zip/Compress/PpmdEncoder.cpp",
        "7zip/Compress/PpmdRegister.cpp",
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
        "7zip/Crypto/7zAes.cpp",
        "7zip/Crypto/7zAesRegister.cpp",
        "7zip/Crypto/HmacSha1.cpp",
        "7zip/Crypto/HmacSha256.cpp",
        "7zip/Crypto/MyAes.cpp",
        "7zip/Crypto/MyAesReg.cpp",
        "7zip/Crypto/Pbkdf2HmacSha1.cpp",
        "7zip/Crypto/RandGen.cpp",
        "7zip/Crypto/WzAes.cpp",
        "7zip/Crypto/ZipCrypto.cpp",
        "7zip/Crypto/ZipStrong.cpp",
        "7zip/Crypto/Rar20Crypto.cpp",
        "7zip/Crypto/Rar5Aes.cpp",
        "7zip/Crypto/RarAes.cpp",
        "Common/MyWindows.cpp",
        "Common/CommandLineParser.cpp",
        "Common/ListFileUtils.cpp",
        "Common/StdInStream.cpp",
        "Common/StdOutStream.cpp",
        "Windows/ErrorMsg.cpp",
        "Windows/FileLink.cpp",
        "Windows/SystemInfo.cpp",
        "7zip/Common/FilePathAutoRename.cpp",
        "7zip/Common/FileStreams.cpp",
        "7zip/Common/MultiOutStream.cpp",
        "7zip/UI/Common/ArchiveCommandLine.cpp",
        "7zip/UI/Common/ArchiveExtractCallback.cpp",
        "7zip/UI/Common/ArchiveOpenCallback.cpp",
        "7zip/UI/Common/Bench.cpp",
        "7zip/UI/Common/DefaultName.cpp",
        "7zip/UI/Common/EnumDirItems.cpp",
        "7zip/UI/Common/Extract.cpp",
        "7zip/UI/Common/ExtractingFilePath.cpp",
        "7zip/UI/Common/HashCalc.cpp",
        "7zip/UI/Common/LoadCodecs.cpp",
        "7zip/UI/Common/OpenArchive.cpp",
        "7zip/UI/Common/PropIDUtils.cpp",
        "7zip/UI/Common/SetProperties.cpp",
        "7zip/UI/Common/SortUtils.cpp",
        "7zip/UI/Common/TempFiles.cpp",
        "7zip/UI/Common/Update.cpp",
        "7zip/UI/Common/UpdateAction.cpp",
        "7zip/UI/Common/UpdateCallback.cpp",
        "7zip/UI/Common/UpdatePair.cpp",
        "7zip/UI/Common/UpdateProduce.cpp",
        "7zip/UI/Console/BenchCon.cpp",
        "7zip/UI/Console/ConsoleClose.cpp",
        "7zip/UI/Console/ExtractCallbackConsole.cpp",
        "7zip/UI/Console/HashCon.cpp",
        "7zip/UI/Console/List.cpp",
        "7zip/UI/Console/Main.cpp",
        "7zip/UI/Console/MainAr.cpp",
        "7zip/UI/Console/OpenCallbackConsole.cpp",
        "7zip/UI/Console/PercentPrinter.cpp",
        "7zip/UI/Console/UpdateCallbackConsole.cpp",
        "7zip/UI/Console/UserInputUtils.cpp",
    };

    const cpp_src_unix = .{};

    const cpp_src_win = .{};
};

const LibSevenZip = struct {
    const defs = .{
        .{ "_FILE_OFFSET_BITS", "64" },
        .{ "_LARGEFILE_SOURCE", "" },
        .{ "NDEBUG", "" },
        .{ "_REENTRANT", "" },
        .{ "_7ZIP_LARGE_PAGES", "" },
        .{ "RegisterArc", "DllRegisterArc" },
        .{ "RegisterCodec", "DllRegisterCodec" },
        .{ "EXTERNAL_CODECS", "" },
        .{ "BREAK_HANDLER", "" },
        .{ "UNICODE", "" },
        .{ "_UNICODE", "" },
    };

    const c_src = .{
        "7zBuf2.c",
        "7zCrc.c",
        "7zCrcOpt.c",
        "7zStream.c",
        "Aes.c",
        "Alloc.c",
        "Bcj2.c",
        "Bcj2Enc.c",
        "Blake2s.c",
        "Bra.c",
        "Bra86.c",
        "BraIA64.c",
        "BwtSort.c",
        "CpuArch.c",
        "Delta.c",
        "HuffEnc.c",
        "LzFind.c",
        "LzFindMt.c",
        "Lzma2Dec.c",
        "Lzma2Enc.c",
        "LzmaDec.c",
        "LzmaEnc.c",
        "MtCoder.c",
        "Ppmd7.c",
        "Ppmd7Dec.c",
        "Ppmd7Enc.c",
        "Ppmd8.c",
        "Ppmd8Dec.c",
        "Ppmd8Enc.c",
        "Sha1.c",
        "Sha256.c",
        "Sort.c",
        "Threads.c",
        "Xz.c",
        "XzCrc64.c",
        "XzCrc64Opt.c",
        "XzDec.c",
        "XzEnc.c",
        "XzIn.c",
    };

    const cpp_src = .{
        "7zip/Archive/7z/7zCompressionMode.cpp",
        "7zip/Archive/7z/7zDecode.cpp",
        "7zip/Archive/7z/7zEncode.cpp",
        "7zip/Archive/7z/7zExtract.cpp",
        "7zip/Archive/7z/7zFolderInStream.cpp",
        "7zip/Archive/7z/7zHandler.cpp",
        "7zip/Archive/7z/7zHandlerOut.cpp",
        "7zip/Archive/7z/7zHeader.cpp",
        "7zip/Archive/7z/7zIn.cpp",
        "7zip/Archive/7z/7zOut.cpp",
        "7zip/Archive/7z/7zProperties.cpp",
        "7zip/Archive/7z/7zRegister.cpp",
        "7zip/Archive/7z/7zSpecStream.cpp",
        "7zip/Archive/7z/7zUpdate.cpp",
        "7zip/Archive/ApmHandler.cpp",
        "7zip/Archive/ArHandler.cpp",
        "7zip/Archive/ArchiveExports.cpp",
        "7zip/Archive/ArjHandler.cpp",
        "7zip/Archive/Bz2Handler.cpp",
        "7zip/Archive/Cab/CabBlockInStream.cpp",
        "7zip/Archive/Cab/CabHandler.cpp",
        "7zip/Archive/Cab/CabHeader.cpp",
        "7zip/Archive/Cab/CabIn.cpp",
        "7zip/Archive/Cab/CabRegister.cpp",
        "7zip/Archive/Chm/ChmHandler.cpp",
        "7zip/Archive/Chm/ChmIn.cpp",
        "7zip/Archive/ComHandler.cpp",
        "7zip/Archive/Common/CoderMixer2.cpp",
        "7zip/Archive/Common/DummyOutStream.cpp",
        "7zip/Archive/Common/FindSignature.cpp",
        "7zip/Archive/Common/HandlerOut.cpp",
        "7zip/Archive/Common/InStreamWithCRC.cpp",
        "7zip/Archive/Common/ItemNameUtils.cpp",
        "7zip/Archive/Common/MultiStream.cpp",
        "7zip/Archive/Common/OutStreamWithCRC.cpp",
        "7zip/Archive/Common/OutStreamWithSha1.cpp",
        "7zip/Archive/Common/ParseProperties.cpp",
        "7zip/Archive/CpioHandler.cpp",
        "7zip/Archive/CramfsHandler.cpp",
        "7zip/Archive/DeflateProps.cpp",
        "7zip/Archive/DllExports2.cpp",
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
        "7zip/Archive/Iso/IsoHandler.cpp",
        "7zip/Archive/Iso/IsoHeader.cpp",
        "7zip/Archive/Iso/IsoIn.cpp",
        "7zip/Archive/Iso/IsoRegister.cpp",
        "7zip/Archive/LzhHandler.cpp",
        "7zip/Archive/LzmaHandler.cpp",
        "7zip/Archive/MachoHandler.cpp",
        "7zip/Archive/MbrHandler.cpp",
        "7zip/Archive/MslzHandler.cpp",
        "7zip/Archive/MubHandler.cpp",
        "7zip/Archive/Nsis/NsisDecode.cpp",
        "7zip/Archive/Nsis/NsisHandler.cpp",
        "7zip/Archive/Nsis/NsisIn.cpp",
        "7zip/Archive/Nsis/NsisRegister.cpp",
        "7zip/Archive/NtfsHandler.cpp",
        "7zip/Archive/PeHandler.cpp",
        "7zip/Archive/PpmdHandler.cpp",
        "7zip/Archive/QcowHandler.cpp",
        "7zip/Archive/Rar/RarHandler.cpp",
        "7zip/Archive/Rar/Rar5Handler.cpp",
        "7zip/Archive/RpmHandler.cpp",
        "7zip/Archive/SplitHandler.cpp",
        "7zip/Archive/SquashfsHandler.cpp",
        "7zip/Archive/SwfHandler.cpp",
        "7zip/Archive/Tar/TarHandler.cpp",
        "7zip/Archive/Tar/TarHandlerOut.cpp",
        "7zip/Archive/Tar/TarHeader.cpp",
        "7zip/Archive/Tar/TarIn.cpp",
        "7zip/Archive/Tar/TarOut.cpp",
        "7zip/Archive/Tar/TarRegister.cpp",
        "7zip/Archive/Tar/TarUpdate.cpp",
        "7zip/Archive/Udf/UdfHandler.cpp",
        "7zip/Archive/Udf/UdfIn.cpp",
        "7zip/Archive/UefiHandler.cpp",
        "7zip/Archive/VdiHandler.cpp",
        "7zip/Archive/VhdHandler.cpp",
        "7zip/Archive/VmdkHandler.cpp",
        "7zip/Archive/Wim/WimHandler.cpp",
        "7zip/Archive/Wim/WimHandlerOut.cpp",
        "7zip/Archive/Wim/WimIn.cpp",
        "7zip/Archive/Wim/WimRegister.cpp",
        "7zip/Archive/XarHandler.cpp",
        "7zip/Archive/XzHandler.cpp",
        "7zip/Archive/ZHandler.cpp",
        "7zip/Archive/Zip/ZipAddCommon.cpp",
        "7zip/Archive/Zip/ZipHandler.cpp",
        "7zip/Archive/Zip/ZipHandlerOut.cpp",
        "7zip/Archive/Zip/ZipIn.cpp",
        "7zip/Archive/Zip/ZipItem.cpp",
        "7zip/Archive/Zip/ZipOut.cpp",
        "7zip/Archive/Zip/ZipRegister.cpp",
        "7zip/Archive/Zip/ZipUpdate.cpp",
        "7zip/Common/CWrappers.cpp",
        "7zip/Common/CreateCoder.cpp",
        "7zip/Common/FilterCoder.cpp",
        "7zip/Common/InBuffer.cpp",
        "7zip/Common/InOutTempBuffer.cpp",
        "7zip/Common/LimitedStreams.cpp",
        "7zip/Common/MemBlocks.cpp",
        "7zip/Common/MethodId.cpp",
        "7zip/Common/MethodProps.cpp",
        "7zip/Common/OffsetStream.cpp",
        "7zip/Common/OutBuffer.cpp",
        "7zip/Common/OutMemStream.cpp",
        "7zip/Common/ProgressMt.cpp",
        "7zip/Common/ProgressUtils.cpp",
        "7zip/Common/PropId.cpp",
        "7zip/Common/StreamBinder.cpp",
        "7zip/Common/StreamObjects.cpp",
        "7zip/Common/StreamUtils.cpp",
        "7zip/Common/UniqBlocks.cpp",
        "7zip/Common/VirtThread.cpp",
        "7zip/Compress/BZip2Crc.cpp",
        "7zip/Compress/BZip2Decoder.cpp",
        "7zip/Compress/BZip2Encoder.cpp",
        "7zip/Compress/BZip2Register.cpp",
        "7zip/Compress/Bcj2Coder.cpp",
        "7zip/Compress/Bcj2Register.cpp",
        "7zip/Compress/BcjCoder.cpp",
        "7zip/Compress/BcjRegister.cpp",
        "7zip/Compress/BitlDecoder.cpp",
        "7zip/Compress/BranchMisc.cpp",
        "7zip/Compress/BranchRegister.cpp",
        "7zip/Compress/ByteSwap.cpp",
        "7zip/Compress/CodecExports.cpp",
        "7zip/Compress/CopyCoder.cpp",
        "7zip/Compress/CopyRegister.cpp",
        "7zip/Compress/Deflate64Register.cpp",
        "7zip/Compress/DeflateDecoder.cpp",
        "7zip/Compress/DeflateEncoder.cpp",
        "7zip/Compress/DeflateRegister.cpp",
        "7zip/Compress/DeltaFilter.cpp",
        "7zip/Compress/ImplodeDecoder.cpp",
        "7zip/Compress/ImplodeHuffmanDecoder.cpp",
        "7zip/Compress/LzOutWindow.cpp",
        "7zip/Compress/LzhDecoder.cpp",
        "7zip/Compress/Lzma2Decoder.cpp",
        "7zip/Compress/Lzma2Encoder.cpp",
        "7zip/Compress/Lzma2Register.cpp",
        "7zip/Compress/LzmaDecoder.cpp",
        "7zip/Compress/LzmaEncoder.cpp",
        "7zip/Compress/LzmaRegister.cpp",
        "7zip/Compress/LzmsDecoder.cpp",
        "7zip/Compress/LzxDecoder.cpp",
        "7zip/Compress/PpmdDecoder.cpp",
        "7zip/Compress/PpmdEncoder.cpp",
        "7zip/Compress/PpmdRegister.cpp",
        "7zip/Compress/PpmdZip.cpp",
        "7zip/Compress/QuantumDecoder.cpp",
        "7zip/Compress/ShrinkDecoder.cpp",
        "7zip/Compress/ZDecoder.cpp",
        "7zip/Compress/XpressDecoder.cpp",
        "7zip/Compress/ZlibDecoder.cpp",
        "7zip/Compress/ZlibEncoder.cpp",
        "7zip/Crypto/7zAes.cpp",
        "7zip/Crypto/7zAesRegister.cpp",
        "7zip/Crypto/HmacSha1.cpp",
        "7zip/Crypto/HmacSha256.cpp",
        "7zip/Crypto/MyAes.cpp",
        "7zip/Crypto/MyAesReg.cpp",
        "7zip/Crypto/Pbkdf2HmacSha1.cpp",
        "7zip/Crypto/RandGen.cpp",
        "7zip/Crypto/Rar20Crypto.cpp",
        "7zip/Crypto/Rar5Aes.cpp",
        "7zip/Crypto/RarAes.cpp",
        "7zip/Crypto/WzAes.cpp",
        "7zip/Crypto/ZipCrypto.cpp",
        "7zip/Crypto/ZipStrong.cpp",
        "Common/CRC.cpp",
        "Common/CrcReg.cpp",
        "Common/DynLimBuf.cpp",
        "Common/IntToString.cpp",
        "Common/MyMap.cpp",
        "Common/MyString.cpp",
        "Common/MyVector.cpp",
        "Common/MyWindows.cpp",
        "Common/MyXml.cpp",
        "Common/NewHandler.cpp",
        "Common/Sha1Reg.cpp",
        "Common/Sha256Reg.cpp",
        "Common/StringConvert.cpp",
        "Common/StringToInt.cpp",
        "Common/UTFConvert.cpp",
        "Common/Wildcard.cpp",
        "Common/XzCrc64Reg.cpp",
        "Windows/FileDir.cpp",
        "Windows/FileFind.cpp",
        "Windows/FileIO.cpp",
        "Windows/FileName.cpp",
        "Windows/PropVariant.cpp",
        "Windows/PropVariantUtils.cpp",
        "Windows/Synchronization.cpp",
        "Windows/System.cpp",
        "Windows/TimeUtils.cpp",
    };

    const cpp_src_unix = .{
        "myWindows/wine_date_and_time.cpp",
    };
};
