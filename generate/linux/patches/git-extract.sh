#!/bin/sh
#
# NAME:
#         git-extract.sh - extract linuxized sources/patches from the ACPICA
#                          git repository
#
# SYNOPSIS:
#         git-extract.sh [-r] <commit>
#
# DESCRIPTION:
#         Extract linuxized patches from the git repository.
#         !-r mode (extracting patches mode):
#                  Extract the linuxized patch of the given commit from the
#                  ACPICA git repository.
#          -r mode (extracting sources mode):
#                  Extract the linuxized repository of the given commit from
#                  the ACPICA git repository.
#	  NOTE: Be careful using this script on a repo in detached HEAD mode.
#
# AUTHOR:
#         Lv Zheng <lv.zheng@intel.com>
#
# COPYRIGHT:
#         Copyright (c) 2012-2013, Intel Corporation.
#

usage() {
	echo "Usage: `basename $0` [-r] <commit>"
	echo "Where:"
	echo "     -r: Extract Linux repository of the commit."
	echo "         or"
	echo "         Extract Linux patch of the commit."
	echo " commit: GIT commit (default to HEAD)."
	exit -1
}

while getopts "r" opt
do
	case $opt in
	r) EXTRACT_REPO=true;;
	?) echo "Invalid argument $opt"
	   usage;;
	esac
done
shift $(($OPTIND - 1))

version=$1

fulldir()
{
	lpath=$1
	(
		cd $lpath; pwd
	)
}

getdir()
{
	lpath=`dirname $1`
	fulldir $lpath
}

SCRIPT=`getdir $0`
CURDIR=`pwd`
ACPISRC=$SCRIPT/bin/acpisrc

GE_git_repo=`cd $SCRIPT/../../..; pwd`
GE_acpica_repo=$CURDIR/acpica-$version
GE_linux_repo=$CURDIR/linux-$version
GE_linux_before=$CURDIR/linux.before
GE_linux_after=$CURDIR/linux.after

linuxize_hierarchy()
{
	subdirs="dispatcher events executer hardware \
		namespace parser resources tables utilities"

	# Making hierarchy
	mv components/* .
	rm -rf common compiler components \
	       debugger disassembler \
	       interpreter \
	       os_specific \
	       tools

	# Making public include files
	if [ -d include ]; then
		mkdir -p acpi_include
		mv -f include/* acpi_include
		mv -f acpi_include include/acpi
	fi

	# Making source files
	mkdir -p drivers/acpi/acpica
	# Moving files
	for subdir in $subdirs; do
		if [ -d $subdir ]; then
			mv $subdir/* drivers/acpi/acpica/
			# Removing directories
			echo "Removing $subdir"
			rm -rf $subdir
		fi
	done

	# Making private include files
	private_includes="accommon.h"
	private_includes="$private_includes acdebug.h acdisasm.h acdispat.h"
	private_includes="$private_includes acevents.h"
	private_includes="$private_includes acglobal.h"
	private_includes="$private_includes achware.h"
	private_includes="$private_includes acinterp.h"
	private_includes="$private_includes aclocal.h"
	private_includes="$private_includes acmacros.h"
	private_includes="$private_includes acnamesp.h"
	private_includes="$private_includes acobject.h acopcode.h"
	private_includes="$private_includes acparser.h acpredef.h"
	private_includes="$private_includes acresrc.h"
	private_includes="$private_includes acstruct.h"
	private_includes="$private_includes actables.h"
	private_includes="$private_includes acutils.h"
	private_includes="$private_includes amlcode.h amlresrc.h"
	for inc in $private_includes ; do
		if [ -f include/acpi/$inc ] ; then
			mv include/acpi/$inc drivers/acpi/acpica/
		fi
	done
}

linuxize()
{
	# Be careful with local variable namings
	repo_acpica=$1
	repo_linux=$2

	echo "Converting format (acpisrc)..."
	$ACPISRC -ldqy $repo_acpica/source $repo_linux > /dev/null

	echo "Converting format (hierarchy)..."
	(
		cd $repo_linux
		ls
		linuxize_hierarchy
	)

	echo "Converting format (lindent)..."
	(
		cd $repo_linux
		find . -name "*.[ch]" | xargs ../lindent.sh
		find . -name "*~" | xargs rm -f
	)
}

{
	echo "Extracting GIT ($GE_git_repo)..."
	# Cleanup
	rm -rf $GE_acpica_repo

	echo "Creating ACPICA repository ($GE_acpica_repo)..."
	git clone $GE_git_repo $GE_acpica_repo > /dev/null
	(
		cd $GE_acpica_repo
		git reset $version --hard >/dev/null 2>&1
	)

	if [ ! -f $ACPISRC ]; then
		echo "Generating AcpiSrc..."
		(
			cd $SCRIPT
			$SCRIPT/acpisrc.sh $GE_acpica_repo
		)
	fi

	if [ "x$EXTRACT_REPO" = "xtrue" ] ; then
		# Cleanup
		rm -rf $GE_linux_repo

		echo "Creating Linux repository ($GE_linux_repo)..."
		linuxize $GE_acpica_repo $GE_linux_repo
	else
		revision=`git log -1 --format=%H`

		GE_acpica_patch=$CURDIR/acpica-$revision.patch
		GE_linux_patch=$CURDIR/linux-$revision.patch

		# Cleanup
		rm -rf $GE_linux_after
		rm -rf $GE_linux_before
		rm -f $GE_linux_patch
		rm -f $GE_acpica_patch

		(
			echo "Creating ACPICA patch ($GE_acpica_patch)..."
			cd $GE_acpica_repo
			git format-patch -1 --stdout >> $GE_acpica_patch
		)

		echo "Creating Linux repository $version+ ($GE_linux_after)..."
		linuxize $GE_acpica_repo $GE_linux_after

		(
			echo "Patching repository ($GE_acpica_repo)..."
			cd $GE_acpica_repo
			patch -R -p1 < $GE_acpica_patch > /dev/null
		)

		echo "Creating Linux repository $version- ($GE_linux_before)..."
		linuxize $GE_acpica_repo $GE_linux_before

		(
			echo "Creating Linux patch ($GE_linux_patch)..."
			cd $CURDIR
			tmpfile=`tempfile`
			diff -Nurp linux.before linux.after >> $tmpfile
			git log -c $revision -1 --format="From %H Mon Sep 17 00:00:00 2001%nFrom: %aN <%aE>%nData: %aD%nSubject: [PATCH] %s%n%n%b---" > $GE_linux_patch
			diffstat $tmpfile >> $GE_linux_patch
			echo >> $GE_linux_patch
			cat $tmpfile >> $GE_linux_patch
			rm -f $tmpfile
		)

		# Cleanup temporary directories
		rm -rf $GE_linux_before
		rm -rf $GE_linux_after
		rm -rf $GE_acpica_repo
	fi
}
