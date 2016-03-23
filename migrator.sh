#!/bin/bash

set -o pipefail

# initialization
initialize_migrator() {
	# sets colors for use in output
	GREEN='\e[32m'
	BLUE='\e[34m'
	YELLOW='\e[0;33m'
	RED='\e[31m'
	BOLD='\e[1m'
	CLEAR='\e[0m'

	# pre-configure ok, warning, and error output
	OK="[${GREEN}OK${CLEAR}]"
	INFO="[${BLUE}INFO${CLEAR}]"
	NOTICE="[${YELLOW}!!${CLEAR}]"
	ERROR="[${RED}ERROR${CLEAR}]"
	
	#set Registry endpoint	
	V1_REGISTRY=${1}
	V2_REGISTRY=${2}	

	# trap for ctrl+c
	#trap 'catch_error User exited' SIGINT

	# trap errors
	#trap 'catch_error Non-zero exit code' ERR
}

# generic error catching
catch_error() {
	echo -e "\n${ERROR} ${@}"
	echo -e "${ERROR} Migration from v1 to v2 failed!"
	exit 1
}

catch_push_pull_error() {
	local ACTION="${1}"
	local IMAGE="${2}"
	catch_error "Failed to ${ACTION} ${IMAGE}; aborting"
}

disk_space_enough() {
	local level=`df -h| sed -n '/\/data$/p' | gawk '{print $4}' | sed 's/%//' | sed 's/[0-9;]*.[0-9]*//'`
	if [ -z ${level} ]
	then
		level=`df -h| sed -n '/\/data$/p' | gawk '{print $4}' | sed 's/%//' | sed 's/[0-9]*//'`
		if [ -z ${level} ]
		then
			catch_error "error in parsing disk space level:${level}"
		fi
	fi
	local space=`df -h| sed -n '/\/data$/p' | gawk '{print $4}' | sed 's/%//' | sed 's/[A-Z]//'`	
	case ${level} in
		K|M)
			return 0
			;;
		G)
			local ret=`echo "${space}<100" | bc`
			if [ ${ret} -eq 1 ]
			then
				return 0
			else
				return 1
			fi
			;;
		T)
			return 1
			;;
		*)
			return 0
			;;
	esac	
}


# verify requirements met for script to execute properly
verify_ready() {
	# verify v1 registry variable has been passed
	if [ -z "${V1_REGISTRY}" ]
	then
		catch_error "${BOLD}V1_REGISTRY${CLEAR} environment variable required"
	fi

	# verify v2 registry variable has been passed
	if [ -z "${V2_REGISTRY}" ]
	then
		catch_error "${BOLD}V2_REGISTRY${CLEAR} environment variable required"
	fi
	
	# verify docker daemon is accessible
	if ! $(docker info > /dev/null 2>&1)
	then
		catch_error "Docker daemon not accessible. Is the Docker socket shared into the container as a volume?"
	fi
	
	# verify the local disk space >=100G
	disk_space_enough
	local ret=$?
	if [ ${ret} -eq 0 ]
	then 
		catch_error "Disk Space is less than 100G"
	fi
}

query_images(){
	#Init empty list
	REPO_V1_LIST=""
	REPO_V2_LIST=""
	REPO_ACTUAL_LIST=""
	USER_LIST=""

	#Getting V1_REGISTRY images_list
	echo -e "\n${INFO} Getting a list of images from ${V1_REGISTRY}"
	local REPO_LIST=$(curl http://${V1_REGISTRY}/v1/search?q= | jq -r '.results | .[] | .name') || catch_error "v1 curl => API failure"
	local flag=0
	for i in ${REPO_LIST}
	do
		# get list of tags for image i
		local IMAGE_TAGS=$(curl http://${V1_REGISTRY}/v1/repositories/${i}/tags | jq -r 'keys | .[]') || catch_error "v1 curl => API failure"
		# loop through tags to create list of full image names w/tags
		for j in ${IMAGE_TAGS}
		do
			if [ ${flag} -eq 0 ]
			then
				REPO_V1_LIST="${i}:${j}"
				flag=$((flag+1))
			else
				# add image to list
				REPO_V1_LIST="${REPO_V1_LIST} ${i}:${j}"
			fi
		done
	done
	echo -e "${OK} Successfully retrieved v1 registry list of Docker images from ${V1_REGISTRY}"
	#echo -e "${REPO_V1_LIST}"

:<<BLOCK
	for i in ${REPO_V1_LIST}
	do
		`echo ${i} >> input`
	done
BLOCK
	
	#Getting V2_REGISTRY images_list	
	echo -e "\n${INFO} Getting a list of images from ${V2_REGISTRY}"
	REPO_LIST=$(curl http://${V2_REGISTRY}/v2/_catalog | jq -r '.repositories | .[]') || catch_error "v2 curl => API failure"
	flag=0
	for i in ${REPO_LIST}
	do
		# get list of tags for image i
		IMAGE_TAGS=$(curl http://${V2_REGISTRY}/v2/${i}/tags/list | jq -r '.tags | .[]') || catch_error "v2 curl => API failure"
		# loop through tags to create list of full image names w/tags
		for j in ${IMAGE_TAGS}
		do
			if [ ${flag} -eq 0 ]
			then
				REPO_V2_LIST="${i}:${j}"
				flag=$((flag+1))
			else
				# add image to list
				REPO_V2_LIST="${REPO_V2_LIST} ${i}:${j}"
			fi	 
		done
	done
	echo -e "${OK} Successfully retrieved v2 registry list of Docker images from ${V1_REGISTRY}"

:<<BLOCK
	for i in ${REPO_V2_LIST}
	do
		`echo ${i} >> output`
	done
BLOCK

	#REPO_ACTUAL_LIST
	flag=0
	local user_flag=0
	for i in ${REPO_V1_LIST}
	do
		local trag=0
		for j in ${REPO_V2_LIST}
		do
			if [ ${i} = ${j} ]
			then
				trag=$((trag+1))
				break
			fi
		done
		if [ ${trag} -eq 1 ]
		then
			continue
		fi
		
		if [ ${flag} -eq 0 ]
		then
			flag=$((flag+1))
			REPO_ACTUAL_LIST="${i}"
		else
			REPO_ACTUAL_LIST="${REPO_ACTUAL_LIST} ${i}"
		fi
		
		local user=`echo "${i}" | awk -F'/' '{print $1}'`
		for k in ${USER_LIST}
		do
			if [ ${k} = ${user} ]
			then
				trag=$((trag+1))
				break
			fi
		done
		if [ ${trag} -eq 0 ]
		then
			if [ ${user_flag} -eq 0 ]
			then
				user_flag=$((user_flag+1))
				USER_LIST="${user}"
			else
				USER_LIST="${USER_LIST} ${user}"
			fi
		fi
	done
	echo -e "${OK} Successfully retrieved actual list to be Migrated"

:<<BLOCK
	#echo -e "REPO_ACTUAL_LIST\n"
	for i in ${REPO_ACTUAL_LIST}
	do
		`echo ${i} >> result`
	done
BLOCK

:<<BLOCK
	echo -e "USER_LIST\n${USER_LIST}\n"
	for i in ${USER_LIST}
	do
		echo ${i}
	done
BLOCK
}

show_image_list() {
	#Show V1_REGISTRY images list
	echo -e "\n${INFO} Full list of images from ${V1_REGISTRY} to be migrated:"
	# output list with v1 registry name prefix added
	for i in ${REPO_V1_LIST}
	do
		echo ${V1_REGISTRY}/${i}
	done
	echo -e "${OK} End full list of images from ${V1_REGISTRY}"

	#Show V2_REGISTRY images list
	echo -e "\n${INFO} Full list of images exist in ${V2_REGISTRY}"
	# output list with v1 registry name prefix added
	for i in ${REPO_V2_LIST}
	do
		echo ${V2_REGISTRY}/${i}
	done
	echo -e "${OK} End full list of images from ${V2_REGISTRY}"

	#Show Actual images to be Migrated
	echo -e "\n${INFO} Acutal list of images to be Migrated from ${V1_REGISTRY} to ${V2_REGISTRY}"
	# output list with v1 registry name prefix added
	for i in ${REPO_ACTUAL_LIST}
	do
		echo ${V1_REGISTRY}/${i}
	done
	echo -e "${OK} End full list of images to be Migrated"
	
	#Show users
	echo -e "\n${INFO} Acutal list of users to be Migrated from ${V1_REGISTRY} to ${V2_REGISTRY}"	
	for i in ${USER_LIST}
	do
		echo ${i}
	done
	echo -e "${OK} End full list of users"
}

# push/pull image
push_pull_image() {
	# get action and image name passed
	ACTION="${1}"
	IMAGE="${2}"

	# check the action and act accordingly
	case ${ACTION} in
		push)
			# push image
			echo -e "${INFO} Pushing ${IMAGE}"
			(docker push ${IMAGE} && echo -e "${OK} Successfully ${ACTION}ed ${IMAGE}\n") || catch_push_pull_error "push" "${IMAGE}"
			;;
		pull)
			# pull image
			echo -e "${INFO} Pulling ${IMAGE}"
			(docker pull ${IMAGE} && echo -e "${OK} Successfully ${ACTION}ed ${IMAGE}\n") || catch_push_pull_error "pull" "${IMAGE}"
			;;
	esac
}

retag_image() {
	# get source and destination image names passed
	SOURCE_IMAGE="${1}"
	DESTINATION_IMAGE="${2}"

	# retag image
	(docker tag ${SOURCE_IMAGE} ${DESTINATION_IMAGE} && echo -e "${OK} ${SOURCE_IMAGE} > ${DESTINATION_IMAGE}") || catch_error "retag failure for ${SOURCE_IMAGE} to ${DESTINATION_IMAGE}"
}

#:<<BLOCK
#Migrating from V1_REGISTRY to V2_REGISTRY
pull_images(){
	echo -e "\n${INFO} Starting to Migrate images from ${V1_REGISTRY} to ${V2_REGISTRY}"
	for i in ${USER_LIST}
	do
		local ADD_PULL_LIST=""
		for j in ${REPO_ACTUAL_LIST}
		do
			local user=`echo "${j}" | awk -F'/' '{print $1}'`
			if [ ${user} != ${i} ]
			then
				continue
			fi
			disk_space_enough
			local ret=$?
			if [ $ret -eq 1 ]
			then
				ADD_PULL_LIST="${ADD_PULL_LIST} ${j}"
				push_pull_image "pull" "${V1_REGISTRY}/${j}"	
			else
				echo -e "\n${NOTICE} Disk space is reaching the limit,Starting deleting local cached images"
				
				for k in ${ADD_PULL_LIST}
				do
					retag_image "${V1_REGISTRY}/${k}" "${V2_REGISTRY}/${k}"
					push_pull_image "push" "${V2_REGISTRY}/${k}"
				done
				for k in ${ADD_PULL_LIST}
				do
					docker rmi -f ${V1_REGISTRY}/${k} || catch_error "docker rmi failure for ${V1_REGISTRY}/${k}"
					docker rmi -f ${V2_REGISTRY}/${k} || catch_error "docker rmi failure for ${V2_REGISTRY}/${k}"
				done
				ADD_PULL_LIST="${j}"
				push_pull_image "pull" "${V1_REGISTRY}/${j}"
			fi
		done	
		for z in ${ADD_PULL_LIST}
		do
			retag_image "${V1_REGISTRY}/${z}" "${V2_REGISTRY}/${z}"
			push_pull_image "push" "${V2_REGISTRY}/${z}"
		done


		for z in ${ADD_PULL_LIST}
		do
			docker rmi -f ${V1_REGISTRY}/${z} || catch_error "docker rmi failure for ${V1_REGISTRY}/${z}"
			docker rmi -f ${V2_REGISTRY}/${z} || catch_error "docker rmi failure for ${V2_REGISTRY}/${z}"
		done

	done
}
#BLOCK

migration_complete_judge(){
	local REPO_LIST=$(curl http://${V2_REGISTRY}/v2/_catalog | jq -r '.repositories | .[]') || catch_error "v2 curl => API failure"
	local flag=0
	local REPO_V2_FINAL_LIST=""
	for i in ${REPO_LIST}
	do
		# get list of tags for image i
		local IMAGE_TAGS=$(curl http://${V2_REGISTRY}/v2/${i}/tags/list | jq -r '.tags | .[]') || catch_error "v2 curl => API failure"
		# loop through tags to create list of full image names w/tags
		for j in ${IMAGE_TAGS}
		do
			if [ ${flag} -eq 0 ]
			then
				REPO_V2_FINAL_LIST="${i}:${j}"
				flag=$((flag+1))
			else
				# add image to list
				REPO_V2_FINAL_LIST="${REPO_V2_FINAL_LIST} ${i}:${j}"
			fi
		done
	done
	
	local trag=0
	for i in ${REPO_V1_LIST}
	do
		flag=0
		for j in ${REPO_V2_FINAL_LIST}
		do
			if [ ${i} = ${j} ]
			then
				flag=$((flag+1))
				break
			fi
		done
				
		if [ ${flag} -eq 0 ]
		then
			trag=$((trag+1))
			break
		fi
	done
	
	if [ ${trag} -eq 1 ]
	then
		echo -e "\n${ERROR} Migration from v1 to v2 not complete!"
	else
		echo -e "\n${OK} Migration from v1 to v2 complete!"
	fi
	
}
	
:<<BLOCK
echo_test() {
	echo -e "${OK}invalid response"
	echo -e "${INFO}"
	echo -e "${NOTICE}"
	echo -e "${ERROR}"
	catch_error "fail to push images"
}
BLOCK

# main function
main() {
	initialize_migrator "${1}" "${2}"
	verify_ready
	query_images
	show_image_list
	pull_images
	migration_complete_judge
}

main "$@"


