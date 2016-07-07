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

source /etc/profile

function usage() {
  echo "$0 [ -d ][ -q ]"
}

debug=0
quiet=0

while getopts "hdq" name
do
  case $name in
    h) usage;;
    q) quiet=1;;
    d) debug=1;;
  esac
done

chef_cmd=""

[ $debug -eq 1 ] && chef_cmd="$chef_cmd -l debug"
[ $quiet -eq 1 ] && chef_cmd="$chef_cmd -L /dev/null"


chef-client -c /etc/chef/client.rb --once -s 5 --node-name $(hostname -s) -j /etc/chef/role-manager-once.json $chef_cmd
