#!/bin/bash
# adbackup - incremental backups for your Android device
# Copyright (C) <2016>  <Bojan Stipic>
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.

# Prints usage information
printUsage()
{
cat << _EOF_
Usage: ${0##*/} [OPTION]... [DIRECTORY]

DESCRIPTION:
	Creates an incremental backup of MTP device inside DIRECTORY.
	If more than one device is connected, you should use -p and -d options (see OPTIONS below)

OPTIONS:
	-d, --device=NUM
		Specify which MTP device to use if there is more than one is connected. NUM=1 by default. Use -p option to list all devices.
	-p, --print
		List all connected devices.
	-r, --reverse
		Reverse operation - restore backup to device.
	-h, --help
		Display help and exit.
_EOF_
}

# Prints connected MTP devices
printDevices()
{
	local ids idsIter i IFS bus device output
	ids="$(find /run/user/$(id -u)/gvfs/ -maxdepth 1 -type d -name 'mtp:*')"\
	i=0
	IFS=$'\n'
	if [[ "$ids" ]]; then
		for idsIter in "$ids"; do
			((++i))
			bus=${idsIter#*%3A}
			bus=${bus%\%2C*}
			device=${idsIter#*%2C}
			device=${device%\%5D*}
			output="$i. $(lsusb | grep "Bus $bus Device $device" | cut -d' ' -f7-)"
			echo "$output"
		done
	else
		echo "No connected MTP devices found"
	fi
}

deviceInfo()
{
	local bus device output
	bus=${@#*%3A}
	bus=${bus%\%2C*}
	device=${@#*%2C}
	device=${device%\%5D*}
	output="$(lsusb | grep "Bus $bus Device $device" | cut -d' ' -f7-)"
	echo "$output"
}

# Defaults
backupPath="."
deviceNum="1"

# Parse arguments
if (( $# > 0 )); then
	isBackupPathSet=false
	for arg in "$@"; do
		if [[ "$arg" =~ ^[^-] && $isBackupPathSet == false ]]; then
			backupPath="${arg%/}"
			isBackupPathSet=true
		elif [[ "$arg" =~ -d[0-9]+ || "$arg" =~ --device=[0-9]+ ]]; then
			deviceNum="$arg"
			deviceNum="${deviceNum#-d}"
			deviceNum="${deviceNum#--device=}"
		elif [[ "$arg" == -r || "$arg" == --reverse ]]; then
			reverse=true
		elif [[ "$arg" == -h || "$arg" == --help ]]; then
			printUsage
			exit
		elif [[ "$arg" == -p || "$arg" == --print ]]; then
			printDevices
			exit
		else
			echo "Unkown argument: $arg"
			printUsage
			exit 1
	  	fi
	done
fi

if [[ ! -d "$backupPath" ]]; then
	echo "Error: '$backupPath' does not exist, or is not a directory."
	exit 2
fi

# Find leaf directories
skel="$(find $backupPath -type d -exec sh -c '(ls -p "{}"|grep />/dev/null)||echo "{}"' \;)"

devicePath="$(find /run/user/$(id -u)/gvfs/ -maxdepth 1 -type d -name 'mtp:*' | head -n$deviceNum | tail -n1)"

if [[ ! "$devicePath" ]]; then
	echo "Error: MTP device was not found."
    exit 3
fi

# Show summary and prompt user
echo "Device:"
deviceInfo "$devicePath"
echo -e "\nBackup root directory:"
echo "$backupPath"
echo -e "\nLeaf directories found: "
echo "${skel#$backupPath/}"
echo
test "$reverse" == true && echo "REVERSE BACKUP mode"
echo -n "Continue? [Y/n] "
read -r ans

# Do incremental backup
if [[ $ans == y || $ans == Y || ! $ans ]]; then
	IFS=$'\n'
	cmd() { rsync -rlvh --delete --ignore-existing "$@" ;}
	if [[ "$reverse" == true ]]; then
		for dir in $skel; do
			cmd "$dir/" "${dir/$backupPath/$devicePath}/"
		done
	else
		for dir in $skel; do
			cmd "${dir/$backupPath/$devicePath}/" "$dir/"
		done
	fi
	unset IFS
else
	echo Abort.
	exit
fi
