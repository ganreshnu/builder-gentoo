Print() {
	local -r bracketColor="247" labelColor="$1" label="$2"; shift 2
	printf "$(tput setaf $bracketColor)[$(tput sgr0)$(tput setaf $labelColor)%s$(tput sgr0)$(tput setaf $bracketColor)]$(tput sgr0) %s\n" "$label" "$*"
}
ExpectArg() {
	local -n v="$1"; shift
	local -n c="$1"; shift
	local name="${1%%=*}"
	c=0
	if [[ "$1" == "${name}" ]]; then
		[[ $# < 2 ]] && >&2 Print 1 error "$1 expects a value." && return 1
		v="$2"
		c=1
		return 0
	fi
	v="${1#*=}"
}
SetupRoot() {
	tar --directory="${args[fsroot]}" --extract --file=/root/fsroot-empty.tar.xz
}
Define() {
	IFS=$'\n' read -r -d '' ${1} ||true
}
