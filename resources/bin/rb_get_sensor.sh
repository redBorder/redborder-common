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
  echo "ERROR: $0 -s <sensor_name> [-t type][-l][-a]"
  echo
  echo "CURRENT HARDWARE SENSORS: "

  if [ "x$sensor_type" != "x" ]; then
    ipmitool sdr type "$sensor_type" get
  else
    ipmitool sdr
  fi
  exit 2
}

sensor=""
sensor_type=""
list=0
all=0

while getopts "s:t:i:u:p:hla" opt; do
  case $opt in
    l) list=1;;
    s) sensor=$OPTARG;;
    t) sensor_type=$OPTARG;;
    a) all=1;;
    i) host=$OPTARG;;
    u) user=$OPTARG;;
    p) password=$OPTARG;;
    h) usage;;
  esac
done

# echo "the host is $host the user is $user and the password is $password"

credentials=""
if [ "x$host" != "x" ]; then
  if [ "x$user" != "x" ]; then
    if [ "x$password" != "x" ]; then
      credentials=" -H $host -U $user -P $password "
    fi
  fi
fi

if [ $list -eq 1 ]; then
  ipmitool $credentials sdr type  list
else

  if [ "x$sensor" != "x" ]; then
    if [ "x$sensor_type" != "x" ]; then  
      result=$(ipmitool $credentials sdr type $sensor_type |grep -e "^$sensor[ ]*" | sed 's/.*|//' | awk '{print $1}')
    else
      result=$(ipmitool $credentials sdr|grep -e "^$sensor[ ]*" |  sed 's/[^|]*|//' | awk '{print $1}')
    fi
    
    [ $all -eq 0 ] && result=$(echo $result|head -n 1|sed 's/ .*//g')
    counter=0
    while read line; do
      if [ "x$result" != "x" ]; then
        echo $line | egrep -q "^[[:digit:]]+$"
        if [ $? -eq 0 ]; then
          [ $all -eq 1 -a $counter -ne 0 ] && echo -n ";"
          echo -n $line
          counter=$(($counter + 1))
        fi
      fi
    done <<< "$result"

    echo

  else
    usage
  fi
fi

