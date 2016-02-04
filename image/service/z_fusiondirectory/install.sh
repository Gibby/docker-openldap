#!/bin/bash -e
# this script is run during the image build

LC_ALL=C DEBIAN_FRONTEND=noninteractive apt-get install -y $(cat /container/service/z_fusiondirectory/fusiondirectory.plugins | grep -v -f /container/service/z_fusiondirectory/fusiondirectory.plugins.ignore)

