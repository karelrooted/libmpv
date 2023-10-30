#!/bin/bash

############################################################
# Help                                                     #
############################################################
Help()
{
   # Display Help
   echo "build binary target."
   echo "usage: resignipa.sh -i <ipa file path> [ -s \"<signing-identity>\" -p \"<profile_name_or_path>\" -d device_name_or_ecid -k ] | [-h]"
   echo "options:"
   echo "i     : The path to the original ipa file to be resigned."
   echo "s     : Optional, The identiy/name of the signing certifiate installed in keychain."
   echo "p     : Optional, The name or path to the provisioning profile. ex: \"tvOS Team Provisioning Profile: com.karelrooted.yattee\""
   echo "d     : Optional, Install ipa to device, value can be Device name or ecid."
   echo "k     : Optional, Keep the resign ipa, default: the resign ipa in temp directory will be deleted"
   echo "h     : Optional, Print this Help."
   echo
}

#!/bin/bash

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
            url: "https://github.com/some/remote/$xcframework.zip",
            checksum: "$checksum"
        ),
EndOfMessage
  
done
