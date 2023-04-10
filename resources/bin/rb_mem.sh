#!/bin/bash

#######################################################################
# Copyright (c) 2014 ENEO Tecnología S.L.
# This file is part of redBorder.
# redBorder is free software: you can redistribute it and/or modify
# it under the terms of the GNU Affero General Public License License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
# redBorder is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU Affero General Public License License for more details.
# You should have received a copy of the GNU Affero General Public License License
# along with redBorder. If not, see <http://www.gnu.org/licenses/>.
#######################################################################

function usage(){
  echo "$0 [ -p pid ] [ -f <filepid> ] [ -n serv ]"
}

pid=""
file=""
serv=""

while getopts "p:f:n:h" opt; do
  case $opt in
    p) pid=$OPTARG;;
    f) file=$OPTARG;;
    n) serv=$OPTARG;;
    h) usage;;
  esac
done

if [ "x$file" != "x" ]; then
  pid=$(head -n 1 $file)
fi

if [ "x$pid" != "x" ]; then
  if [ -f /proc/$pid/cmdline ]; then
    pmap -x $pid | grep total | awk '{print $4}' | sed 's/K//'
  fi
fi

if [ "x$serv" != "x" ]; then
  pid_serv=$(systemctl show --property MainPID $serv | sed 's/MainPID=//g')
  pmap -x $pid_serv | grep total | awk '{print $4}' | sed 's/K//'
fi
