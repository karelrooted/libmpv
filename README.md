# Libmpv

[![ffmpeg](https://img.shields.io/badge/ffmpeg-n6.1-blue.svg)](https://github.com/FFmpeg/FFmpeg)
[![mpv](https://img.shields.io/badge/mpv-v0.37.0-blue.svg)](https://github.com/mpv-player/mpv)

script to build libmpv for macOS, iOS, iPadOS and tvOS

## Requirements

- iOS 17.0+ / macOS 15.0+ / tvOS 17.0+
- Xcode 15.0+

## Usage

### Apple
You can use libmpv with : [MPVKit](https://github.com/karelrooted/MPVKit.git) (swift binding of libmpv)

## Build

```bash
git clone https://github.com/karelrooted/libmpv.git --recurse-submodules --shallow-submodules
cd libmpv && swift run MPVBuild
```

## Todo
* Use shell script to build libmpv instead of swift.

## Credits

- [ffmpeg](https://ffmpeg.org)
- [mpv](https://mpv.io)
- [kingslay/ffmpegkit](https://github.com/kingslay/ffmpegkit)
- [cxfksword/MPVKit](https://github.com/cxfksword/MPVKit)
- [xbmc/xbmc](https://github.com/xbmc/xbmc)

## License
libmpv is under the [LGPL 3.0](https://www.gnu.org/licenses/lgpl-3.0.en.html) license. Check [mpv](https://mpv.io) and [ffmpeg](https://ffmpeg.org) for more license requirement.
Please note samba is under GPL v3 license, so if you enable smbclient, this library's license became GPL v3 too
