#!/usr/bin/env bash

# To be able to use the mac touchbar for sudo command auth:
# edit the following file: /etc/pam.d/sudo
# and add the following line after the initial comment line:
#   `auth sufficient pam_tid.so`
# This script also verifies that this line is added only once (ie skips if already present)
COUNT=$(grep -c pam_tid /etc/pam.d/sudo)
if [[ $COUNT -gt 0 ]]; then
  echo "ALREADY PRESENT - Not adding again!!!"
else
  echo "INCLUDING NEW LINE!!!"
  sudo sed -i '' '2i\
auth       sufficient     pam_tid.so\
' /etc/pam.d/sudo
fi
