#!/bin/bash
# 
#######################################
# Config file of Remote File Fetcher.
# Arguments:
#   Section name.
# Example:
#   source config.sh <section>
#######################################
case "$1" in


  "sample")
    readonly MODE="sftp"

    # 取得対象
    FILENAMES=("foo*.txt.gz" "bar*.gz" "samplefile.csv.gz")
    NUM_TARGET_FILES=10

    # active/standby 設定
    readonly TIME_SWITCH_ROLE=600 # seconds
    readonly IP_CLIENTS=("192.168.1.1" "192.168.1.2") # First IP is active
    readonly MAX_RETRIES=5

    # クライアント間接続用情報
    readonly USER_CLIENT="ubuntu"
    readonly IDENTITY_FILE_CLIENT="/home/ubuntu/.ssh/id_ed25519"

    # クライアント - サーバ間接続用情報
    readonly USER_SERVER="centos"
    readonly IP_SERVERS=("10.0.0.10" "10.0.0.20")
    readonly IDENTITY_FILE_SERVER="/home/ubuntu/.ssh/id_rsa"
    readonly PATH_SRC="log/sample" # ここからファイル取得する
    readonly PATH_SAVE="/home/ubuntu/sample"

    # 解凍用設定
    readonly IS_DECOMPRESS=1 # set 1 to enable
    readonly PATH_DECOMPRESS="/home/ubuntu/sample/decompress"

    # 取得完了ファイルリストの保存先
    readonly PATH_FINISHED="/home/ubuntu/sample/finished"

    # このスクリプトのログの保存先
    readonly PATH_SCRIPT_LOG="/home/ubuntu/sample/script_log"
    readonly LOGLEVEL="info"
    ;;


  *)
    echo "No such section"
    exit 1
    ;;


esac
