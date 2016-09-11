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

# Prints device name
# $1 - path to mounted directory
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

# Prints all connected MTP devices
printDevices()
{
	local ids idsIter i IFS
	ids="$(find /run/user/$(id -u)/gvfs/ -maxdepth 1 -type d -name 'mtp:*')"
	i=0
	IFS=$'\n'
	if [[ "$ids" ]]; then
		for idsIter in "$ids"; do
			((++i))
			echo "$i. $(deviceInfo $idsIter)"
		done
	else
		echo "No connected MTP devices found"
	fi
}

# Defaults
backupPath="."
deviceNum="1"

args="$(getopt -o d:prh --long device:,print,reverse,help -n ${0##*/} -- "$@")"
(( $? != 0 )) && exit 1
eval set -- "$args"

while true ; do
	case "$1" in
		-d|--device)
			if [[ $2 =~ [0-9]+ ]]; then
				deviceNum="$2"
			else
				echo "$1 requires an integer value."
				printUsage
				exit 1
			fi
			shift 2
			;;
		-p|--print)
			printDevices
			exit
			;;
		-r|--reverse)
			reverse=true
			shift
			;;
		-h|--help)
			printUsage
			exit
			;;
		--)
			shift
			break
			;;
		*)
			echo "Unkown argument: $1"
			printUsage
			exit 1
			;;
	esac
done
(( $# > 1 )) && echo "Wrong number of positional arguments" && exit 1
(( $# == 1)) && backupPath="${1%/}"

if [[ ! -d "$backupPath" ]]; then
	echo "Error: '$backupPath' does not exist, or is not a directory."
	exit 2
fi

# Find leaf directories
skel="$(find $backupPath -type d -exec sh -c '(ls -p "{}"|grep />/dev/null)||echo "{}"' \;)"

# Select working device
devicePath="$(find /run/user/$(id -u)/gvfs/ -maxdepth 1 -type d -name 'mtp:*')"
devicePathNum="$(echo $devicePath | wc -l | cut -d' ' -f1)"
if [[ ! "$devicePath" ]]; then
	echo "Error: No connected MTP device found."
	exit 3
elif (( $deviceNum < 1 || $devicePathNum < $deviceNum )); then
	echo "Error: Device with NUM=$deviceNum does not exist"
	echo "Connected devices:"
	printDevices
	exit 3
else
	devicePath="$(echo $devicePath | head -n$deviceNum | tail -n1)"
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
	cmd() { rsync -avh --delete "$@" ;}
	# If doing reverse operation, permissions and timestamps cannot be preserved
	# on Android device over MTP because of a bug in FUSE implementation,
	# so we must use `-rl --size-only` instead of `-a` rsync option.
	# Last tested on Android Marshmallow, and still not fixed.
	cmd_r() { rsync -rlvh --size-only "$@" ;}
	if [[ "$reverse" != true ]]; then
		for dir in $skel; do
			cmd "${dir/$backupPath/$devicePath}/" "$dir/"
		done
	else
		for dir in $skel; do
			cmd_r "$dir/" "${dir/$backupPath/$devicePath}/"
		done
	fi
	unset IFS
else
	echo Abort.
	exit
fi
