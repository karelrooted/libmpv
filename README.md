# Libmpv

[![ffmpeg](https://img.shields.io/badge/ffmpeg-n6.1-blue.svg)](https://github.com/FFmpeg/FFmpeg)
[![mpv](https://img.shields.io/badge/mpv-v0.37.0-blue.svg)](https://github.com/mpv-player/mpv)

script to build libmpv for macOS, iOS, iPadOS and tvOS

## Requirements

- iOS 17.0+ / macOS 14.0+ / tvOS 17.0+
- Xcode 15.0+

## Usage

### Apple
You can use libmpv with [MPVKit](https://github.com/karelrooted/MPVKit.git) (swift binding of libmpv)

## Build

```bash
git clone https://github.com/karelrooted/libmpv.git --recurse-submodules --shallow-submodules
cd libmpv && sh ./build.sh && sh ./xcframework.sh
```

### build help

```bash
usage: build.sh [-h]
options:
p     : Optional, platforms(macOS iOS tvOS iSimulator tvSimulator). Default: all
a     : Optional, archs(x86_64 arm64). Default: all, please note iOS and tvOS will ignore this and always be arm64
l     : Optional, libraries(openssl libpng freetype fribidi harfbuzz libass readline gmp nettle gnutls smbclient moltenvk shaderc littlecms libplacebo libdav1d libbluray ffmpeg uchardet luajit mpv).
o     : Optional, optimize level, default: 2 when debug is false, 0 when debug is true
g     : Optional, enable gpl, default: false
d     : Optional, enable debug, default: false
h     : Optional, Print this Help.
```

### debug example

build ios smbclient
```bash
./build.sh -p ios -l "readline gmp nettle gnutls smbclient"
```

## Credits

- [ffmpeg](https://ffmpeg.org)
- [mpv](https://mpv.io)
- [qoli/mpv-ios-scripts](https://github.com/qoli/mpv-ios-scripts)
- [kingslay/ffmpegkit](https://github.com/kingslay/ffmpegkit)
- [cxfksword/MPVKit](https://github.com/cxfksword/MPVKit)
- [xbmc/xbmc](https://github.com/xbmc/xbmc)

## License
libmpv is under the [LGPL 3.0](https://www.gnu.org/licenses/lgpl-3.0.en.html) license. Check [mpv](https://mpv.io) and [ffmpeg](https://ffmpeg.org) for more license requirement.
Please note samba is under GPL v3 license, so if you enable smbclient, this library's license became GPL v3 too
