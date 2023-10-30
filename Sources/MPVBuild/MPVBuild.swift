//
//  Build.swift
//
//
//  Created by karelrooted on 10/24/23.
//

import ArgumentParser
import Foundation

@main
struct MPVBuild: ParsableCommand {
    static var configuration = CommandConfiguration(
        abstract: "Cross Compile libmpv for apple platform(iOS, tvOS, MacOS).",
        discussion: """
        Swift PM: https://github.com/karelrooted/MPVKit.git
        """
    )

    @Option(name: .shortAndLong, help: "Target platforms '(iOS, tvOS, MacOS)'. Default All")
    var platforms: [String] = []

    @Flag(help: "disable-openssl.")
    var disableOpenssl = false

    @Flag(help: "disable-libass.")
    var disableLibass = false

    @Flag(help: "disable-libplacebo .")
    var disablePlacebo = false

    @Flag(help: "disable-ffmpeg.")
    var disableFfmpeg = false

    @Flag(help: "disable-mpv.")
    var disableMpv = false

    // according to the official document, static link moltenvk is not the right way on mac
    // please consider disable this on macos, and manuly import vulkan.framework to xcode project to use vukan dylib
    @Flag(help: "disable-staic-link-moltenvk-on-mac.")
    var disableStaticLinkMoltenVkOnMac = false

    @Flag(help: "enable-libsrt.")
    var enableLibsrt = false

    @Flag(help: "enable-libsmbclient.")
    var enableLibsmbclient = false

    @Flag(help: "enable-debug.")
    var enableDebug = false

    mutating func run() throws {
        if Utility.shell("which brew") == nil {
            print("""
            You need to install brew first
            /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
            """)
            return
        }
        Utility.shell("brew list pkg-config || brew install pkg-config")
        Utility.shell("brew list automake || brew install automake")
        Utility.shell("brew list meson || brew install meson")

        // var currentWorkingDir = URL.currentDirectory
        /// URL #file pointing to the current source file when it was compiled.
        let currentSourceFileURL = URL(fileURLWithPath: #file, isDirectory: false)
        let currentWorkingDir = currentSourceFileURL.deletingLastPathComponent() + "../../"

        let path = currentWorkingDir + "build"

        if !FileManager.default.fileExists(atPath: path.path) {
            try? FileManager.default.createDirectory(at: path, withIntermediateDirectories: false, attributes: nil)
        }
        FileManager.default.changeCurrentDirectoryPath(path.path)
        if platforms.isEmpty {
            BaseBuild.platforms = PlatformType.allCases
        } else {
            BaseBuild.platforms = platforms.compactMap { platform in
                PlatformType(rawValue: platform)
            }
        }
        if !disableOpenssl {
            try BuildOpenSSL().buildALL()
        }
        if enableLibsrt {
            try BuildSRT().buildALL()
        }
        if !disableLibass {
            // try BuildPng().buildALL()
            // try BuildBrotli().buildALL()
            try BuildFreetype().buildALL()
            try BuildFribidi().buildALL()
            try BuildHarfbuzz().buildALL()
            try BuildASS().buildALL()
        }
        if enableLibsmbclient {
            try BuildGmp().buildALL()
            try BuildNettle().buildALL()
            try BuildGnutls().buildALL()
            try BuildSmbclient().buildALL()
        }
        if !disablePlacebo {
            // try BuildMoltenVK().buildALL()
            // try BuildShaderc().buildALL()
            try BuildLittleCms().buildALL()
            try BuildLibPlacebo().buildALL()
        }
        if !disableFfmpeg {
            // try BuildDav1d().buildALL()
            try BuildLibbluray().buildALL()
            try BuildFFMPEG(enableDebug: enableDebug).buildALL()
        }
        if !disableMpv {
            // try BuildUchardet().buildALL()
            //try BuildLuaJit().buildALL()
            try BuildMPV(disableStaticLinkMoltenVkOnMac: disableStaticLinkMoltenVkOnMac).buildALL()
        }
    }
}

private enum Library: String, CaseIterable {
    case ffmpeg, freetype, fribidi, harfbuzz, libass, libpng, mpv, openssl, srt, smbclient,
         gnutls, gmp, nettle, brotli, uchardet, libplacebo, littlecms, libbluray, LuaJIT, shaderc, MoltenVK, libdav1d
}

private class BaseBuild {
    static var platforms = PlatformType.allCases
    private let library: Library
    let directoryURL: URL
    init(library: Library) {
        self.library = library
        directoryURL = URL.currentDirectory + "../Vendor/\(library.rawValue)"
    }

    func buildALL() throws {
        // try? FileManager.default.removeItem(at: URL.currentDirectory + library.rawValue)
        for platform in BaseBuild.platforms {
            for arch in architectures(platform) {
                try build(platform: platform, arch: arch)
            }
        }
        try createXCFramework()
    }

    func architectures(_ platform: PlatformType) -> [ArchType] {
        platform.architectures()
    }

    func build(platform: PlatformType, arch: ArchType) throws {
        let buildURL = scratch(platform: platform, arch: arch)
        let thinURL = thinDir(platform: platform, arch: arch)
        try? FileManager.default.removeItem(at: buildURL)
        try? FileManager.default.removeItem(at: thinURL)
        try? FileManager.default.createDirectory(at: buildURL, withIntermediateDirectories: true, attributes: nil)
        // try? _ = Utility.launch(path: "/usr/bin/make", arguments: ["distclean"], currentDirectoryURL: buildURL)
        // try? _ = Utility.launch(path: "/usr/bin/make", arguments: ["clean"], currentDirectoryURL: buildURL)
        let environ = environment(platform: platform, arch: arch)
        if FileManager.default.fileExists(atPath: (directoryURL + "meson.build").path) {
            // let meson = Utility.shell("which meson", isOutput: true)!
            let meson = "/usr/local/bin/meson"
            // print("before meson")
            // print(meson)
            var argus = arguments(platform: platform, arch: arch)
            let crossFile = crossFilePath(platform: platform, arch: arch)
            if crossFile != "" {
                argus.append("--cross-file=\(crossFile)")
            }

            do {
                try Utility.launch(path: meson, arguments: ["setup", buildURL.path] + argus, currentDirectoryURL: directoryURL, environment: environ)
                try Utility.launch(path: meson, arguments: ["compile", "-C", buildURL.path], currentDirectoryURL: directoryURL, environment: environ)
                try Utility.launch(path: meson, arguments: ["install", "-C", buildURL.path], currentDirectoryURL: directoryURL, environment: environ)
            } catch {
                let logFile = scratch(platform: platform, arch: arch) + "meson-logs/meson-log.txt"
                if let data = FileManager.default.contents(atPath: logFile.path), let str = String(data: data, encoding: .utf8) {
                    //print(str)
                }
                throw error
            }

        } else {
            try configure(buildURL: buildURL, environ: environ, platform: platform, arch: arch)
            try Utility.launch(path: "/usr/bin/make", arguments: ["-j5", "-s"], currentDirectoryURL: buildURL, environment: environ)
            try Utility.launch(path: "/usr/bin/make", arguments: ["-j5", "install", "-s"], currentDirectoryURL: buildURL, environment: environ)
        }
    }

    func configure(buildURL: URL, environ: [String: String], platform: PlatformType, arch: ArchType) throws {
        let autogen = directoryURL + "autogen.sh"
        if FileManager.default.fileExists(atPath: autogen.path) {
            var environ = environ
            environ["NOCONFIGURE"] = "1"
            try Utility.launch(executableURL: autogen, arguments: [], currentDirectoryURL: directoryURL, environment: environ)
        }
        let configure = directoryURL + "\(configureFileName())"
        var bootstrap = directoryURL + "bootstrap"
        if !FileManager.default.fileExists(atPath: configure.path), FileManager.default.fileExists(atPath: bootstrap.path) {
            try Utility.launch(executableURL: bootstrap, arguments: [], currentDirectoryURL: directoryURL, environment: environ)
        }
        bootstrap = directoryURL + ".bootstrap"
        if !FileManager.default.fileExists(atPath: configure.path), FileManager.default.fileExists(atPath: bootstrap.path) {
            try Utility.launch(executableURL: bootstrap, arguments: [], currentDirectoryURL: directoryURL, environment: environ)
        }
        try Utility.launch(executableURL: configure, arguments: arguments(platform: platform, arch: arch), currentDirectoryURL: buildURL, environment: environ)
    }

    func configureFileName() -> String {
        return "configure"
    }

    func getVulkanPkgconfig(buildURL: URL, platform: PlatformType, arch: ArchType) -> String {
        var path = ""
        switch platform {
        case .ios:
            path = "ios-arm64"
        case .isimulator:
            path = "ios-arm64_x86_64-simulator"
        case .tvsimulator:
            path = "tvos-arm64_x86_64-simulator"
        case .tvos:
            path = "tvos-arm64_arm64e"
        case .macos:
            path = "macos-arm64_x86_64"
        case .maccatalyst:
            path = "ios-arm64_x86_64-maccatalyst"
        }

        let vulkanPkgUrl = buildURL + "pkgconfig"
        try? FileManager.default.createDirectory(at: vulkanPkgUrl, withIntermediateDirectories: true, attributes: nil)
        let pkgfile = vulkanPkgUrl + "vulkan.pc"
        let str = """
        prefix=\((directoryURL + "/../..").path)/Framework/MoltenVK.xcframework/\(path)
        includedir=${prefix}/include
        libdir=${prefix}


        Name: vulkan
        Description: vulkan
        Version: 1.3.268.1
        Libs: -L${libdir} -lMoltenVK
        Cflags: -I${includedir} -DPL_HAVE_PTHREAD  -DPL_STATIC
        """
        do {
            try str.write(toFile: pkgfile.path, atomically: true, encoding: .utf8)
        } catch {
            print("Unexpected error: \(error).")
        }

        if platform == .macos {
            // return ""
        }
        return (platform == .ios && arch == .arm64e) ? "" : vulkanPkgUrl.path + ":"
    }

    func crossFilePath(platform: PlatformType, arch: ArchType) -> String {
        let url = scratch(platform: platform, arch: arch)
        let crossFile = url + "crossFile.meson"
        let prefix = thinDir(platform: platform, arch: arch)
        let content = """
        [binaries]
        c = ['/usr/bin/clang', '-arch', '\(arch.rawValue)']
        cpp = ['/usr/bin/clang++', '-arch', '\(arch.rawValue)']
        objc = ['/usr/bin/clang', '-arch', '\(arch.rawValue)']
        objcpp = ['/usr/bin/clang++', '-arch', '\(arch.rawValue)']
        ar = '\(platform.xcrunFind(tool: "ar"))'
        strip = '\(platform.xcrunFind(tool: "strip"))'
        pkgconfig = 'pkg-config'

        [properties]
        has_function_printf = true
        has_function_hfkerhisadf = false

        [host_machine]
        system = 'darwin'
        subsystem = '\(platform.mesonSubSystem)'
        kernel = 'xnu'
        cpu_family = '\(arch.cpuFamily())'
        cpu = '\(arch.targetCpu())'
        endian = 'little'

        [built-in options]
        default_library = 'static'
        buildtype = 'release'
        prefix = '\(prefix.path)'
        """
        FileManager.default.createFile(atPath: crossFile.path, contents: content.data(using: .utf8), attributes: nil)
        return crossFile.path
    }

    private func pkgConfigPath(platform: PlatformType, arch: ArchType) -> String {
        var pkgConfigPath = ""
        for lib in Library.allCases {
            let path = URL.currentDirectory + [lib.rawValue, platform.rawValue, "thin", arch.rawValue]
            if FileManager.default.fileExists(atPath: path.path) {
                pkgConfigPath += "\(path.path)/lib/pkgconfig:"
            }
        }
        return pkgConfigPath
    }

    func environment(platform: PlatformType, arch: ArchType) -> [String: String] {
        let buildURL = scratch(platform: platform, arch: arch)
        var environ = [
            "LC_CTYPE": "C",
            "CC": ccFlags(platform: platform, arch: arch),
            "CFLAGS": cFlags(platform: platform, arch: arch),
            "CPPFLAGS": cFlags(platform: platform, arch: arch),
            "CXXFLAGS": cFlags(platform: platform, arch: arch),
            "LDFLAGS": ldFlags(platform: platform, arch: arch),
            "PKG_CONFIG_PATH": pkgConfigPath(platform: platform, arch: arch),
            "CMAKE_OSX_ARCHITECTURES": arch.rawValue,
            "PATH": "/usr/local/opt/gnu-sed/libexec/gnubin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin",
        ]
        environ["PKG_CONFIG_PATH"] = environ["PKG_CONFIG_PATH"]! + getVulkanPkgconfig(buildURL: buildURL, platform: platform, arch: arch)
        return environ
    }

    func ccFlags(platform _: PlatformType, arch _: ArchType) -> String {
        "/usr/bin/clang "
    }

    func cFlags(platform: PlatformType, arch: ArchType) -> String {
        var cflags = "-g -arch " + arch.rawValue + " " + platform.deploymentTarget(arch)
        if platform == .macos || platform == .maccatalyst {
            cflags += " -fno-common"
        }
        let syslibroot = platform.isysroot()
        cflags += " -isysroot \(syslibroot)"
        if platform == .maccatalyst {
            cflags += " -iframework \(syslibroot)/System/iOSSupport/System/Library/Frameworks"
        }
        if platform == .tvos || platform == .tvsimulator {
            cflags += " -DHAVE_FORK=0"
        }
        return cflags
    }

    func ldFlags(platform: PlatformType, arch: ArchType) -> String {
        cFlags(platform: platform, arch: arch)
    }

    func arguments(platform: PlatformType, arch: ArchType) -> [String] {
        return [
            "--prefix=\(thinDir(platform: platform, arch: arch).path)",
        ]
    }

    func createXCFramework(useFramework: Bool = false) throws {
        var frameworks: [String] = []
        if let platform = BaseBuild.platforms.first {
            if let arch = architectures(platform).first {
                let lib = thinDir(platform: platform, arch: arch) + "lib"
                if FileManager.default.fileExists(atPath: lib.path) {
                    let fileNames = try FileManager.default.contentsOfDirectory(atPath: lib.path)
                    for fileName in fileNames {
                        if fileName.hasPrefix("lib"), fileName.hasSuffix(".a") {
                            frameworks.append("lib" + fileName.dropFirst(3).dropLast(2))
                        }
                    }
                }
            }
        }
        for framework in frameworks {
            var arguments = ["-create-xcframework"]
            for platform in PlatformType.allCases {
                if useFramework {
                    do {
                        let result = try createFramework(framework: framework, platform: platform)
                        arguments.append("-framework")
                        arguments.append(result)
                    } catch {
                        continue
                    }
                } else {
                    let universalDir = URL.currentDirectory + [library.rawValue, platform.rawValue, "\(framework).universal"]
                    try? FileManager.default.removeItem(at: universalDir)
                    try? FileManager.default.createDirectory(at: universalDir, withIntermediateDirectories: true, attributes: nil)
                    var lipoArguments = ["-create"]
                    for arch in architectures(platform) {
                        let prefix = thinDir(platform: platform, arch: arch)
                        if !FileManager.default.fileExists(atPath: (prefix + ["lib", "\(framework).a"]).path) {
                            continue
                        }
                        lipoArguments.append((prefix + ["lib", "\(framework).a"]).path)
                        var headerURL = prefix + "include" + framework
                        if !FileManager.default.fileExists(atPath: headerURL.path) {
                            headerURL = prefix + "include"
                        }
                        try? FileManager.default.copyItem(at: headerURL, to: universalDir + "Headers")
                    }
                    if lipoArguments.count == 1 {
                        continue
                    }
                    lipoArguments.append("-output")
                    lipoArguments.append((universalDir + "\(framework).a").path)
                    try Utility.launch(path: "/usr/bin/lipo", arguments: lipoArguments)
                    arguments.append("-library")
                    arguments.append((universalDir + "\(framework).a").path)
                    arguments.append("-headers")
                    arguments.append((universalDir + "Headers").path)
                }
            }
            arguments.append("-output")
            let XCFrameworkFile = URL.currentDirectory + ["../Framework", framework.firstUppercased + ".xcframework"]
            arguments.append(XCFrameworkFile.path)
            if FileManager.default.fileExists(atPath: XCFrameworkFile.path) {
                try? FileManager.default.removeItem(at: XCFrameworkFile)
            }
            try Utility.launch(path: "/usr/bin/xcodebuild", arguments: arguments)
        }
    }

    private func createFramework(framework: String, platform: PlatformType) throws -> String {
        let frameworkDir = URL.currentDirectory + [library.rawValue, platform.rawValue, "\(framework.firstUppercased).framework"]
        try? FileManager.default.removeItem(at: frameworkDir)
        try? FileManager.default.createDirectory(at: frameworkDir, withIntermediateDirectories: true, attributes: nil)
        var arguments = ["-create"]
        for arch in architectures(platform) {
            let prefix = thinDir(platform: platform, arch: arch)
            if !FileManager.default.fileExists(atPath: (prefix + ["lib", "\(framework).a"]).path) {
                continue
            }
            arguments.append((prefix + ["lib", "\(framework).a"]).path)
            var headerURL = prefix + "include" + framework
            if !FileManager.default.fileExists(atPath: headerURL.path) {
                headerURL = prefix + "include"
            }
            try? FileManager.default.copyItem(at: headerURL, to: frameworkDir + "Headers")
        }
        arguments.append("-output")
        arguments.append((frameworkDir + framework.firstUppercased).path)
        try Utility.launch(path: "/usr/bin/lipo", arguments: arguments)
        try? FileManager.default.createDirectory(at: frameworkDir + "Modules", withIntermediateDirectories: true, attributes: nil)
        var modulemap = """
        framework module \(framework.firstUppercased) [system] {
            umbrella "."

        """
        frameworkExcludeHeaders(framework.firstUppercased).forEach { header in
            modulemap += """
                exclude header "\(header).h"

            """
        }
        modulemap += """
            export *
        }
        """
        FileManager.default.createFile(atPath: frameworkDir.path + "/Modules/module.modulemap", contents: modulemap.data(using: .utf8), attributes: nil)
        createPlist(path: frameworkDir.path + "/Info.plist", name: framework.firstUppercased, minVersion: platform.minVersion, platform: platform.sdk())
        return frameworkDir.path
    }

    func thinDir(platform: PlatformType, arch: ArchType) -> URL {
        URL.currentDirectory + [library.rawValue, platform.rawValue, "thin", arch.rawValue]
    }

    func scratch(platform: PlatformType, arch: ArchType) -> URL {
        URL.currentDirectory + [library.rawValue, platform.rawValue, "scratch", arch.rawValue]
    }

    func frameworkExcludeHeaders(_: String) -> [String] {
        []
    }

    private func createPlist(path: String, name: String, minVersion: String, platform: String) {
        let identifier = "com.kintan.ksplayer." + name
        let content = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
        <key>CFBundleDevelopmentRegion</key>
        <string>en</string>
        <key>CFBundleExecutable</key>
        <string>\(name)</string>
        <key>CFBundleIdentifier</key>
        <string>\(identifier)</string>
        <key>CFBundleInfoDictionaryVersion</key>
        <string>6.0</string>
        <key>CFBundleName</key>
        <string>\(name)</string>
        <key>CFBundlePackageType</key>
        <string>FMWK</string>
        <key>CFBundleShortVersionString</key>
        <string>87.88.520</string>
        <key>CFBundleVersion</key>
        <string>87.88.520</string>
        <key>CFBundleSignature</key>
        <string>????</string>
        <key>MinimumOSVersion</key>
        <string>\(minVersion)</string>
        <key>CFBundleSupportedPlatforms</key>
        <array>
        <string>\(platform)</string>
        </array>
        <key>NSPrincipalClass</key>
        <string></string>
        </dict>
        </plist>
        """
        FileManager.default.createFile(atPath: path, contents: content.data(using: .utf8), attributes: nil)
    }
}

private class BuildFFMPEG: BaseBuild {
    private let isDebug: Bool
    init(enableDebug: Bool) {
        isDebug = enableDebug
        super.init(library: .ffmpeg)
    }

     override func getVulkanPkgconfig(buildURL: URL, platform: PlatformType, arch: ArchType) -> String {
        if platform == .maccatalyst {
            return ""
        }
        
        return super.getVulkanPkgconfig(buildURL: buildURL, platform: platform, arch: arch)
    }

    override func build(platform: PlatformType, arch: ArchType) throws {
        if platform == .maccatalyst {
            return
        }
        do {
            try super.build(platform: platform, arch: arch)
        } catch {
            let logFile = scratch(platform: platform, arch: arch) + "ffbuild/config.log"
            if let data = FileManager.default.contents(atPath: logFile.path), let str = String(data: data, encoding: .utf8) {
                //print(str)
            }
            throw MyError.buildError("build ffmpeg error: \(error)")
        }
        let buildDir = scratch(platform: platform, arch: arch)
        let lldbFile = URL.currentDirectory + "LLDBInitFile"
        if let data = FileManager.default.contents(atPath: lldbFile.path), var str = String(data: data, encoding: .utf8) {
            str.append("settings \(str.count == 0 ? "set" : "append") target.source-map \((buildDir + "src").path) \(directoryURL.path)\n")
            try str.write(toFile: lldbFile.path, atomically: true, encoding: .utf8)
        }
        if platform == .macos, arch.executable() {
            // let prefix = thinDir(platform: platform, arch: arch)
            // try replaceBin(prefix: prefix, item: "ffmpeg")
            // try replaceBin(prefix: prefix, item: "ffplay")
            // try replaceBin(prefix: prefix, item: "ffprobe")
        }
    }

    override func cFlags(platform: PlatformType, arch: ArchType) -> String {
        var cflags = super.cFlags(platform: platform, arch: arch)
        cflags += " -framework Metal -framework QuartzCore -framework Foundation -framework IOSurface -framework CoreGraphics -lc++ "
        switch platform {
        case .macos:
            cflags += " -framework IOKit -framework APPKit "
        case .maccatalyst:
            cflags += " -framework IOKit -framework APPKit -framework UIKit "
        case .ios:
            cflags += " -framework IOKit -framework UIKit "
        default:
            cflags += " -framework UIKit "
        }
        return cflags
    }

    override func ldFlags(platform: PlatformType, arch: ArchType) -> String {
        var ldflags = super.ldFlags(platform: platform, arch: arch)
        ldflags += " /usr/local/lib/libfontconfig.a "
        return ldflags
    }

    override func arguments(platform: PlatformType, arch: ArchType) -> [String] {
        var arguments = super.arguments(platform: platform, arch: arch)
        arguments += ffmpegConfiguers
        if isDebug {
            arguments.append("--enable-debug")
            arguments.append("--disable-stripping")
            arguments.append("--disable-optimizations")
        } else {
            arguments.append("--disable-debug")
            arguments.append("--enable-stripping")
            arguments.append("--enable-optimizations")
        }
        arguments.append("--ignore-tests=TESTS")
        arguments.append("--disable-large-tests")
        arguments.append("--enable-libbluray")
        /**
         aacpsdsp.o), building for Mac Catalyst, but linking in object file built for
         x86_64 binaries are built without ASM support, since ASM for x86_64 is actually x86 and that confuses `xcodebuild -create-xcframework` https://stackoverflow.com/questions/58796267/building-for-macos-but-linking-in-object-file-built-for-free-standing/59103419#59103419
         */
        if platform == .maccatalyst || arch == .x86_64 {
            arguments.append("--disable-neon")
            arguments.append("--disable-asm")
        } else {
            arguments.append("--enable-neon")
            arguments.append("--enable-asm")
        }
        if platform == .macos, arch.executable() {
            arguments.append("--enable-ffplay")
            arguments.append("--enable-sdl2")
            arguments.append("--enable-encoder=aac")
            arguments.append("--enable-encoder=movtext")
            arguments.append("--enable-encoder=mpeg4")
            arguments.append("--enable-decoder=rawvideo")
            arguments.append("--enable-filter=color")
            arguments.append("--enable-filter=lut")
            arguments.append("--enable-filter=negate")
            arguments.append("--enable-filter=testsrc")
            arguments.append("--enable-pic")
            arguments.append("--disable-indev=avfoundation")
            arguments.append("--disable-outdev=audiotoolbox")
            // arguments.append("--disable-avdevice")
            arguments.append("--enable-avdevice")
            //            arguments.append("--enable-indev=lavfi")
        } else {
            arguments.append("--enable-pic")
            arguments.append("--disable-indev=avfoundation")
            arguments.append("--disable-outdev=audiotoolbox")
            arguments.append("--enable-avdevice")
            // arguments.append("--disable-avdevice")
            arguments.append("--disable-programs")
        }
        //        if platform == .isimulator || platform == .tvsimulator {
        //            arguments.append("--assert-level=1")
        //        }
        for library in [Library.openssl, .libass, .fribidi, .freetype, .srt, .smbclient, .libplacebo, .shaderc, .libdav1d] {
            let path = URL.currentDirectory + [library.rawValue, platform.rawValue, "thin", arch.rawValue]
            if FileManager.default.fileExists(atPath: path.path) {
                let libraryName = [.openssl, .libass, .libplacebo, .libdav1d].contains(library) ? library.rawValue : "lib" + library.rawValue
                if (library != .libplacebo || (arch != .arm64e && platform != .maccatalyst))  && (library != .shaderc || arch != .arm64e) {
                    arguments.append("--enable-\(libraryName)")
                }
                if library == .srt {
                    arguments.append("--enable-protocol=\(libraryName)")
                }
                if library == .libass {
                    arguments.append("--enable-filter=subtitles")
                }
            }
        }
        arguments.append("--target-os=darwin")

        arguments.append("--arch=\(arch.arch())")
        // arguments.append(arch.cpu())
        return arguments
    }

    private func replaceBin(prefix: URL, item: String) throws {
        if FileManager.default.fileExists(atPath: (prefix + ["bin", item]).path) {
            try? FileManager.default.removeItem(at: URL(fileURLWithPath: "/usr/local/bin/\(item)"))
            try? FileManager.default.copyItem(at: prefix + ["bin", item], to: URL(fileURLWithPath: "/usr/local/bin/\(item)"))
        }
    }

    override func createXCFramework(useFramework: Bool = true) throws {
        try super.createXCFramework(useFramework: true)
        // makeFFmpegSourece()
    }

    private func makeFFmpegSourece() throws {
        guard let platform = BaseBuild.platforms.first, let arch = architectures(platform).first else {
            return
        }
        let target = URL.currentDirectory + ["../Framework", "LibFFmpeg"]
        try? FileManager.default.removeItem(at: target)
        try? FileManager.default.createDirectory(at: target, withIntermediateDirectories: true, attributes: nil)
        let thin = thinDir(platform: platform, arch: arch)
        try? FileManager.default.copyItem(at: thin + "include", to: target + "include")
        let scratchURL = scratch(platform: platform, arch: arch)
        try? FileManager.default.createDirectory(at: target + "include", withIntermediateDirectories: true, attributes: nil)
        try? FileManager.default.copyItem(at: scratchURL + "config.h", to: target + "include" + "config.h")
        let fileNames = try FileManager.default.contentsOfDirectory(atPath: scratchURL.path)
        for fileName in fileNames where fileName.hasPrefix("lib") {
            var url = scratchURL + fileName
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue {
                // copy .c
                if let subpaths = FileManager.default.enumerator(atPath: url.path) {
                    let dstDir = target + fileName
                    while let subpath = subpaths.nextObject() as? String {
                        if subpath.hasSuffix(".c") {
                            let srcURL = url + subpath
                            let dstURL = target + "include" + fileName + subpath
                            try? FileManager.default.copyItem(at: srcURL, to: dstURL)
                        } else if subpath.hasSuffix(".o") {
                            let subpath = subpath.replacingOccurrences(of: ".o", with: ".c")
                            let srcURL = scratchURL + "src" + fileName + subpath
                            let dstURL = dstDir + subpath
                            let dstURLDir = dstURL.deletingLastPathComponent()
                            if !FileManager.default.fileExists(atPath: dstURLDir.path) {
                                try? FileManager.default.createDirectory(at: dstURLDir, withIntermediateDirectories: true, attributes: nil)
                            }
                            try? FileManager.default.copyItem(at: srcURL, to: dstURL)
                        }
                    }
                }
                url = scratchURL + "src" + fileName
                // copy .h
                try? FileManager.default.copyItem(at: scratchURL + "src" + "compat", to: target + "compat")
                if let subpaths = FileManager.default.enumerator(atPath: url.path) {
                    let dstDir = target + "include" + fileName
                    while let subpath = subpaths.nextObject() as? String {
                        if subpath.hasSuffix(".h") || subpath.hasSuffix("_template.c") {
                            let srcURL = url + subpath
                            let dstURL = dstDir + subpath
                            let dstURLDir = dstURL.deletingLastPathComponent()
                            if !FileManager.default.fileExists(atPath: dstURLDir.path) {
                                try? FileManager.default.createDirectory(at: dstURLDir, withIntermediateDirectories: true, attributes: nil)
                            }
                            try? FileManager.default.copyItem(at: srcURL, to: dstURL)
                        }
                    }
                }
            }
        }
    }

    override func buildALL() throws {
        Utility.shell("brew list nasm || brew install nasm")
        Utility.shell("brew list sdl2 || brew install sdl2")
        Utility.shell("brew list gnu-sed || brew install gnu-sed")
        let lldbFile = URL.currentDirectory + "LLDBInitFile"
        try? FileManager.default.removeItem(at: lldbFile)
        FileManager.default.createFile(atPath: lldbFile.path, contents: nil, attributes: nil)
        let _ = try? Utility.launch(path: "/usr/bin/git", arguments: ["apply", "\(directoryURL.path)/../../Sources/MPVBuild/ffmpeg.patch"], currentDirectoryURL: directoryURL)
        try super.buildALL()
    }

    override func frameworkExcludeHeaders(_ framework: String) -> [String] {
        if framework == "Libavcodec" {
            return ["xvmc", "vdpau", "qsv", "dxva2", "d3d11va"]
        } else if framework == "Libavutil" {
            return ["hwcontext_vulkan", "hwcontext_vdpau", "hwcontext_vaapi", "hwcontext_qsv", "hwcontext_opencl", "hwcontext_dxva2", "hwcontext_d3d11va", "hwcontext_cuda"]
        } else {
            return super.frameworkExcludeHeaders(framework)
        }
    }

    private let ffmpegConfiguers = [
        // Configuration options:
        "--disable-armv5te", "--disable-armv6", "--disable-armv6t2", "--disable-bsfs",
        "--disable-bzlib", "--disable-gray", "--disable-iconv", "--disable-linux-perf",
        "--disable-xlib", "--disable-swscale-alpha", "--disable-symver", "--disable-small",
        "--enable-cross-compile", "--enable-gpl", "--enable-libxml2", "--enable-nonfree",
        "--enable-runtime-cpudetect", "--enable-thumb", "--enable-version3", "--pkg-config-flags=--static",
        "--enable-static", "--disable-shared",
        // Documentation options:
        "--disable-doc", "--disable-htmlpages", "--disable-manpages", "--disable-podpages", "--disable-txtpages",
        // Component options:
        "--enable-avcodec", "--enable-avformat", "--enable-avutil", "--enable-network", "--enable-swresample", "--enable-swscale",
        "--disable-devices", "--disable-outdevs", "--disable-indevs", "--disable-postproc",
        // ,"--disable-pthreads"
        // ,"--disable-w32threads"
        // ,"--disable-os2threads"
        // ,"--disable-dct"
        // ,"--disable-dwt"
        // ,"--disable-lsp"
        // ,"--disable-lzo"
        // ,"--disable-mdct"
        // ,"--disable-rdft"
        // ,"--disable-fft"
        // Hardware accelerators:
        // "--disable-d3d11va", "--disable-dxva2", "--disable-vaapi", "--disable-vdpau",
        // "--enable-videotoolbox", "--enable-audiotoolbox",
        // Individual component options:
        // ,"--disable-everything"
        // ./configure --list-decoders
        // ./configure --list-muxers
        // ./configure --list-demuxers
        // ./configure --list-protocols
        // filters
        // "--disable-protocol=bluray"
        "--enable-protocols",
        "--disable-protocol=ffrtmpcrypt", "--disable-protocol=gopher", "--disable-protocol=icecast",
        "--disable-protocol=librtmp*", "--disable-protocol=libssh", "--disable-protocol=md5", "--disable-protocol=mmsh",
        "--disable-protocol=mmst", "--disable-protocol=sctp", "--disable-protocol=subfile", "--disable-protocol=unix",
    ]
}

private class BuildOpenSSL: BaseBuild {
    init() {
        super.init(library: .openssl)
    }

    override func configureFileName() -> String {
        return "Configure"
    }

    override func arguments(platform: PlatformType, arch: ArchType) -> [String] {
        super.arguments(platform: platform, arch: arch) +
            [
                arch == .x86_64 ? "darwin64-x86_64" : arch == .arm64e ? "iphoneos-cross" : "darwin64-arm64",
                "no-async", "no-shared", "no-dso", "no-engine", "no-tests",
            ]
    }

    override func createXCFramework(useFramework: Bool = true) throws {
        try super.createXCFramework(useFramework: true)
    }
}

private class BuildLuaJit: BaseBuild {
    init() {
        super.init(library: .LuaJIT)
    }

    override func build(platform: PlatformType, arch: ArchType) throws {
        if platform == .maccatalyst || (platform == .macos && arch == .arm64) {
            return
        }
        let buildURL = scratch(platform: platform, arch: arch)
        let thinDir = thinDir(platform: platform, arch: arch)
        try? FileManager.default.removeItem(at: buildURL)
        try? FileManager.default.removeItem(at: thinDir)
        try? FileManager.default.createDirectory(at: thinDir, withIntermediateDirectories: true, attributes: nil)
        try? _ = Utility.launch(path: "/usr/bin/make", arguments: ["clean"], currentDirectoryURL: directoryURL, environment: ["MACOSX_DEPLOYMENT_TARGET": "10.14"])
        // var environ = environment(platform: platform, arch: arch)
        var environ: [String: String] = [:]
        if platform == .macos {
            environ["MACOSX_DEPLOYMENT_TARGET"] = platform.minVersion
        }
        try Utility.launch(path: "/usr/bin/make", arguments: ["-j5", "-s"] + arguments(platform: platform, arch: arch), currentDirectoryURL: directoryURL, environment: environ)
        try Utility.launch(path: "/usr/bin/make", arguments: ["-j5", "install", "-s", "PREFIX=\(thinDir.path)"], currentDirectoryURL: directoryURL, environment: environ)
    }

    override func arguments(platform: PlatformType, arch: ArchType) -> [String] {
        let thinDir = thinDir(platform: platform, arch: arch)
        var argus = ["PREFIX=\(thinDir.path)"]
        let syslibroot = platform.isysroot()
        let clang = "/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/"
        let targetFlags = "-arch \(arch.rawValue) -isysroot \(syslibroot)"
        var targetSys = ""
        switch platform {
        case .ios, .isimulator, .tvos, .tvsimulator:
            targetSys = "iOS"
        default:
            break
        }
        if targetSys != "" {
            argus += [
                "DEFAULT_CC=clang",
                "CROSS=\(clang)",
                "TARGET_FLAGS=\(targetFlags)",
                "TARGET_SYS=\(targetSys)",
            ]
        }

        return argus
    }
}

private class BuildSmbclient: BaseBuild {
    init() {
        Utility.shell("brew list samba ||  brew install samba")
        // Utility.shell("brew list readline ||  brew install readline")
        super.init(library: .smbclient)
    }

    override func scratch(platform _: PlatformType, arch _: ArchType) -> URL {
        directoryURL
    }

    override func build(platform: PlatformType, arch: ArchType) throws {
        if platform != .macos {
            return
        }
        try super.build(platform: platform, arch: arch)
        /* let buildURL = scratch(platform: platform, arch: arch)
         try? FileManager.default.createDirectory(at: buildURL, withIntermediateDirectories: true, attributes: nil)
         let environ = environment(platform: platform, arch: arch)
         try Utility.launch(path: "/usr/bin/python3", arguments: ["./buildtools/bin/waf", "distclean"], currentDirectoryURL: directoryURL, environment: environ)
         try Utility.launch(path: "/usr/bin/python3", arguments: ["./buildtools/bin/waf", "configure"] + arguments(platform: platform, arch: arch), currentDirectoryURL: directoryURL, environment: environ)
         try Utility.launch(path: "/usr/bin/python3", arguments: ["./buildtools/bin/waf", "build"], currentDirectoryURL: directoryURL, environment: environ)
         try Utility.launch(path: "/usr/bin/python3", arguments: ["./buildtools/bin/waf", "install"], currentDirectoryURL: directoryURL, environment: environ) */
    }

    override func environment(platform: PlatformType, arch: ArchType) -> [String: String] {
        var environ = super.environment(platform: platform, arch: arch)
        environ["PATH"] = (directoryURL + "buildtools/bin").path + ":" + environ["PATH"]!
        environ["CPPFLAGS"] = environ["CPPFLAGS"]! + " -I/usr/local/opt/readline/include"
        environ["PKG_CONFIG_PATH"] = environ["PKG_CONFIG_PATH"]! + "/usr/local/opt/readline/lib/pkgconfig"
        environ["LDFLAGS"] = environ["LDFLAGS"]! + " -L/usr/local/opt/readline/lib  "
        environ["PYTHONHASHSEED"] = "1"
        return environ
    }

    override func arguments(platform: PlatformType, arch: ArchType) -> [String] {
        var argus = super.arguments(platform: platform, arch: arch) +
            [
                "--without-gpgme",
                "--bundled-libraries=NONE,talloc,ldb,tdb,tevent",
                "--disable-cephfs",
                "--disable-cups",
                "--disable-iprint",
                "--disable-glusterfs",
                "--disable-python",
                "--without-acl-support",
                "--without-ad-dc",
                "--without-ads",
                "--without-ldap",
                "--without-libarchive",
                "--without-json",
                "--without-pam",
                "--without-regedit",
                "--without-syslog",
                "--without-utmp",
                "--without-gettext",
                "--without-winbind",
                "--with-shared-modules=!vfs_snapper",
                // "--with-system-mitkrb5",
                // "--enable-static",
                // "--disable-shared",
                "--host=\(platform.host(arch: arch))",
                // "--with-sysroot=\(platform.isysroot())",
            ]
        if platform != .macos {
            argus.append("--cross-compile")
            if platform == .ios {
                argus.append("--cross-execute='/User/liumiuyong/simulator/iOS.17.0.simulator -L \(platform.isysroot())'")
            } else if platform == .tvos {
                argus.append("--cross-execute='/User/liumiuyong/simulator/tvOS.17.0.simulator -L \(platform.isysroot())'")
            }
        }
        return argus
    }
}

private class BuildGmp: BaseBuild {
    init() {
        super.init(library: .gmp)
    }

    override func arguments(platform: PlatformType, arch: ArchType) -> [String] {
        super.arguments(platform: platform, arch: arch) +
            [
                // "--disable-maintainer-mode",
                // "--disable-assembly",
                "--with-pic",
                "--enable-static",
                "--disable-shared",
                "--disable-fast-install",
                "--host=\(platform.host(arch: arch))",
                "--with-sysroot=\(platform.isysroot())",
            ]
    }
}

private class BuildLibbluray: BaseBuild {
    init() {
        super.init(library: .libbluray)
    }

    override func arguments(platform: PlatformType, arch: ArchType) -> [String] {
        var argus = super.arguments(platform: platform, arch: arch) +
            [
                "--enable-static",
                "--disable-shared",
                "--disable-fast-install",
                "--disable-bdjava-jar",
                "--disable-dependency-tracking",
                "--disable-silent-rules",
                "--host=\(platform.host(arch: arch))",
                "--with-sysroot=\(platform.isysroot())",
            ]
         if platform != .macos {
            //argus.append("--without-fontconfig")
         } 
         argus.append("--without-fontconfig")
         return argus  
    }

    override func configure(buildURL: URL, environ: [String: String], platform: PlatformType, arch: ArchType) throws {
        let path = directoryURL + "configure"
        try? FileManager.default.removeItem(at: path)
        let configure = directoryURL + "\(configureFileName())" 
        try Utility.launch(executableURL: directoryURL + "bootstrap", arguments: [], currentDirectoryURL: directoryURL, environment: environ)
        if platform != .macos && platform != .maccatalyst {
            if let data = FileManager.default.contents(atPath: path.path), var str = String(data: data, encoding: .utf8) {
                        str = str.replacingOccurrences(of:
                            """
                            -framework DiskArbitration
                            """, with:
                            """
                            """)
                            try str.write(toFile: path.path, atomically: true, encoding: .utf8)
                    }
        }
        try Utility.launch(executableURL: configure, arguments: arguments(platform: platform, arch: arch), currentDirectoryURL: buildURL, environment: environ)
    }

    override func build(platform: PlatformType, arch: ArchType) throws {
        if platform != .macos {
            var patch = "libbluray.patch"
            if platform == .tvos || platform == .tvsimulator {
                patch = "libbluray.tvos.patch"
            }
            let _ = try? Utility.launch(path: "/usr/bin/git", arguments: ["apply", "\(directoryURL.path)/../../Sources/MPVBuild/\(patch)"], currentDirectoryURL: directoryURL)
        }
        try super.build(platform: platform, arch: arch)
        if platform != .macos {
            let _ = try? Utility.launch(path: "/usr/bin/git", arguments: ["stash"], currentDirectoryURL: directoryURL)
        }
        

    }
}

private class BuildNettle: BaseBuild {
    init() {
        super.init(library: .nettle)
    }

    override func arguments(platform: PlatformType, arch: ArchType) -> [String] {
        super.arguments(platform: platform, arch: arch) +
            [
                // "--disable-mini-gmp",
                "--enable-mini-gmp",
                "--disable-assembler",
                "--disable-openssl",
                "--disable-gcov",
                "--disable-documentation",
                // "--with-pic",
                "--enable-static",
                "--disable-shared",
                // "--disable-fast-install",
                "--disable-dependency-tracking",
                "--host=\(platform.host(arch: arch))",
                // "--with-sysroot=\(platform.isysroot())",
            ]
    }
}

private class BuildGnutls: BaseBuild {
    init() {
        super.init(library: .gnutls)
    }

    override func arguments(platform: PlatformType, arch: ArchType) -> [String] {
        super.arguments(platform: platform, arch: arch) +
            [
                "--with-included-libtasn1",
                "--with-included-unistring",
                "--without-idn",
                "--without-p11-kit",
                "--with-nettle-mini",
                "--enable-hardware-acceleration",
                "--disable-openssl-compatibility",
                "--disable-code-coverage",
                "--disable-doc",
                "--disable-manpages",
                "--without-brotli",
                // "--disable-guile",
                "--disable-tests",
                "--disable-tools",
                "-disable-rpath",
                "--disable-maintainer-mode",
                "--disable-full-test-suite",
                "--with-pic",
                "--enable-static",
                "--disable-shared",
                "--disable-fast-install",
                "--disable-dependency-tracking",
                "--host=\(platform.host(arch: arch))",
                "--with-sysroot=\(platform.isysroot())",
            ]
    }

    override func configure(buildURL: URL, environ: [String: String], platform: PlatformType, arch: ArchType) throws {
        let bootstrap = directoryURL + "bootstrap"
        try Utility.launch(executableURL: bootstrap, arguments: [], currentDirectoryURL: directoryURL, environment: environ)
        try super.configure(buildURL: buildURL, environ: environ, platform: platform, arch: arch)
    }
}

private class BuildSRT: BaseBuild {
    init() {
        super.init(library: .srt)
    }

    override func buildALL() throws {
        Utility.shell("brew list cmake || brew install cmake")
        try super.buildALL()
    }

    override func configure(buildURL: URL, environ: [String: String], platform: PlatformType, arch: ArchType) throws {
        let thinDirPath = thinDir(platform: platform, arch: arch).path

        let arguments = [
            (directoryURL + "CMakeLists.txt").path,
            "-Wno-dev",
            "-DUSE_ENCLIB=openssl",
            "-DCMAKE_VERBOSE_MAKEFILE=0",
            "-DCMAKE_BUILD_TYPE=Release",
            "-DCMAKE_PREFIX_PATH=\(thinDirPath)",
            "-DCMAKE_INSTALL_PREFIX=\(thinDirPath)",
            "-DENABLE_STDCXX_SYNC=1",
            "-DENABLE_CXX11=1",
            "-DUSE_OPENSSL_PC=1",
            "-DENABLE_DEBUG=0",
            "-DENABLE_LOGGING=0",
            "-DENABLE_HEAVY_LOGGING=0",
            "-DENABLE_APPS=0",
            "-DENABLE_SHARED=0",
            platform == .maccatalyst ? "-DENABLE_MONOTONIC_CLOCK=0" : "-DENABLE_MONOTONIC_CLOCK=1",
        ]
        try Utility.launch(path: "/usr/local/bin/cmake", arguments: arguments, currentDirectoryURL: buildURL, environment: environ)
    }
}

private class BuildFribidi: BaseBuild {
    init() {
        super.init(library: .fribidi)
    }

    override func configure(buildURL: URL, environ: [String: String], platform: PlatformType, arch: ArchType) throws {
        try super.configure(buildURL: buildURL, environ: environ, platform: platform, arch: arch)
        let makefile = buildURL + "Makefile"
        // DISABLE BUILDING OF doc FOLDER (doc depends on c2man which is not available on all platforms)
        if let data = FileManager.default.contents(atPath: makefile.path), var str = String(data: data, encoding: .utf8) {
            str = str.replacingOccurrences(of: " doc ", with: " ")
            try? str.write(toFile: makefile.path, atomically: true, encoding: .utf8)
        }
    }

    override func arguments(platform: PlatformType, arch: ArchType) -> [String] {
        super.arguments(platform: platform, arch: arch) +
            [
                "--disable-deprecated",
                "--disable-debug",
                "--with-pic",
                "--enable-static",
                "--disable-shared",
                "--disable-fast-install",
                "--disable-dependency-tracking",
                "--host=\(platform.host(arch: arch))",
                "--with-sysroot=\(platform.isysroot())",
            ]
    }
}

private class BuildHarfbuzz: BaseBuild {
    init() {
        super.init(library: .harfbuzz)
    }

    override func arguments(platform: PlatformType, arch: ArchType) -> [String] {
        super.arguments(platform: platform, arch: arch) +
            [
                "--with-glib=no",
                "--with-freetype=no",
                "--with-directwrite=no",
                "--with-pic",
                "--enable-static",
                "--disable-shared",
                "--disable-fast-install",
                "--disable-dependency-tracking",
                "--host=\(platform.host(arch: arch))",
                "--with-sysroot=\(platform.isysroot())",
            ]
    }
}

private class BuildFreetype: BaseBuild {
    init() {
        super.init(library: .freetype)
    }

    override func arguments(platform: PlatformType, arch: ArchType) -> [String] {
        super.arguments(platform: platform, arch: arch) +
            [
                "--with-zlib",
                "--without-harfbuzz",
                "--without-bzip2",
                // "--without-fsref",
                "--without-quickdraw-toolbox",
                "--without-quickdraw-carbon",
                // "--without-ats",
                "--disable-mmap",
                "--with-png=no",
                "--with-brotli=no",
                "--with-pic",
                "--enable-static",
                "--disable-shared",
                "--disable-fast-install",
                "--host=\(platform.host(arch: arch))",
                "--with-sysroot=\(platform.isysroot())",
            ]
    }
}

private class BuildBrotli: BaseBuild {
    init() {
        super.init(library: .brotli)
    }

    override func buildALL() throws {
        Utility.shell("brew list cmake || brew install cmake")
        try super.buildALL()
    }

    override func build(platform: PlatformType, arch: ArchType) throws {
        let buildURL = scratch(platform: platform, arch: arch)
        let thinDir = thinDir(platform: platform, arch: arch)
        try? FileManager.default.removeItem(at: buildURL)
        try? FileManager.default.removeItem(at: thinDir)
        try? FileManager.default.createDirectory(at: buildURL, withIntermediateDirectories: true, attributes: nil)
        let environ = environment(platform: platform, arch: arch)
        try configure(buildURL: buildURL, environ: environ, platform: platform, arch: arch)
        try Utility.launch(path: "/usr/local/bin/cmake", arguments: ["--build", ".", "--config", "Release", "--target", "install"], currentDirectoryURL: buildURL, environment: environ)
    }

    override func configure(buildURL: URL, environ: [String: String], platform: PlatformType, arch: ArchType) throws {
        let thinDirPath = thinDir(platform: platform, arch: arch).path

        let arguments = [
            "-Wno-dev",
            "-DUSE_ENCLIB=openssl",
            "-DCMAKE_VERBOSE_MAKEFILE=0",
            "-DCMAKE_BUILD_TYPE=Release",
            "-DCMAKE_PREFIX_PATH=\(thinDirPath)",
            "-DCMAKE_INSTALL_PREFIX=\(thinDirPath)",
            "-DENABLE_STDCXX_SYNC=1",
            "-DENABLE_CXX11=1",
            "-DUSE_OPENSSL_PC=1",
            "-DENABLE_DEBUG=0",
            "-DENABLE_LOGGING=0",
            "-DENABLE_HEAVY_LOGGING=0",
            "-DENABLE_APPS=0",
            "-DENABLE_SHARED=0",
            platform == .maccatalyst ? "-DENABLE_MONOTONIC_CLOCK=0" : "-DENABLE_MONOTONIC_CLOCK=1",
            directoryURL.path,
        ]
        try Utility.launch(path: "/usr/local/bin/cmake", arguments: arguments, currentDirectoryURL: buildURL, environment: environ)
    }
}

private class BuildPng: BaseBuild {
    init() {
        super.init(library: .libpng)
    }

    override func arguments(platform: PlatformType, arch: ArchType) -> [String] {
        let asmOptions = arch == .x86_64 ? "--enable-intel-sse=yes" : "--enable-arm-neon=yes"
        return super.arguments(platform: platform, arch: arch) +
            [
                asmOptions,
                "--disable-unversioned-libpng-pc",
                "--disable-unversioned-libpng-config",
                "--with-pic",
                "--enable-static",
                "--disable-shared",
                "--disable-fast-install",
                "--host=\(platform.host(arch: arch))",
                "--with-sysroot=\(platform.isysroot())",
            ]
    }
}

private class BuildASS: BaseBuild {
    init() {
        super.init(library: .libass)
    }

    override func arguments(platform: PlatformType, arch: ArchType) -> [String] {
        return super.arguments(platform: platform, arch: arch) +
            [
                "--disable-libtool-lock",
                "--disable-test",
                "--disable-profile",
                "--disable-fontconfig",
                "--disable-asm",
                // platform == .maccatalyst || arch == .x86_64 ? "--disable-asm" : "--enable-asm",
                "--with-pic",
                // "--enable-directwrite",
                "--disable-libunibreak",
                "--enable-static",
                "--disable-shared",
                "--disable-fast-install",
                "--disable-dependency-tracking",
                "--host=\(platform.host(arch: arch))",
                "--with-sysroot=\(platform.isysroot())",
            ]
    }
}

private class BuildUchardet: BaseBuild {
    init() {
        super.init(library: .uchardet)
    }

    override func configure(buildURL: URL, environ: [String: String], platform: PlatformType, arch: ArchType) throws {
        let thinDirPath = thinDir(platform: platform, arch: arch).path

        let arguments = [
            (directoryURL + "CMakeLists.txt").path,
            "-Wno-dev",
            "-Ddefault_library=static",
            "-DCMAKE_VERBOSE_MAKEFILE=0",
            "-DBUILD_SHARED_LIBS=false",
            "-DCMAKE_BUILD_TYPE=Release",
            "-DCMAKE_PREFIX_PATH=\(thinDirPath)",
            "-DCMAKE_INSTALL_PREFIX=\(thinDirPath)",
            "-DCMAKE_OSX_SYSROOT=\(platform.isysroot())",
            "-DENABLE_STDCXX_SYNC=1",
            "-DENABLE_CXX11=1",
            "-DENABLE_DEBUG=0",
            "-DENABLE_LOGGING=0",
            "-DENABLE_HEAVY_LOGGING=0",
            "-DENABLE_APPS=0",
            "-DENABLE_SHARED=0",
            platform == .maccatalyst ? "-DENABLE_MONOTONIC_CLOCK=0" : "-DENABLE_MONOTONIC_CLOCK=1",
        ]
        try Utility.launch(path: "/usr/local/bin/cmake", arguments: arguments, currentDirectoryURL: buildURL, environment: environ)
    }
}

private class BuildShaderc: BaseBuild {
    init() {
        super.init(library: .shaderc)
    }

    override func buildALL() throws {
        Utility.shell("\(directoryURL.path)/utils/git-sync-deps")
        let _ = try? Utility.launch(path: "/usr/bin/git", arguments: ["apply", "\(directoryURL.path)/../../Sources/MPVBuild/spirv-tools.patch"], currentDirectoryURL: directoryURL + "third_party/spirv-tools")
        try super.buildALL()
    }

    override func build(platform: PlatformType, arch: ArchType) throws {
        let buildURL = scratch(platform: platform, arch: arch)
        let thinDir = thinDir(platform: platform, arch: arch)
        try? FileManager.default.removeItem(at: buildURL)
        try? FileManager.default.removeItem(at: thinDir)
        do {
            let thinDirPath = thinDir.path
            try? FileManager.default.createDirectory(at: buildURL, withIntermediateDirectories: true, attributes: nil)
            let environ = environment(platform: platform, arch: arch)
            try configure(buildURL: buildURL, environ: environ, platform: platform, arch: arch)
            try Utility.launch(path: "/usr/local/bin/ninja", arguments: [], currentDirectoryURL: buildURL, environment: environ)
            try Utility.launch(path: "/usr/local/bin/ninja", arguments: ["install"], currentDirectoryURL: buildURL, environment: environ)
            Utility.shell("mv \(thinDirPath)/lib/pkgconfig/shaderc.pc \(thinDirPath)/lib/pkgconfig/shaderc_shared.pc")
            Utility.shell("mv \(thinDirPath)/lib/pkgconfig/shaderc_combined.pc \(thinDirPath)/lib/pkgconfig/shaderc.pc")
        } catch {
            throw MyError.buildError("build shaderc error: \(error)")
        }
    }

    override func configure(buildURL: URL, environ: [String: String], platform: PlatformType, arch: ArchType) throws {
        let thinDirPath = thinDir(platform: platform, arch: arch).path

        let arguments = [
            "-Wno-dev",
            "-GNinja",
            "-DBUILD_SHARED_LIBS=false",
            "-DCMAKE_BUILD_TYPE=Release",
            "-DCMAKE_PREFIX_PATH=\(thinDirPath)",
            "-DCMAKE_INSTALL_PREFIX=\(thinDirPath)",
            "-DCMAKE_OSX_SYSROOT=\(platform.isysroot())",
            directoryURL.path,
        ]
        try Utility.launch(path: "/usr/local/bin/cmake", arguments: arguments, currentDirectoryURL: buildURL, environment: environ)
    }
}

private class BuildLittleCms: BaseBuild {
    init() {
        super.init(library: .littlecms)
    }

    override func build(platform: PlatformType, arch: ArchType) throws {
        try super.build(platform: platform, arch: arch)
    }
}

private class BuildLibPlacebo: BaseBuild {
    init() {
        super.init(library: .libplacebo)
    }

    override func build(platform: PlatformType, arch: ArchType) throws {
        try super.build(platform: platform, arch: arch)
    }

    override func arguments(platform: PlatformType, arch: ArchType) -> [String] {
        var argus =
            [
                "-Dtests=false",
                "-Ddemos=false",
                // "-Dlcms=disabled",
                // "-Dshaderc=disabled",
                // "-Dvulkan=disabled"
            ]
        if platform != .macos {
            // argus.append("-Dshaderc=disabled")
            // argus.append("-Dlcms=disabled")
            // argus.append("-Dvulkan=disabled")
        }
        return argus
    }
}

private class BuildMoltenVK: BaseBuild {
    init() {
        super.init(library: .MoltenVK)
    }

    override func buildALL() throws {
        try Utility.launch(path: (directoryURL + "fetchDependencies").path, arguments: ["--all"], currentDirectoryURL: directoryURL)
        try Utility.launch(path: "/usr/bin/make", arguments: [], currentDirectoryURL: directoryURL)
        try? FileManager.default.copyItem(at: directoryURL + "Package/Release/MoltenVK/MoltenVK.xcframework", to: URL.currentDirectory + "../Framework/MoltenVK.xcframework")
    }
}

private class BuildDav1d: BaseBuild {
    init() {
        super.init(library: .libdav1d)
    }

    override func build(platform: PlatformType, arch: ArchType) throws {
        try super.build(platform: platform, arch: arch)
    }

    override func arguments(platform: PlatformType, arch: ArchType) -> [String] {
        return ["-Denable_asm=true", "-Denable_tools=false", "-Denable_examples=false", "-Denable_tests=false", "--default-library=static"]
    }
}

private class BuildMPV: BaseBuild {
    var isDisableStaticLinkMoltenVkOnMac: Bool = true
    init(disableStaticLinkMoltenVkOnMac: Bool) {
        isDisableStaticLinkMoltenVkOnMac = disableStaticLinkMoltenVkOnMac
        super.init(library: .mpv)
    }

    override func getVulkanPkgconfig(buildURL: URL, platform: PlatformType, arch: ArchType) -> String {
        // if platform == .macos && !isDisableStaticLinkMoltenVkOnMac {
        if platform == .macos && isDisableStaticLinkMoltenVkOnMac {
            return ""
        }
        return super.getVulkanPkgconfig(buildURL: buildURL, platform: platform, arch: arch)
    }

    override func build(platform: PlatformType, arch: ArchType) throws {
        if platform == .maccatalyst {
            return
        }
        try super.build(platform: platform, arch: arch)
    }

    override func buildALL() throws {
        let _ = try? Utility.launch(path: "/usr/bin/git", arguments: ["apply", "\(directoryURL.path)/../../Sources/MPVBuild/mpv.patch"], currentDirectoryURL: directoryURL)
        try super.buildALL()

        // copy headers
        /*let includeSourceDirectory = URL.currentDirectory + ["../Framework", "Libmpv.xcframework", "tvos-arm64", "Headers", "mpv"]
        let includeDestDirectory = URL.currentDirectory + ["../Sources", "LibMPV", "include"]
        print("Copy libmpv headers to path: \(includeDestDirectory.path)")
        try? FileManager.default.removeItem(at: includeDestDirectory)
        try? FileManager.default.copyItem(at: includeSourceDirectory, to: includeDestDirectory)*/
    }

    override func arguments(platform: PlatformType, arch: ArchType) -> [String] {
        var arguments =
            [
                /*
                 "--verbose",
                 "--disable-cplayer",
                 "--disable-lcms2",
                 "--disable-lua",
                 "--disable-rubberband",
                 "--disable-zimg",
                 "--disable-javascript",
                 "--disable-jpeg",
                 "--disable-swift",
                 "--disable-vapoursynth",
                 "--enable-uchardet",
                 "--enable-lgpl",
                 "--enable-libmpv-static",
                 platform == .macos ? "--enable-videotoolbox-gl" : (platform == .maccatalyst ? "--enable-gl" : "--enable-ios-gl"),
                 platform == .macos ? "-Dvideotoolbox-gl=enabled" : (platform == .maccatalyst ? "-Dgl=enabled" : "-Dios-gl=enabled"),
                  */
                // "-Dprefer_static=true",
                // "-Dvideotoolbox-gl=disabled",
                "-Dlibmpv=true",
                "-Dswift-build=disabled",
            ]
        if platform == .maccatalyst || (platform == .macos && arch == .arm64) {
            arguments.append("-Dlua=disabled")
        } else {
            arguments.append("-Dlua=luajit")
        }
        arguments.append("-Drubberband=disabled")
        arguments.append("-Djavascript=disabled")
        arguments.append("-Dzimg=disabled")
        arguments.append("-Djpeg=disabled")
        // arguments.append("-Dshaderc=disabled")
        arguments.append("-Dspirv-cross=disabled")
        // arguments.append("-Dvulkan=disabled")
        if platform != .macos {
            arguments.append("-Dvideotoolbox-gl=disabled")
            arguments.append("-Dios-gl=enabled")
        }
        return arguments
    }
}

private enum PlatformType: String, CaseIterable {
    case macos, ios, isimulator, tvos, tvsimulator, maccatalyst
    var minVersion: String {
        switch self {
        case .ios, .isimulator:
            return "13.0"
        case .tvos, .tvsimulator:
            return "13.0"
        case .macos:
            return "10.15"
        case .maccatalyst:
            return "13.0"
        }
    }

    var mesonSubSystem: String {
        switch self {
        case .isimulator:
            return "ios-simulator"
        case .tvsimulator:
            return "tvos-simulator"
        default:
            return self.rawValue
        }
    }

    func architectures() -> [ArchType] {
        switch self {
        case .ios:
            return [.arm64]
        case .tvos:
            return [.arm64]
        case .isimulator, .tvsimulator:
            return [.arm64, .x86_64]
        case .macos:
            #if arch(x86_64)
                return [.x86_64, .arm64]
            #else
                return [.arm64, .x86_64]
            #endif
        case .maccatalyst:
            return [.arm64, .x86_64]
        }
    }

    func deploymentTarget(_ arch: ArchType) -> String {
        switch self {
        case .ios:
            return "-mios-version-min=\(minVersion)"
        case .isimulator:
            return "-mios-simulator-version-min=\(minVersion)"
        case .tvos:
            return "-mtvos-version-min=\(minVersion)"
        case .tvsimulator:
            return "-mtvos-simulator-version-min=\(minVersion)"
        case .macos:
            return "-mmacosx-version-min=\(minVersion)"
        case .maccatalyst:
            return arch == .x86_64 ? "-target x86_64-apple-ios-macabi" : "-target arm64-apple-ios-macabi"
        }
    }

    func sdk() -> String {
        switch self {
        case .ios:
            return "iPhoneOS"
        case .isimulator:
            return "iPhoneSimulator"
        case .tvos:
            return "AppleTVOS"
        case .tvsimulator:
            return "AppleTVSimulator"
        case .macos:
            return "MacOSX"
        case .maccatalyst:
            return "MacOSX"
        }
    }

    func isysroot() -> String {
        try! Utility.launch(path: "/usr/bin/xcrun", arguments: ["--sdk", sdk().lowercased(), "--show-sdk-path"], isOutput: true)
    }

    /* func isysroot() -> String {
         xcrunFind(tool: "--show-sdk-path")
     } */

    func xcrunFind(tool: String) -> String {
        try! Utility.launch(path: "/usr/bin/xcrun", arguments: ["--sdk", sdk().lowercased(), "--find", tool], isOutput: true)
    }

    func host(arch: ArchType) -> String {
        switch self {
        case .ios, .isimulator, .maccatalyst:
            return "\(arch == .x86_64 ? "x86_64" : "arm64")-ios-darwin"
        case .tvos, .tvsimulator:
            return "\(arch == .x86_64 ? "x86_64" : "arm64")-tvos-darwin"
        case .macos:
            return "\(arch == .x86_64 ? "x86_64" : "arm64")-apple-darwin"
        }
    }
}

enum ArchType: String, CaseIterable {
    // swiftlint:disable identifier_name
    case arm64, x86_64, arm64e
    // swiftlint:enable identifier_name
    func executable() -> Bool {
        guard let architecture = Bundle.main.executableArchitectures?.first?.intValue else {
            return false
        }
        // NSBundleExecutableArchitectureARM64
        if architecture == 0x0100_000C, self == .arm64 {
            return true
        } else if architecture == NSBundleExecutableArchitectureX86_64, self == .x86_64 {
            return true
        }
        return false
    }

    func arch() -> String {
        switch self {
        case .arm64, .arm64e:
            return "aarch64"
        case .x86_64:
            return "x86_64"
        }
    }

    // TODO: remove
    func cpu() -> String {
        switch self {
        case .arm64:
            return "--cpu=armv8"
        case .x86_64:
            return "--cpu=x86-64"
        case .arm64e:
            return "--cpu=armv8.3-a"
        }
    }

    func cpuFamily() -> String {
        switch self {
        case .arm64, .arm64e:
            return "aarch64"
        case .x86_64:
            return "x86_64"
        }
    }

    func targetCpu() -> String {
        switch self {
        case .arm64, .arm64e:
            return "arm64"
        case .x86_64:
            return "x86_64"
        }
    }
}

enum Utility {
    @discardableResult
    static func shell(_ command: String, isOutput _: Bool = false, currentDirectoryURL: URL? = nil, environment: [String: String] = [:]) -> String? {
        do {
            return try launch(executableURL: URL(fileURLWithPath: "/bin/zsh"), arguments: ["-c", command], currentDirectoryURL: currentDirectoryURL, environment: environment)
        } catch {
            print(error.localizedDescription)
            return nil
        }
    }

    @discardableResult
    static func launch(path: String, arguments: [String], isOutput: Bool = false, currentDirectoryURL: URL? = nil, environment: [String: String] = [:]) throws -> String {
        try launch(executableURL: URL(fileURLWithPath: path), arguments: arguments, isOutput: isOutput, currentDirectoryURL: currentDirectoryURL, environment: environment)
    }

    @discardableResult
    static func launch(executableURL: URL, arguments: [String], isOutput: Bool = false, currentDirectoryURL: URL? = nil, environment: [String: String] = [:]) throws -> String {
        #if os(macOS)
            let task = Process()
            task.environment = environment
            var standardOutput: FileHandle?
            var logURL: URL?
            if isOutput {
                let pipe = Pipe()
                task.standardOutput = pipe
                standardOutput = pipe.fileHandleForReading
            } else if let curURL = currentDirectoryURL {
                logURL = curURL.appendingPathExtension("log")
                if !FileManager.default.fileExists(atPath: logURL!.path) {
                    FileManager.default.createFile(atPath: logURL!.path, contents: nil)
                }
                let standardOutput = try FileHandle(forWritingTo: logURL!)
                if #available(macOS 10.15.4, *) {
                    try standardOutput.seekToEnd()
                }
                task.standardOutput = standardOutput
            }
            task.arguments = arguments
            var log = executableURL.path + " " + arguments.joined(separator: " ") + " environment: " + environment.description
            if let currentDirectoryURL {
                log += " url: \(currentDirectoryURL)"
            }
            print(log)
            task.currentDirectoryURL = currentDirectoryURL
            task.executableURL = executableURL
            try task.run()
            task.waitUntilExit()
            if task.terminationStatus == 0 {
                if isOutput, let standardOutput {
                    let data = standardOutput.readDataToEndOfFile()
                    let result = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .newlines) ?? ""
                    print(result)
                    return result
                } else {
                    return ""
                }
            } else {
                if let logURL = logURL {
                    print("please view log file for detail: \(logURL)\n")
                }
                throw NSError(domain: "fail", code: Int(task.terminationStatus))
            }
        #else
            return ""
        #endif
    }
}

extension URL {
    static var currentDirectory: URL {
        URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    }

    static func + (left: URL, right: String) -> URL {
        var url = left
        url.appendPathComponent(right)
        return url
    }

    static func + (left: URL, right: [String]) -> URL {
        var url = left
        right.forEach {
            url.appendPathComponent($0)
        }
        return url
    }
}

extension StringProtocol {
    var firstUppercased: String { prefix(1).uppercased() + dropFirst() }
    var firstLowercased: String { prefix(1).lowercased() + dropFirst() }
    var firstCapitalized: String { prefix(1).capitalized + dropFirst() }
}

enum MyError: Error {
    case buildError(String)
}
