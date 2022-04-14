#!/bin/bash


logme() {
# params:
# $1 - log level in uppercase (e.g. INFO,WARNING,ERROR)
# $2 - log message

  local level=$1
  local msg=$2
  echo "$(date '+%Y-%m-%d %H:%M:%S %z') [${level}] ${msg}"
}

