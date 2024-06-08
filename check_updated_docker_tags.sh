#!/bin/bash
#
# checks for container updates which uses fixed tag name
# all the containers which uses the 'latest' tag are handled by https://github.com/containrrr/watchtower
#
# dependency: regctl		: https://github.com/regclient/regclient
#             send_mail.py
#
# inspired by: https://github.com/mag37/dockcheck
#
# PLI, 2023-10-01
# 
#-----------------------------------------------------------------------------------------------------

# install dir
BASE=/opt/tools

# https://github.com/regclient/regclient
regbin=$(which regctl)

# exclude images
Exclude="watchtower"

EXCLUDE_TAGS="latest|alpine|testing|webauthn|arm|amd|sha|build|^rc|rc-|-rc|jammy|-ubi|-noble|[a-f0-9]{20,}"


#-----------------------------------------------------------------------------------------------------

build_line() {
    NR=$1

    # add leading charactes
    ((NR += 20))

    for ((i=0; i<$NR; i++)) ; do
	printf "="
    done
    echo
}


run_check() {
    echo "INFO: excluded images: $Exclude"
    printf "INFO: getting images : "
    IMAGES=$(docker ps --format '{{.Names}} {{.Image}}' | egrep -v ":latest|:lts" | awk '{print $1}')

    echo "$IMAGES" | tr '\n' ',' | sed -e 's/,$//'
    echo
    echo

    IFS=',' read -r -a Excludes <<< "$Exclude" ; unset IFS

    for i in $IMAGES; do
	for e in "${Excludes[@]}" ; do [[ "$i" == "$e" ]] && continue 2 ; done 

	echo "INFO: checking $i ..."
	RepoUrl=$(docker inspect "$i" --format='{{.Config.Image}}')
	LocalHash=$(docker image inspect "$RepoUrl" --format '{{.RepoDigests}}')

	echo "INFO:  RepoUrl   : $RepoUrl"
	echo "INFO:  LocalHash : $LocalHash"

    # get latest image tag
    LATEST_TAG=$($regbin tag ls "$RepoUrl" | egrep -v "$EXCLUDE_TAGS" | sort -n -t "." -k1,1 -k2,2 -k3,3 | tail -1 | sed -e 's,^v,,g')


    if RegHash=$($regbin image digest --list "$RepoUrl" 2>/dev/null) ; then
	if [[ "$RepoUrl" =~ $LATEST_TAG ]]; then
	    NoUpdates+=("$i:$LATEST_TAG"); 
	else 
	    GotUpdates+=("$i:$LATEST_TAG"); 
	fi
    fi
    echo
    done

    LEN=$(echo ${NoUpdates[@]} | wc -c)


    build_line $LEN
    echo "INFO: NoUpdates  : ${NoUpdates[@]}"
    build_line $LEN
    echo

    if [ ${#GotUpdates[@]} -gt 0 ]; then
	build_line $LEN
	echo "INFO: GotUpdates : ${GotUpdates[@]}"
	build_line $LEN
	echo
    fi
}

check_regctl() {
    if [ -z "$regbin" ]; then
	echo "WARN: regclient binary is missing, trying to download"

	case "$(uname --machine)" in
	    x86_64|amd64) architecture="amd64" ;;
	    arm64|aarch64) architecture="arm64";;
	    *) echo "Architecture not supported, exiting." ; exit 1;;
	esac

	regclient="https://github.com/regclient/regclient/releases/latest/download/regctl-linux-$architecture"
	OUTBIN=/tmp/regctl
        wget -q $regclient -O $OUTBIN 
	if [ $? -eq 0 ]; then
	    echo "WARN: $OUTBIN downloaded. Pls. install into a directory which is in the search path"
	    chmod +x $OUTBIN; 
	    regbin="$OUTBIN"
	else
	    echo "ERROR: could not download regctl"
	    exit 2
	fi
    else
	echo "INFO: $regbin ok"
    fi
}


notify_email() {
    LOG="$1"

    if [ $(grep -c GotUpdates $LOG) -ne 0 ]; then
	echo "INFO: new container images found, sending notification"
	cat $LOG | $BASE/send_mail.py -p -s "New container version on $(uname -n) found!" -m -
    fi
}

#-----------------------------------------------------------------------------------------------------
#

date

# check for helper script
check_regctl

# run update check
TMPLOG=$(mktemp -t .container_check.XXXXXX)
run_check | tee $TMPLOG

# notify, if updates found
notify_email $TMPLOG
rm -f $TMPLOG

#

