#!/bin/sh
#---------------------------------------------------------------------------#
# Copyright (C) 1995 University of Melbourne.
# This file may only be copied under the terms of the GNU General
# Public License - see the file COPYING in the Mercury distribution.
#---------------------------------------------------------------------------#

# MOD2INIT - Convert *.mod (or *.c) to *_init.c
#
# This script outputs an appropriate init.c, given the .mod (or .c) files.
#
# Usage: mod2init [-w<entry_point>] modules...
#
# Environment variables: MERCURY_MOD_LIB_DIR, MERCURY_MOD_LIB_MODS.

MERCURY_MOD_LIB_DIR=${MERCURY_MOD_LIB_DIR:-@LIBDIR@/modules}
MERCURY_MOD_LIB_MODS=${MERCURY_MOD_LIB_MODS:-@LIBDIR@/modules/*}

defentry=mercury__io__run_0_0
while getopts w: c
do
	case $c in
	w)	defentry="$OPTARG";;
	\?)	echo "Usage: mod2init -[wentry] modules ..."
		exit 1;;
	esac
	shift `expr $OPTIND - 1`
done

files="$* $MERCURY_MOD_LIB_MODS"
modules="`sed -n '/^BEGIN_MODULE(\(.*\)).*$/s//\1/p' $files`"
echo "/*";
echo "** This code was automatically generated by mod2init.";
echo "** Do not edit.";
echo "**"
echo "** Input files:"
for file in $files; do 
	echo "** $file"
done
echo "*/";
echo "";
echo '#include <stddef.h>';
echo '#include "init.h"';
echo "";
echo "Declare_entry($defentry);";
echo "#if defined(USE_GCC_NONLOCAL_GOTOS) && !defined(USE_ASM_LABELS)";
echo "Code *default_entry;";
echo "#else";
echo "Code *default_entry = ENTRY($defentry);";
echo "#endif";
echo "";
for mod in $modules; do
	echo "extern void $mod(void);";
done
echo "";
echo "#ifdef CONSERVATIVE_GC";
echo "/* This works around a bug in the Solaris 2.X (X <= 4) linker. */";
echo "/* The reason it is here is that it needs to be in statically linked */";
echo "/* code, it won't work if it is in the dynamically linked library. */";
echo "void init_gc(void)";
echo "{";
echo "    GC_INIT();";
echo "}";
echo "#endif";
echo "";
echo "void init_modules(void)";
echo "{";
for mod in $modules; do
	echo "	$mod();";
done
echo "";
echo "	default_entry = ENTRY($defentry);";
echo "}";
