#!/bin/sh -xe

Help()
{
   # Display Help
   echo "build libmpv xcframework."
   echo "usage: xcframework.sh [-h]"
   echo "options:"
   echo "l     : Optional, libraries(crypto ssl srt png freetype brotli fribidi harfbuzz ass readline gmp nettle gnutls smbclient shaderc lcms2 dovi placebo dav1d bluray avcodec avdevice avfilter avformat avutil swresample swscale uchardet luajit mpv)."
   echo "h     : Optional, Print this Help."
   echo
}

LIBRARIES="crypto ssl srt png freetype brotli fribidi harfbuzz ass readline gmp nettle gnutls smbclient shaderc lcms2 dovi placebo dav1d bluray avcodec avdevice avfilter avformat avutil swresample swscale uchardet luajit mpv"
PLATFORMS="macos ios tvos isimulator tvsimulator"
ROOT="$(pwd)"
Framework="$ROOT/Framework"

while getopts ":hp:a:l:d" OPTION; do
    case $OPTION in
    h)
        Help
        exit
        ;;
    l)
        LIBRARIES=$(echo "$OPTARG" | awk '{print tolower($0)}')
        ;;
    ?)
        echo "Invalid option"
        exit 1
        ;;
    esac
done

for LIBRARY in $LIBRARIES; do
    arguments=""
    LIBRARY_NAME="lib$LIBRARY"
    if [[ "$LIBRARY" = "shaderc" ]]; then
        LIBRARY_NAME="libshaderc_combined"
    elif [[ "$LIBRARY" = "luajit" ]]; then
        LIBRARY_NAME="libluajit-5.1"
    else
        LIBRARY_NAME="lib$LIBRARY"
    fi
    for PLATFORM in $PLATFORMS; do
        ARCHS="x86_64 arm64"
        if [[ "$PLATFORM" = "ios" || "$PLATFORM" = "tvos" ]]; then
            ARCHS="arm64"
        fi
        SCRATCH="$ROOT/build/scratch-$PLATFORM"
        mkdir -p $SCRATCH/$LIBRARY_NAME.universal
        lipo_arguments=""
        for ARCH in $ARCHS; do
            if [[ ! -f "$SCRATCH/$ARCH/lib/$LIBRARY_NAME.a" ]]; then
                continue
            fi
            lipo_arguments="$lipo_arguments $SCRATCH/$ARCH/lib/$LIBRARY_NAME.a"
            header_dir=""
            if [[ -d "$SCRATCH/$ARCH/include/$LIBRARY" ]]; then
                header_dir="$SCRATCH/$ARCH/include/$LIBRARY"
            elif [[ -d "$SCRATCH/$ARCH/include/lib$LIBRARY" ]]; then
                header_dir="$SCRATCH/$ARCH/include/lib$LIBRARY"
            elif [[ "$LIBRARY" = "freetype" ]]; then
                header_dir="$SCRATCH/$ARCH/include/freetype2"
            elif [[ "$LIBRARY" = "png" ]]; then
                header_dir="$SCRATCH/$ARCH/include/*png*"
            elif [[ $LIBRARY = "luajit" ]]; then
                header_dir="$SCRATCH/$ARCH/include/luajit-2.1"
            elif [[ $LIBRARY = "ssl" ]]; then
                header_dir="$SCRATCH/$ARCH/include/openssl"
            elif [[ $LIBRARY = "lcms2" ]]; then
                header_dir="$SCRATCH/$ARCH/include/*lcms2*"
            fi
            mkdir -p $SCRATCH/$LIBRARY_NAME.universal/include
            if [[ $header_dir != "" ]]; then
                cp -R $header_dir $SCRATCH/$LIBRARY_NAME.universal/include/
            fi
        done
        if [[ $lipo_arguments = "" ]]; then
            continue
        fi
        lipo -create $lipo_arguments -output $SCRATCH/$LIBRARY_NAME.universal/$LIBRARY_NAME.a
        arguments="$arguments -library $SCRATCH/$LIBRARY_NAME.universal/$LIBRARY_NAME.a -headers $SCRATCH/$LIBRARY_NAME.universal/include"
    done
    
    if [[ $arguments = "" ]]; then
        continue
    fi
    rm -fr $Framework/Lib$LIBRARY.xcframework
    xcodebuild -create-xcframework $arguments -output $Framework/Lib$LIBRARY.xcframework

    #FULL_INFO_PLIST_PATH=$Framework"/"$LIBRARY".xcframework/Info.plist"
    #/usr/libexec/PlistBuddy -c "Add :MinimumOSVersion string 13.0" "$FULL_INFO_PLIST_PATH"
done
