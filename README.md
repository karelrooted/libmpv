# Libmpv

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

## License
libmpv is under the [LGPL 3.0](https://www.gnu.org/licenses/lgpl-3.0.en.html) license. See [mpv](https://mpv.io) and [ffmpeg](https://ffmpeg.org) for more license requirement
