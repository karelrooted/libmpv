#!/bin/sh -e

Help()
{
   # Display Help
   echo "compile libmpv."
   echo "usage: build.sh [-h]"
   echo "options:"
   echo "p     : Optional, platforms(macOS iOS tvOS iSimulator tvSimulator). Default: all"
   echo "a     : Optional, archs(x86_64 arm64). Default: all, please note iOS and tvOS will ignore this and always be arm64"
   echo "l     : Optional, libraries(openssl libpng freetype fribidi harfbuzz libass readline gmp nettle gnutls smbclient moltenvk shaderc littlecms libplacebo libdav1d libbluray ffmpeg uchardet luajit mpv)."
   echo "d     : Optional, enable debug, default: false"
   echo "h     : Optional, Print this Help."
   echo
}

PKG_DEFAULT_PATH=$(pkg-config --variable pc_path pkg-config)
export ROOT="$(pwd)"
export SRC="$ROOT/Vendor"
export PKG_CONFIG_LIBDIR
export LDFLAGS
export CFLAGS
export CXXFLAGS
export CPPFLAGS
export COMMON_OPTIONS
export ENVIRONMENT
export ARCH
export PLATFORM
export CMAKE_OSX_ARCHITECTURES
export SDKPATH
export BUILDDIR
export LC_CTYPE="C"
#export LC_ALL="C"
export CC="/usr/bin/clang "
#export PATH="/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/:/usr/local/opt/gnu-sed/libexec/gnubin:/opt/homebrew/bin:$PATH"
export PATH="/usr/local/opt/gnu-sed/libexec/gnubin:/opt/homebrew/bin:$PATH"
export SCRATCH
export ARCH
export DEBUG_SWITCH

# add maccatalyst
PLATFORMS="macos ios tvos isimulator tvsimulator"
LIBRARIES="openssl libpng freetype fribidi harfbuzz libass moltenvk shaderc littlecms libplacebo libdav1d libbluray ffmpeg uchardet luajit mpv"
#LIBRARIES="openssl libpng freetype fribidi harfbuzz libass readline gmp nettle gnutls smbclient shaderc littlecms libplacebo libdav1d libbluray ffmpeg uchardet luajit mpv"
#LIBRARIES="openssl libpng freetype fribidi harfbuzz libass shaderc littlecms libplacebo libdav1d libbluray ffmpeg uchardet luajit mpv"
#LIBRARIES="openssl srt libpng freetype brotli fribidi harfbuzz libass readline gmp nettle gnutls smbclient shaderc littlecms libdovi libplacebo libdav1d libbluray ffmpeg uchardet luajit mpv"
#LIBRARIES="readline gmp nettle gnutls smbclient"

while getopts ":hp:a:l:d" OPTION; do
    case $OPTION in
    h)
        Help
        exit
        ;;
    p)
        PLATFORMS=$(echo "$OPTARG" | awk '{print tolower($0)}')
        ;;
    a)
        ARCHS=$(echo "$OPTARG" | awk '{print tolower($0)}')
        ;;
    l)
        LIBRARIES=$(echo "$OPTARG" | awk '{print tolower($0)}')
        ;;
    d)
        DEBUG_SWITCH=true
        ;;
    ?)
        echo "Invalid option"
        exit 1
        ;;
    esac
done

set -x
if [[ ! -z $DEBUG_SWITCH ]]; then
    debug_flag="-g"
    buile_type="debug"
else 
    buile_type="release"
fi

which -s brew
if [[ $? != 0 ]]; then
    # Install Homebrew
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
fi
brew list pkg-config || brew install pkg-config
brew list automake || brew install automake
brew list meson || brew install meson
brew list cmake || brew install cmake
brew list nasm || brew install nasm
brew list sdl2 || brew install sdl2
brew list gnu-sed || brew install gnu-sed

if [[ $LIBRARIES == *"moltenvk"* ]]; then
    ./scripts/moltenvk-build
fi
for PLATFORM in $PLATFORMS; do
    #rm -rf build/scratch-$PLATFORM
    if [[ "$PLATFORM" = "macos" ]]; then
        MIN_VERSION="10.15"
        if [[ -z $ARCHS ]]; then
            ARCHS="x86_64 arm64"
        fi 
        SDK_VERSION=$(xcrun -sdk macosx --show-sdk-version)
        PLATFORM_NAME="MacOS"
        SDKPATH="$(xcrun -sdk macosx --show-sdk-path)"
        DEPLOYMENT_TARGET="-mmacosx-version-min=$MIN_VERSION"
        #DEPLOYMENT_TARGET_LDFLAG="-Wl,-macosx-version-min,$MIN_VERSION"
        DEPLOYMENT_TARGET_LDFLAG=""
    elif [[ "$PLATFORM" = "ios" ]]; then
        MIN_VERSION="13.0"
        ARCHS="arm64"
        SDK_VERSION=$(xcrun -sdk iphoneos --show-sdk-version)
        PLATFORM_NAME="iPhoneOS"
        SDKPATH="$(xcrun -sdk iphoneos --show-sdk-path)"
        DEPLOYMENT_TARGET="-mios-version-min=$MIN_VERSION"
        #DEPLOYMENT_TARGET_LDFLAG="-Wl,-ios_version_min,$MIN_VERSION"
    elif [[ "$PLATFORM" = "tvos" ]]; then
        MIN_VERSION="13.0"
        ARCHS="arm64"
        SDK_VERSION=$(xcrun -sdk appletvos --show-sdk-version)
        PLATFORM_NAME="AppleTVOS"
        SDKPATH="$(xcrun -sdk appletvos --show-sdk-path)"
        DEPLOYMENT_TARGET="-mtvos-version-min=$MIN_VERSION"
        CFLAG_HAVE_FORK=" -DHAVE_FORK=0 "
    #DEPLOYMENT_TARGET_LDFLAG="-Wl,-tvos_version_min,$MIN_VERSION"
    elif [[ "$PLATFORM" = "isimulator" ]]; then
        MIN_VERSION="13.0"
        if [[ -z $ARCHS ]]; then
            ARCHS="x86_64 arm64"
        fi
        SDK_VERSION=$(xcrun -sdk iphonesimulator --show-sdk-version)
        PLATFORM_NAME="iPhoneSimulator"
        SDKPATH="$(xcrun -sdk iphonesimulator --show-sdk-path)"
        DEPLOYMENT_TARGET="-mios-simulator-version-min=$MIN_VERSION"
        #DEPLOYMENT_TARGET_LDFLAG="-Wl,-ios_simulator_version_min,$MIN_VERSION"
    elif [[ "$PLATFORM" = "tvsimulator" ]]; then
        MIN_VERSION="13.0"
        if [[ -z $ARCHS ]]; then
            ARCHS="x86_64 arm64"
        fi
        SDK_VERSION=$(xcrun -sdk appletvsimulator --show-sdk-version)
        PLATFORM_NAME="AppleTVSimulator"
        SDKPATH="$(xcrun -sdk appletvsimulator --show-sdk-path)"
        DEPLOYMENT_TARGET="-mtvos-simulator-version-min=$MIN_VERSION"
        CFLAG_HAVE_FORK=" -DHAVE_FORK=0 "
        #DEPLOYMENT_TARGET_LDFLAG="-Wl,-tvos_simulator_version_min,$MIN_VERSION"
    elif [[ "$PLATFORM" = "maccatalyst" ]]; then
        MIN_VERSION="13.0"
        if [[ -z $ARCHS ]]; then
            ARCHS="x86_64 arm64"
        fi
        SDK_VERSION=$(xcrun -sdk macosx --show-sdk-version)
        PLATFORM_NAME="AppleTVSimulator"
        SDKPATH="$(xcrun -sdk macosx --show-sdk-path)"
        DEPLOYMENT_TARGET="-target x86_64-apple-ios-macabi"
        DEPLOYMENT_TARGET_LDFLAG=""
    else
        echo "illegal platform option"
        exit 1
    fi

    SCRIPTS="$ROOT/scripts"
    SCRATCH="$ROOT/build/scratch-$PLATFORM"

    for ARCH in $ARCHS; do
        echo "PLATFORM: $PLATFORM ARCH: $ARCH"
        export HOSTFLAG="$ARCH-$PLATFORM-darwin"
        if [[ $PLATFORM = "macos" ]]; then
            HOSTFLAG_PLATFORM="apple"
        elif [[ $PLATFORM = "ios" || $PLATFORM = "isimulator" || $PLATFORM = "maccatalyst" ]]; then
            HOSTFLAG_PLATFORM="ios"
        elif [[ $PLATFORM = "tvos" || $PLATFORM = "tvsimulator" ]]; then
            HOSTFLAG_PLATFORM="tvos"
        fi
        HOSTFLAG="$ARCH-$HOSTFLAG_PLATFORM-darwin"
        if [[ $ARCH = "arm64" ]]; then
            if [[ "$PLATFORM" = "maccatalyst" ]]; then
                DEPLOYMENT_TARGET="-target arm64-apple-ios-macabi"
            fi
            CMAKE_OSX_ARCHITECTURES=$ARCH
            ACFLAGS="-arch $ARCH -isysroot $SDKPATH $DEPLOYMENT_TARGET"
            ALDFLAGS="-arch $ARCH -isysroot $SDKPATH $DEPLOYMENT_TARGET_LDFLAG"
        elif [[ $ARCH = "x86_64" ]]; then
            CMAKE_OSX_ARCHITECTURES=$ARCH
            ACFLAGS="-arch $ARCH -isysroot $SDKPATH $DEPLOYMENT_TARGET"
            ALDFLAGS="-arch $ARCH -isysroot $SDKPATH $DEPLOYMENT_TARGET_LDFLAG "
        else
            echo "Unhandled architecture option"
            exit 1
        fi

        CFLAGS="$ACFLAGS $CFLAG_HAVE_FORK $debug_flag"
        LDFLAGS="$ALDFLAGS"
        CXXFLAGS="$CFLAGS"
        CPPFLAGS="$CFLAGS"
        PKG_CONFIG_LIBDIR="$SCRATCH/$ARCH/lib/pkgconfig:$PKG_DEFAULT_PATH"

        mkdir -p $SCRATCH
        export COMMON_OPTION_PREFIX="--prefix=$SCRATCH/$ARCH"
        COMMON_OPTIONS="$COMMON_OPTION_PREFIX --enable-static \
            --disable-shared --disable-dependency-tracking --with-pic --host=$HOSTFLAG --with-sysroot=$SDKPATH"
        export MESON_COMMON_OPTIONS="-Dprefix=$SCRATCH/$ARCH -Dbuildtype=$buile_type -Ddefault_library=static --cross-file=$ROOT/meson/$PLATFORM-$ARCH.txt"
        #export MESON_COMMON_OPTIONS="-Dprefix=$SCRATCH/$ARCH -Dbuildtype=release -Ddefault_library=static"
        for LIBRARY in $LIBRARIES; do
            if [[ $LIBRARY = "moltenvk" ]]; then
                continue
            fi
            BUILDDIR=$SCRATCH/$ARCH/$LIBRARY
            echo "building $LIBRARY"
            rm -fr $BUILDDIR
            mkdir -p $BUILDDIR && cd $_ && $SCRIPTS/$LIBRARY-build $LIBRARY
        done
    done
done



