#!/bin/bash

PATH_INIT_SCRIPT="aws/lab1/init-script.sh"
ROOT_GIT_REPOSITORY=$(git rev-parse --show-toplevel)

. $ROOT_GIT_REPOSITORY/$PATH_INIT_SCRIPT