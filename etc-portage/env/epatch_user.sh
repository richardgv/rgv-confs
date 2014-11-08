# Copied from: /usr/portage/eclass/eutils.eclass

# @FUNCTION: estack_push
# @USAGE: <stack> [items to push]
# @DESCRIPTION:
# Push any number of items onto the specified stack.  Pick a name that
# is a valid variable (i.e. stick to alphanumerics), and push as many
# items as you like onto the stack at once.
#
# The following code snippet will echo 5, then 4, then 3, then ...
# @CODE
#		estack_push mystack 1 2 3 4 5
#		while estack_pop mystack i ; do
#			echo "${i}"
#		done
# @CODE
estack_push() {
	[[ $# -eq 0 ]] && die "estack_push: incorrect # of arguments"
	local stack_name="_ESTACK_$1_" ; shift
	eval ${stack_name}+=\( \"\$@\" \)
}

# @FUNCTION: estack_pop
# @USAGE: <stack> [variable]
# @DESCRIPTION:
# Pop a single item off the specified stack.  If a variable is specified,
# the popped item is stored there.  If no more items are available, return
# 1, else return 0.  See estack_push for more info.
estack_pop() {
	[[ $# -eq 0 || $# -gt 2 ]] && die "estack_pop: incorrect # of arguments"

	# We use the fugly _estack_xxx var names to avoid collision with
	# passing back the return value.  If we used "local i" and the
	# caller ran `estack_pop ... i`, we'd end up setting the local
	# copy of "i" rather than the caller's copy.  The _estack_xxx
	# garbage is preferable to using $1/$2 everywhere as that is a
	# bit harder to read.
	local _estack_name="_ESTACK_$1_" ; shift
	local _estack_retvar=$1 ; shift
	eval local _estack_i=\${#${_estack_name}\[@\]}
	# Don't warn -- let the caller interpret this as a failure
	# or as normal behavior (akin to `shift`)
	[[ $(( --_estack_i )) -eq -1 ]] && return 1

	if [[ -n ${_estack_retvar} ]] ; then
		eval ${_estack_retvar}=\"\${${_estack_name}\[${_estack_i}\]}\"
	fi
	eval unset ${_estack_name}\[${_estack_i}\]
}

# @FUNCTION: evar_push
# @USAGE: <variable to save> [more vars to save]
# @DESCRIPTION:
# This let's you temporarily modify a variable and then restore it (including
# set vs unset semantics).  Arrays are not supported at this time.
#
# This is meant for variables where using `local` does not work (such as
# exported variables, or only temporarily changing things in a func).
#
# For example:
# @CODE
#		evar_push LC_ALL
#		export LC_ALL=C
#		... do some stuff that needs LC_ALL=C set ...
#		evar_pop
#
#		# You can also save/restore more than one var at a time
#		evar_push BUTTERFLY IN THE SKY
#		... do stuff with the vars ...
#		evar_pop     # This restores just one var, SKY
#		... do more stuff ...
#		evar_pop 3   # This pops the remaining 3 vars
# @CODE
evar_push() {
	local var val
	for var ; do
		[[ ${!var+set} == "set" ]] \
			&& val=${!var} \
			|| val="unset_76fc3c462065bb4ca959f939e6793f94"
		estack_push evar "${var}" "${val}"
	done
}

# @FUNCTION: evar_push_set
# @USAGE: <variable to save> [new value to store]
# @DESCRIPTION:
# This is a handy shortcut to save and temporarily set a variable.  If a value
# is not specified, the var will be unset.
evar_push_set() {
	local var=$1
	evar_push ${var}
	case $# in
	1) unset ${var} ;;
	2) printf -v "${var}" '%s' "$2" ;;
	*) die "${FUNCNAME}: incorrect # of args: $*" ;;
	esac
}

# @FUNCTION: evar_pop
# @USAGE: [number of vars to restore]
# @DESCRIPTION:
# Restore the variables to the state saved with the corresponding
# evar_push call.  See that function for more details.
evar_pop() {
	local cnt=${1:-bad}
	case $# in
	0) cnt=1 ;;
	1) isdigit "${cnt}" || die "${FUNCNAME}: first arg must be a number: $*" ;;
	*) die "${FUNCNAME}: only accepts one arg: $*" ;;
	esac

	local var val
	while (( cnt-- )) ; do
		estack_pop evar val || die "${FUNCNAME}: unbalanced push"
		estack_pop evar var || die "${FUNCNAME}: unbalanced push"
		[[ ${val} == "unset_76fc3c462065bb4ca959f939e6793f94" ]] \
			&& unset ${var} \
			|| printf -v "${var}" '%s' "${val}"
	done
}

# @FUNCTION: eshopts_push
# @USAGE: [options to `set` or `shopt`]
# @DESCRIPTION:
# Often times code will want to enable a shell option to change code behavior.
# Since changing shell options can easily break other pieces of code (which
# assume the default state), eshopts_push is used to (1) push the current shell
# options onto a stack and (2) pass the specified arguments to set.
#
# If the first argument is '-s' or '-u', we assume you want to call `shopt`
# rather than `set` as there are some options only available via that.
#
# A common example is to disable shell globbing so that special meaning/care
# may be used with variables/arguments to custom functions.  That would be:
# @CODE
#		eshopts_push -o noglob
#		for x in ${foo} ; do
#			if ...some check... ; then
#				eshopts_pop
#				return 0
#			fi
#		done
#		eshopts_pop
# @CODE
eshopts_push() {
	if [[ $1 == -[su] ]] ; then
		estack_push eshopts "$(shopt -p)"
		[[ $# -eq 0 ]] && return 0
		shopt "$@" || die "${FUNCNAME}: bad options to shopt: $*"
	else
		estack_push eshopts $-
		[[ $# -eq 0 ]] && return 0
		set "$@" || die "${FUNCNAME}: bad options to set: $*"
	fi
}

# @FUNCTION: eshopts_pop
# @USAGE:
# @DESCRIPTION:
# Restore the shell options to the state saved with the corresponding
# eshopts_push call.  See that function for more details.
eshopts_pop() {
	local s
	estack_pop eshopts s || die "${FUNCNAME}: unbalanced push"
	if [[ ${s} == "shopt -"* ]] ; then
		eval "${s}" || die "${FUNCNAME}: sanity: invalid shopt options: ${s}"
	else
		set +$-     || die "${FUNCNAME}: sanity: invalid shell settings: $-"
		set -${s}   || die "${FUNCNAME}: sanity: unable to restore saved shell settings: ${s}"
	fi
}

# @FUNCTION: isdigit
# @USAGE: <number> [more numbers]
# @DESCRIPTION:
# Return true if all arguments are numbers.
isdigit() {
	local d
	for d ; do
		[[ ${d:-bad} == *[!0-9]* ]] && return 1
	done
	return 0
}

# @VARIABLE: EPATCH_SOURCE
# @DESCRIPTION:
# Default directory to search for patches.
EPATCH_SOURCE="${WORKDIR}/patch"
# @VARIABLE: EPATCH_SUFFIX
# @DESCRIPTION:
# Default extension for patches (do not prefix the period yourself).
EPATCH_SUFFIX="patch.bz2"
# @VARIABLE: EPATCH_OPTS
# @DESCRIPTION:
# Options to pass to patch.  Meant for ebuild/package-specific tweaking
# such as forcing the patch level (-p#) or fuzz (-F#) factor.  Note that
# for single patch tweaking, you can also pass flags directly to epatch.
EPATCH_OPTS=""
# @VARIABLE: EPATCH_COMMON_OPTS
# @DESCRIPTION:
# Common options to pass to `patch`.  You probably should never need to
# change these.  If you do, please discuss it with base-system first to
# be sure.
# @CODE
#	-g0 - keep RCS, ClearCase, Perforce and SCCS happy #24571
#	--no-backup-if-mismatch - do not leave .orig files behind
#	-E - automatically remove empty files
# @CODE
EPATCH_COMMON_OPTS="-g0 -E --no-backup-if-mismatch"
# @VARIABLE: EPATCH_EXCLUDE
# @DESCRIPTION:
# List of patches not to apply.	 Note this is only file names,
# and not the full path.  Globs accepted.
EPATCH_EXCLUDE=""
# @VARIABLE: EPATCH_SINGLE_MSG
# @DESCRIPTION:
# Change the printed message for a single patch.
EPATCH_SINGLE_MSG=""
# @VARIABLE: EPATCH_MULTI_MSG
# @DESCRIPTION:
# Change the printed message for multiple patches.
EPATCH_MULTI_MSG="Applying various patches (bugfixes/updates) ..."
# @VARIABLE: EPATCH_FORCE
# @DESCRIPTION:
# Only require patches to match EPATCH_SUFFIX rather than the extended
# arch naming style.
EPATCH_FORCE="no"
# @VARIABLE: EPATCH_USER_EXCLUDE
# @DEFAULT_UNSET
# @DESCRIPTION:
# List of patches not to apply.	 Note this is only file names,
# and not the full path.  Globs accepted.

# @FUNCTION: epatch
# @USAGE: [options] [patches] [dirs of patches]
# @DESCRIPTION:
# epatch is designed to greatly simplify the application of patches.  It can
# process patch files directly, or directories of patches.  The patches may be
# compressed (bzip/gzip/etc...) or plain text.  You generally need not specify
# the -p option as epatch will automatically attempt -p0 to -p4 until things
# apply successfully.
#
# If you do not specify any patches/dirs, then epatch will default to the
# directory specified by EPATCH_SOURCE.
#
# Any options specified that start with a dash will be passed down to patch
# for this specific invocation.  As soon as an arg w/out a dash is found, then
# arg processing stops.
#
# When processing directories, epatch will apply all patches that match:
# @CODE
#	if ${EPATCH_FORCE} != "yes"
#		??_${ARCH}_foo.${EPATCH_SUFFIX}
#	else
#		*.${EPATCH_SUFFIX}
# @CODE
# The leading ?? are typically numbers used to force consistent patch ordering.
# The arch field is used to apply patches only for the host architecture with
# the special value of "all" means apply for everyone.  Note that using values
# other than "all" is highly discouraged -- you should apply patches all the
# time and let architecture details be detected at configure/compile time.
#
# If EPATCH_SUFFIX is empty, then no period before it is implied when searching
# for patches to apply.
#
# Refer to the other EPATCH_xxx variables for more customization of behavior.
epatch() {
	_epatch_draw_line() {
		# create a line of same length as input string
		[[ -z $1 ]] && set "$(printf "%65s" '')"
		echo "${1//?/=}"
	}

	unset P4CONFIG P4PORT P4USER # keep perforce at bay #56402

	# First process options.  We localize the EPATCH_OPTS setting
	# from above so that we can pass it on in the loop below with
	# any additional values the user has specified.
	local EPATCH_OPTS=( ${EPATCH_OPTS[*]} )
	while [[ $# -gt 0 ]] ; do
		case $1 in
		-*) EPATCH_OPTS+=( "$1" ) ;;
		*) break ;;
		esac
		shift
	done

	# Let the rest of the code process one user arg at a time --
	# each arg may expand into multiple patches, and each arg may
	# need to start off with the default global EPATCH_xxx values
	if [[ $# -gt 1 ]] ; then
		local m
		for m in "$@" ; do
			epatch "${m}"
		done
		return 0
	fi

	local SINGLE_PATCH="no"
	# no args means process ${EPATCH_SOURCE}
	[[ $# -eq 0 ]] && set -- "${EPATCH_SOURCE}"

	if [[ -f $1 ]] ; then
		SINGLE_PATCH="yes"
		set -- "$1"
		# Use the suffix from the single patch (localize it); the code
		# below will find the suffix for us
		local EPATCH_SUFFIX=$1

	elif [[ -d $1 ]] ; then
		# We have to force sorting to C so that the wildcard expansion is consistent #471666.
		evar_push_set LC_COLLATE C
		# Some people like to make dirs of patches w/out suffixes (vim).
		set -- "$1"/*${EPATCH_SUFFIX:+."${EPATCH_SUFFIX}"}
		evar_pop

	elif [[ -f ${EPATCH_SOURCE}/$1 ]] ; then
		# Re-use EPATCH_SOURCE as a search dir
		epatch "${EPATCH_SOURCE}/$1"
		return $?

	else
		# sanity check ... if it isn't a dir or file, wtf man ?
		[[ $# -ne 0 ]] && EPATCH_SOURCE=$1
		echo
		eerror "Cannot find \$EPATCH_SOURCE!  Value for \$EPATCH_SOURCE is:"
		eerror
		eerror "  ${EPATCH_SOURCE}"
		eerror "  ( ${EPATCH_SOURCE##*/} )"
		echo
		die "Cannot find \$EPATCH_SOURCE!"
	fi

	# Now that we know we're actually going to apply something, merge
	# all of the patch options back in to a single variable for below.
	EPATCH_OPTS="${EPATCH_COMMON_OPTS} ${EPATCH_OPTS[*]}"

	local PIPE_CMD
	case ${EPATCH_SUFFIX##*\.} in
		xz)      PIPE_CMD="xz -dc"    ;;
		lzma)    PIPE_CMD="lzma -dc"  ;;
		bz2)     PIPE_CMD="bzip2 -dc" ;;
		gz|Z|z)  PIPE_CMD="gzip -dc"  ;;
		ZIP|zip) PIPE_CMD="unzip -p"  ;;
		*)       ;;
	esac

	[[ ${SINGLE_PATCH} == "no" ]] && einfo "${EPATCH_MULTI_MSG}"

	local x
	for x in "$@" ; do
		# If the patch dir given contains subdirs, or our EPATCH_SUFFIX
		# didn't match anything, ignore continue on
		[[ ! -f ${x} ]] && continue

		local patchname=${x##*/}

		# Apply single patches, or forced sets of patches, or
		# patches with ARCH dependant names.
		#	???_arch_foo.patch
		# Else, skip this input altogether
		local a=${patchname#*_} # strip the ???_
		a=${a%%_*}              # strip the _foo.patch
		if ! [[ ${SINGLE_PATCH} == "yes" || \
				${EPATCH_FORCE} == "yes" || \
				${a} == all     || \
				${a} == ${ARCH} ]]
		then
			continue
		fi

		# Let people filter things dynamically
		if [[ -n ${EPATCH_EXCLUDE}${EPATCH_USER_EXCLUDE} ]] ; then
			# let people use globs in the exclude
			eshopts_push -o noglob

			local ex
			for ex in ${EPATCH_EXCLUDE} ; do
				if [[ ${patchname} == ${ex} ]] ; then
					einfo "  Skipping ${patchname} due to EPATCH_EXCLUDE ..."
					eshopts_pop
					continue 2
				fi
			done

			for ex in ${EPATCH_USER_EXCLUDE} ; do
				if [[ ${patchname} == ${ex} ]] ; then
					einfo "  Skipping ${patchname} due to EPATCH_USER_EXCLUDE ..."
					eshopts_pop
					continue 2
				fi
			done

			eshopts_pop
		fi

		if [[ ${SINGLE_PATCH} == "yes" ]] ; then
			if [[ -n ${EPATCH_SINGLE_MSG} ]] ; then
				einfo "${EPATCH_SINGLE_MSG}"
			else
				einfo "Applying ${patchname} ..."
			fi
		else
			einfo "  ${patchname} ..."
		fi

		# most of the time, there will only be one run per unique name,
		# but if there are more, make sure we get unique log filenames
		local STDERR_TARGET="${T}/${patchname}.out"
		if [[ -e ${STDERR_TARGET} ]] ; then
			STDERR_TARGET="${T}/${patchname}-$$.out"
		fi

		printf "***** %s *****\nPWD: %s\n\n" "${patchname}" "${PWD}" > "${STDERR_TARGET}"

		# Decompress the patch if need be
		local count=0
		local PATCH_TARGET
		if [[ -n ${PIPE_CMD} ]] ; then
			PATCH_TARGET="${T}/$$.patch"
			echo "PIPE_COMMAND:  ${PIPE_CMD} ${x} > ${PATCH_TARGET}" >> "${STDERR_TARGET}"

			if ! (${PIPE_CMD} "${x}" > "${PATCH_TARGET}") >> "${STDERR_TARGET}" 2>&1 ; then
				echo
				eerror "Could not extract patch!"
				#die "Could not extract patch!"
				count=5
				break
			fi
		else
			PATCH_TARGET=${x}
		fi

		# Check for absolute paths in patches.  If sandbox is disabled,
		# people could (accidently) patch files in the root filesystem.
		# Or trigger other unpleasantries #237667.  So disallow -p0 on
		# such patches.
		local abs_paths=$(egrep -n '^[-+]{3} /' "${PATCH_TARGET}" | awk '$2 != "/dev/null" { print }')
		if [[ -n ${abs_paths} ]] ; then
			count=1
			printf "NOTE: skipping -p0 due to absolute paths in patch:\n%s\n" "${abs_paths}" >> "${STDERR_TARGET}"
		fi
		# Similar reason, but with relative paths.
		local rel_paths=$(egrep -n '^[-+]{3} [^	]*[.][.]/' "${PATCH_TARGET}")
		if [[ -n ${rel_paths} ]] ; then
			echo
			eerror "Rejected Patch: ${patchname} !"
			eerror " ( ${PATCH_TARGET} )"
			eerror
			eerror "Your patch uses relative paths '../':"
			eerror "${rel_paths}"
			echo
			die "you need to fix the relative paths in patch"
		fi

		# Dynamically detect the correct -p# ... i'm lazy, so shoot me :/
		local patch_cmd
		# Handle aliased patch command #404447 #461568
		local patch="patch"
		eval $(alias patch 2>/dev/null | sed 's:^alias ::')
		while [[ ${count} -lt 5 ]] ; do
			patch_cmd="${patch} -p${count} ${EPATCH_OPTS}"

			# Generate some useful debug info ...
			(
			_epatch_draw_line "***** ${patchname} *****"
			echo
			echo "PATCH COMMAND:  ${patch_cmd} < '${PATCH_TARGET}'"
			echo
			_epatch_draw_line "***** ${patchname} *****"
			${patch_cmd} --dry-run -f < "${PATCH_TARGET}" 2>&1
			ret=$?
			echo
			echo "patch program exited with status ${ret}"
			exit ${ret}
			) >> "${STDERR_TARGET}"

			if [ $? -eq 0 ] ; then
				(
				_epatch_draw_line "***** ${patchname} *****"
				echo
				echo "ACTUALLY APPLYING ${patchname} ..."
				echo
				_epatch_draw_line "***** ${patchname} *****"
				${patch_cmd} < "${PATCH_TARGET}" 2>&1
				ret=$?
				echo
				echo "patch program exited with status ${ret}"
				exit ${ret}
				) >> "${STDERR_TARGET}"

				if [ $? -ne 0 ] ; then
					echo
					eerror "A dry-run of patch command succeeded, but actually"
					eerror "applying the patch failed!"
					#die "Real world sux compared to the dreamworld!"
					count=5
				fi
				break
			fi

			: $(( count++ ))
		done

		# if we had to decompress the patch, delete the temp one
		if [[ -n ${PIPE_CMD} ]] ; then
			rm -f "${PATCH_TARGET}"
		fi

		if [[ ${count} -ge 5 ]] ; then
			echo
			eerror "Failed Patch: ${patchname} !"
			eerror " ( ${PATCH_TARGET} )"
			eerror
			eerror "Include in your bugreport the contents of:"
			eerror
			eerror "  ${STDERR_TARGET}"
			echo
			die "Failed Patch: ${patchname}!"
		fi

		# if everything worked, delete the full debug patch log
		rm -f "${STDERR_TARGET}"

		# then log away the exact stuff for people to review later
		cat <<-EOF >> "${T}/epatch.log"
		PATCH: ${x}
		CMD: ${patch_cmd}
		PWD: ${PWD}

		EOF
		eend 0
	done

	[[ ${SINGLE_PATCH} == "no" ]] && einfo "Done with patching"
	: # everything worked
}

# @FUNCTION: epatch_user
# @USAGE:
# @DESCRIPTION:
# Applies user-provided patches to the source tree. The patches are
# taken from /etc/portage/patches/<CATEGORY>/<P-PR|P|PN>[:SLOT]/, where the first
# of these three directories to exist will be the one to use, ignoring
# any more general directories which might exist as well. They must end
# in ".patch" to be applied.
#
# User patches are intended for quick testing of patches without ebuild
# modifications, as well as for permanent customizations a user might
# desire. Obviously, there can be no official support for arbitrarily
# patched ebuilds. So whenever a build log in a bug report mentions that
# user patches were applied, the user should be asked to reproduce the
# problem without these.
#
# Not all ebuilds do call this function, so placing patches in the
# stated directory might or might not work, depending on the package and
# the eclasses it inherits and uses. It is safe to call the function
# repeatedly, so it is always possible to add a call at the ebuild
# level. The first call is the time when the patches will be
# applied.
#
# Ideally, this function should be called after gentoo-specific patches
# have been applied, so that their code can be modified as well, but
# before calls to e.g. eautoreconf, as the user patches might affect
# autotool input files as well.
epatch_user() {
	[[ $# -ne 0 ]] && die "epatch_user takes no options"

	# Allow multiple calls to this function; ignore all but the first
	local applied="${T}/epatch_user.log"
	[[ -e ${applied} ]] && return 2

	# don't clobber any EPATCH vars that the parent might want
	local EPATCH_SOURCE check base=${PORTAGE_CONFIGROOT%/}/etc/portage/patches
	for check in ${CATEGORY}/{${P}-${PR},${P},${PN}}{,:${SLOT}}; do
		EPATCH_SOURCE=${base}/${CTARGET}/${check}
		[[ -r ${EPATCH_SOURCE} ]] || EPATCH_SOURCE=${base}/${CHOST}/${check}
		[[ -r ${EPATCH_SOURCE} ]] || EPATCH_SOURCE=${base}/${check}
		if [[ -d ${EPATCH_SOURCE} ]] ; then
			EPATCH_SOURCE=${EPATCH_SOURCE} \
			EPATCH_SUFFIX="patch" \
			EPATCH_FORCE="yes" \
			EPATCH_MULTI_MSG="Applying user patches from ${EPATCH_SOURCE} ..." \
			epatch
			echo "${EPATCH_SOURCE}" > "${applied}"
			return 0
		fi
	done
	echo "none" > "${applied}"
	return 1
}

