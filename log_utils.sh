#!/bin/bash
# 
#######################################
# Log utilities for Bash script.
# Arguments:
#   Path to log file.
# Example:
#   source log_utils.sh <path_logfile>
#######################################
readonly LOGFILE="${1:-'script.log'}"

readonly -A LOGLEVELS=(["trace"]=0 ["debug"]=1 ["info"]=2 ["warning"]=3 ["error"]=4 ["critical"]=5)
readonly -A LEVEL_COLORS=(["trace"]=34 ["debug"]=32 ["info"]=36 ["warning"]=33 ["error"]=31 ["critical"]=35)
LEVELNO=${LOGLEVELS["debug"]}

# keyword=type の連想配列。str ならログを "" で囲む。
declare -A KEYWORDS=(["asctime"]="null" ["loglevel"]="null" ["pid"]="null" ["message"]="str")
declare -A extras
declare -A values
readonly DEFAULT_FORMAT="%(asctime)s %(loglevel)s %(message)s"
format="${DEFAULT_FORMAT}"


function is_included() {
	local val="$1"
	local arr=($2)

	for a in "${arr[@]}"; do
		if [[ "${val}" == "${a}" ]]; then
			return 0
		fi
	done

	return 1
}


function set_loglevel() {
    local loglevel="${1}"

    if is_included "${loglevel}" "${!LOGLEVELS[*]}"; then
		LEVELNO=${LOGLEVELS["${loglevel}"]}
    else
        echo "Invalid loglevel: ${loglevel}"
        exit 1
	fi
}


function add_keyword() {
    if [[ -z "${1}" ]]; then
        echo "Argument is empty"
        exit 1
    fi

    if [[ -z "${2}" ]]; then
        local keyword_type="null"
    else
        local keyword_type="${2}"
    fi

    KEYWORDS["${1}"]="${keyword_type}"
}


function check_log_format() {
    local format_arr=(${1})

    for word in "${format_arr[@]}"; do
        keyword=$(echo ${word} | sed -r "s/^.*%\((.*)\)s.*$/\1/g")
        if [[ ! "${!KEYWORDS[@]}" =~ "${keyword}" ]]; then
            echo "Invalid format"
            exit 1
        fi
    done
}


function set_log_format() {
    if [[ -z "${1}" ]]; then
        format="${DEFAULT_FORMAT}"
    else
        format="${1}"
    fi

    check_log_format "${format}"
}


function make_log_text() {
    local format_arr=(${format})
    log_text=""
    for word in "${format_arr[@]}"; do
        word_new=$(echo ${word} | sed -r "s/%\((.*)\)s/\${values[\1]}/g")
        log_text="${log_text} ${word_new}"
    done
}


# ex) log "This is test log" warning
function log() {
    local message=${1}
    local loglevel=${2:-"info"}
    local is_output=1

    if is_included "${loglevel}" "${!LOGLEVELS[*]}"; then
        levelno=${LOGLEVELS["${loglevel}"]}
        is_output=$((LEVELNO > levelno ? 0 : 1))
    else
        echo "Invalid loglevel: ${loglevel} ${message}"
        exit 1
	fi

    if [[ ${is_output} -eq 1 ]]; then
        extras[asctime]=$(date '+%Y-%m-%d %T')
        extras[pid]=$$
        extras[message]="${message}"
        extras[loglevel]="${loglevel^^}"
        for keyword in "${!KEYWORDS[@]}"; do
            if [[ ${KEYWORDS["${keyword}"]} == "str" ]] && ! echo "${extras[${keyword}]}" | grep -q -E "^\".*\"$"; then
                values[${keyword}]="\"${extras[${keyword}]}\""
            else
                values[${keyword}]="${extras[${keyword}]}"
            fi
        done
        
        make_log_text
        log_text=$(eval echo "${log_text}")

        color=${LEVEL_COLORS["${loglevel}"]}
        echo -e "\033[1;${color}m ${log_text} \033[m" # 画面出力用（色付き）
        echo -e "${log_text}" >> "${LOGFILE}" 2>&1 # ファイル出力用
    fi
}
