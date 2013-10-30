#!/bin/bash

DIR="$( cd -P "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

/opt/pin/pin -t $DIR/obj-intel64/*.so -- ${@}
