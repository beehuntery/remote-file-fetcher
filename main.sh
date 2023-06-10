#!/bin/bash
# 
#######################################
# Fetch remote files with redundancy support.
# Example:
#   bash main.sh [-h] [-v] [-s SECTION]
#######################################
readonly VERSION="1.1.3"

set -o pipefail

cd $(dirname $0)

help_text=$(cat <<-EOS
Fetch remote files with redundancy support.
Usage: bash main.sh [-v] [-s SECTION]
 -h, --help | print help text
 -v, --version | print version information
 -s, --section=SECTION | load the specified section from config.sh
EOS
)

# parse args
while [[ $# -gt 0 ]]; do
	case $1 in
		-h | --help)
			echo "${help_text}"
			exit 0
			;;
		-v | --version)
			echo "Remote File Fetcher ${VERSION}"
			exit 0
			;;
		-s | --section=*)
			if [[ "${1}" =~ ^--section= ]]; then
				section=$(echo ${1} | sed -e 's/^--section=//')
				source $(dirname $0)/config.sh "${section}"
			elif [[ -z "${2}" ]] || [[ "${2}" =~ ^-+ ]]; then
				echo "'section' requires an argument"
				exit 1
			else
				section="${2}"
				source $(dirname $0)/config.sh "${section}"
				shift
			fi
			;;
		*)
			echo "Invalid args"
			exit 1
			;;
	esac
	shift
done


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


function check_config() {
	source $(dirname $0)/valid_vars.sh

	if ! is_included "${MODE}" "${_MODE[*]}"; then
		echo "Invalid mode: Valid mode are ${_MODE[@]}"
		exit 1
	fi

	if [[ "${#FILENAMES}" -eq 0 ]]; then
		echo "FILENAMES is empty"
		exit 1
	fi

	function _check_file() {
		local path="${1}"
		if [[ ! -e "${path}" ]]; then
			echo "${path}: No such file"
			exit 1
		fi
	}

	function _check_directory() {
		local path="${1}"
		if [[ ! -d "${path}" ]]; then
			echo "${path}: No such directory"
			exit 1
		fi
	}

	_check_file "${IDENTITY_FILE_CLIENT}"
	_check_file "${IDENTITY_FILE_SERVER}"

	_check_directory "${PATH_SAVE}"
	if [[ ${IS_DECOMPRESS} -eq 1 ]]; then
		_check_directory "${PATH_DECOMPRESS}"
	fi
	_check_directory "${PATH_FINISHED}"
	_check_directory "${PATH_SCRIPT_LOG}"

	unset -f _check_file
	unset -f _check_directory
}

check_config

source $(dirname $0)/log_utils.sh "${PATH_SCRIPT_LOG}/remote-file-fetcher_${section}_$(date '+%Y%m%d').log"

set -u


function log_setting() {

	add_keyword "role" "str"
	add_keyword "retry" ""
	add_keyword "destination" "str"
	add_keyword "filename" "str"
	add_keyword "files" ""

	extras["role"]=""
	extras["retry"]=0
	extras["destination"]=""
	extras["filename"]=""
	extras["files"]="${num_finished_files}/${NUM_TARGET_FILES}"

	set_log_format "%(asctime)s %(loglevel)s PID=%(pid)s role=%(role)s retry=%(retry)s dst=%(destination)s fname=%(filename)s files=%(files)s msg=%(message)s"
	set_loglevel "${LOGLEVEL}"
}


function start_script() {
	# Ctrl+C で中断したときなどに発火
	trap "finish_script" HUP INT QUIT TERM

	# 実行時間計測用
	start_time=$(date +%s)

	# 取得完了したファイルはここに記載
	finished_list="${PATH_FINISHED}/finished_list_${date_hour}"
	touch "${finished_list}"
	num_finished_files=$(wc -l < ${finished_list})

	log_setting

	log "Start script (mode: ${MODE})"
}


function decide_act_sby() {
	log "Start decide_act_sby" trace

	index_act=$((${1} % ${#IP_CLIENTS[@]}))
	if printf '%s\n' $(hostname --all-ip-address) | grep -qx "${IP_CLIENTS[${index_act}]}"; then
		extras["role"]="act"
	else
		extras["role"]="sby"
	fi
	log "Role changed"

	log "End decide_act_sby" trace
}


function check_file_exists() {
	log "Start check_file_exists $1" trace

	local fname="${1}"

	log "Check if file exists"
	for ip_client in "${IP_CLIENTS[@]}"; do
		extras["destination"]="${ip_client}"
		if printf '%s\n' $(hostname --all-ip-address) | grep -qx "${ip_client}"; then
			log "Check host: myself" debug
			local res=$(find ${PATH_SAVE} -name ${fname} 2>/dev/null)
		else
			log "Check host: ${ip_client}" debug
			local res=$(ssh -i ${IDENTITY_FILE_CLIENT} ${USER_CLIENT}@${ip_client} "find ${PATH_SAVE} -name ${fname} 2>/dev/null")
		fi

		if [[ $? -ne 0 ]]; then # 予期せぬエラーの場合
			log "Unexpected error (SSH connection error is one possible cause)" error
			exit 1
		elif [[ -z "${res}" ]]; then # 存在しない場合
			log "Not found" debug
		else # 存在する場合
			fname_full=$(basename ${res})
			extras["filename"]="${fname_full}"
			log "Already exists"
			extras["destination"]=""

			log "End check_file_exists $1" trace

			return 0
		fi
	done

	extras["destination"]=""
	log "Not found in all clients"

	log "End check_file_exists $1" trace

	return 1
}


function add_finished_file() {
	log "Start add_finished_file $1" trace

	local fname_full="${1}"

	if ! grep -q "${fname_full}" "${PATH_FINISHED}/finished_list_${date_hour}"; then
		echo "${fname_full}" >> "${PATH_FINISHED}/finished_list_${date_hour}"
	fi

	num_finished_files=$(wc -l < ${finished_list})
	extras["files"]="${num_finished_files}/${NUM_TARGET_FILES}"

	log "End add_finished_file $1" trace
}


function check_connection() {
	log "Start check_connection" trace

	log "Check connection"
	for ip_server in "${IP_SERVERS[@]}"; do
		extras["destination"]="${ip_server}"
		if [[ "${MODE}" == "sftp" ]]; then
			echo "exit" | sftp -i ${IDENTITY_FILE_SERVER} -oConnectTimeout=3 ${USER_SERVER}@${ip_server}
		elif [[ "${MODE}" == "scp" ]]; then
			ssh -i ${IDENTITY_FILE_SERVER} -oConnectTimeout=3 ${USER_SERVER}@${ip_server} "exit"
		fi

		if [[ $? -ne 0 ]]; then
			log "Connection failure" warning
		else
			log "Connection success" debug
			ip_connect=${ip_server}

			log "End check_connection" trace

			return 0
		fi
	done

	extras["destination"]=""

	log "End check_connection" trace

	return 1
}


function list() {
	log "Start list" trace

	local fname="${1}"
	local ip="${2}"

	if [[ "${MODE}" == "sftp" ]]; then
		local res=$(echo "ls ${PATH_SRC}/${fname}" | sftp -i ${IDENTITY_FILE_SERVER} ${USER_SERVER}@${ip} 2>&1)
		local err_msg="not found"
	elif [[ "${MODE}" == "scp" ]]; then
		local res=$(ssh -i ${IDENTITY_FILE_SERVER} ${USER_SERVER}@${ip} "LANG=C ls ${PATH_SRC}/${fname}" 2>&1)
		local err_msg="No such file or directory"
	fi

	if echo "${res}" | grep -q "${err_msg}"; then
		log "Not found" error
		log "End list" trace
		return 1
	elif echo "${res}" | grep -q "Permission denied"; then
		log "Permission denied" error
		log "End list" trace
		return 1
	else
		if [[ "${MODE}" == "sftp" ]]; then
			res=($(echo "${res}" | sed "1,2d")) # ファイル一覧のみ配列として取り出す
		elif [[ "${MODE}" == "scp" ]]; then
			res=($(echo "${res}"))
		fi
		num_matched=${#res[@]}
		NUM_TARGET_FILES=$((NUM_TARGET_FILES+num_matched-1))
		extras["files"]="${num_finished_files}/${NUM_TARGET_FILES}"
		log "${num_matched} files matched"

		fnames_full=()
		for path in "${res[@]}"; do
			fnames_full+=($(basename ${path}))
		done

		log "End list" trace

		return 0
	fi
}


function fetch() {
	log "Start fetch $1 $2" trace

	local fname="${1}"
	local ip="${2}"

	log "Fetching ..."
	if [[ "${MODE}" == "sftp" ]]; then
		local res=$(echo "get ${PATH_SRC}/${fname} ${PATH_SAVE}" | sftp -i ${IDENTITY_FILE_SERVER} ${USER_SERVER}@${ip} 2>&1)
	elif [[ "${MODE}" == "scp" ]]; then
		local res=$(scp -i ${IDENTITY_FILE_SERVER} ${USER_SERVER}@${ip}:${PATH_SRC}/${fname} ${PATH_SAVE} 2>&1)
	fi

	if echo "${res}" | grep -q "Permission denied"; then
		log "Permission denied" error
		log "End fetch $1 $2" trace
		return 1
	elif echo "${res}" | grep -q "Fetching" || [[ -z "${res}" ]]; then
		log "End fetch $1 $2" trace
		return 0
	elif echo "${res}" | grep -q "not found"; then
		log "Not found" error
		log "End fetch $1 $2" trace
		return 1
	else
		log "Unexpected error" error
		exit 1
	fi
}


function decompress() {
	log "Start decompress $1 $2" trace

	local src=${1}
	local dist=${2}

	local fname=$(basename ${src})
	local host=${fname%%_*}
	local app=$(echo ${fname#*_} | sed -e "s/\.log.*$//")

	log "Decompressing ..."
	local res=$(gzip --decompress ${src} -c 2>&1 > ${dist})
	if [[ -n ${res} ]]; then
		log "Decompress failure: ${res}" error
		log "End decompress $1 $2" trace
		return 1
	else
		log "End decompress $1 $2" trace
		return 0
	fi
}


function fetch_and_decompress() {
	log "Start fetch_and_decompress" trace

	if check_connection; then
		if list ${fname} ${ip_connect}; then
			for fname_full in "${fnames_full[@]}"; do
				extras["filename"]="${fname_full}"
				if fetch ${fname_full} ${ip_connect}; then
					if [[ ${IS_DECOMPRESS} -ne 1 ]]; then
						add_finished_file ${fname_full}
					fi

					log "Fetch success"
					
					# add readable permission
					chmod +r "${PATH_SAVE}/${fname_full}"
					
					if [[ ${IS_DECOMPRESS} -eq 1 ]]; then
						if decompress "${PATH_SAVE}/${fname_full}" "${PATH_DECOMPRESS}/${fname_full%.*}"; then
							add_finished_file ${fname_full}
							log "Decompress success: file size is $(ls -lh ${PATH_DECOMPRESS}/${fname_full%.*} | awk '{ print $5 }')"
						fi
					fi
				fi
			done
		fi
		extras["destination"]=""
	else
		log "All connections failure" error
	fi

	log "End fetch_and_decompress" trace
}


function is_complete_fetch_files() {
	log "Start is_complete_fetch_files" trace

	if [[ ${num_finished_files} -lt ${NUM_TARGET_FILES} ]]; then
		log "End is_complete_fetch_files" trace
		return 1
	elif [[ ${num_finished_files} -eq ${NUM_TARGET_FILES} ]]; then
		log "End is_complete_fetch_files" trace
		return 0
	else
		log "Unexpected number of files were transferred" warning
		exit 1
	fi
}


function finish_script() {
	log "Finished script"

	# 実行時間計測
	end_time=$(date +%s)
	log "Execution time: $((end_time-start_time)) s"

	exit 0
}


function main() {
	log "Start main" trace

	for fname in "${FILENAMES[@]}"; do
		extras["filename"]="${fname}"
		if check_file_exists ${fname}; then
			add_finished_file ${fname_full}
		else
			# TODO
			# 取得できていないのにファイルに記載がある場合は消す

			fetch_and_decompress
		fi

		extras["filename"]=""
		if is_complete_fetch_files; then
			log "All files were fetched"
			rm "${finished_list}"
			log "End main" trace
			finish_script
		fi
	done

	log "End main" trace
}


start_script

NUM_CLIENTS=${#IP_CLIENTS[@]}
for n in $(seq 0 1 $((MAX_RETRIES*NUM_CLIENTS))); do
	extras["retry"]=$((n/NUM_CLIENTS))

	decide_act_sby ${n}

	if [[ "${extras[role]}" == "act" ]]; then
		main
	else
		log "Sleep ${TIME_SWITCH_ROLE} s ..."
		sleep ${TIME_SWITCH_ROLE}
	fi
done

finish_script
