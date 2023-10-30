#!/bin/sh -xe

############################################################
# Help                                                     #
############################################################
Help()
{
   # Display Help
   echo "create zip framework."
   echo "usage: createZipFramework.sh [-h]"
   echo "options:"
   echo "h     : Optional, Print this Help."
   echo
}

touch Package.swift
# Define the target directory
directory="Framework"

# Check if the target is not a directory
if [ ! -d "$directory" ]; then
  exit 1
fi
cd $directory

# Loop through files in the target directory
for xcframework in *; do
  zip -qr $xcframework.zip $xcframework
  library=$(echo "$xcframework"  | cut -d . -f 1)
  checksum=$(swift package compute-checksum $xcframework.zip)
  cat << EndOfMessage
.binaryTarget(
            name: "$library",
            url: "https://github.com/karelrooted/libmpv/releases/download/v0.37.0-alpha/$xcframework.zip",
            checksum: "$checksum"
        ),
EndOfMessage
  rm -fr $xcframework
done
cd -
tar -czf Framework.tgz Framework
