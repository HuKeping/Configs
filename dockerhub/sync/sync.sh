#! /bin/bash

GREEN="\033[32m"
YELLOW="\033[33m"
RED="\033[31m"
OFF="\033[0m"

function cleanup() {
	echo $CNT images get sync at $(date)

	# Backup the root and other private keys, usually it was under ~/.docker/trust/private
	tar -zcf docker.trust.private.tar.gz -C ~ .docker/trust/private
}
trap cleanup EXIT

# Do some environment checking

SYMBOL_NEXT="next"
SYMBOL_NAME="name"
SYMBOL_RESULTS="results"

NEXT_URL="https://hub.docker.com/v2/repositories/library/?page=1&page_size=10"

IMAGE_TAG="latest"

CNT=0

##############
# IMPORTANT
##############
#
# These variables need to be set.
# We will push image to this specified hub, and you might also need to
# provide some credentials to this hub if it was requried.
#
HUB_DOMAIN="www.example.com"
HUB_NAMESPACE="official"
HUB_USERNAME="official"
HUB_PASSWORD="official"

export DOCKER_CONTENT_TRUST=1
export DOCKER_CONTENT_TRUST_SERVER="https://notary-server:4443"
export DOCKER_CONTENT_TRUST_ROOT_PASSPHRASE="passphrase"
export DOCKER_CONTENT_TRUST_REPOSITORY_PASSPHRASE="passphrase"

# All the pre checking would be list here.
# Add more if necessary.
function pre_check() {
	# docker login to the private hub in case it would require for authentication
	docker login -u $HUB_USERNAME -p $HUB_PASSWORD $HUB_DOMAIN > /dev/null 2>&1
	if [ $? -ne 0 ]; then
		echo -e ${RED}[Error]${OFF} Can not login to $HUB_DOMAIN with $HUB_USERNAME:$HUB_PASSWORD
		exit
	fi
}

pre_check

# This loop will pull all the public images from docker hub within the namespace "library/"
# N.B. we only sync the "latest" tag at present.
while [ $NEXT_URL != null ]
do
	# Get the API respone for a set of images.
	Respones=$(curl -k -s -XGET $NEXT_URL)

	# Retrieve the next url for the API and echo to terminal.
	NEXT_URL=$(echo $Respones | jq .$SYMBOL_NEXT | sed -e 's/^"//' -e 's/"$//')
	echo "The next URL would like to be: $NEXT_URL"

	# Get the length of this result array and then iterate it.
	Length=$(echo $Respones | jq ".$SYMBOL_RESULTS | length")
	for ((i=0;i<$Length;i++));do
		Image=$(echo $Respones | jq ".$SYMBOL_RESULTS[$i].$SYMBOL_NAME" | sed -e 's/^"//' -e 's/"$//')

		# 1. unset the DCT before pull images from docker hub
		unset DOCKER_CONTENT_TRUST
		docker pull $Image:$IMAGE_TAG > /dev/null 2>&1

		# 2. rename the image
		docker tag $Image:$IMAGE_TAG $HUB_DOMAIN/$HUB_NAMESPACE/$Image:$IMAGE_TAG

		# 3. enable the DCT and push image to the private hub and sign
		export DOCKER_CONTENT_TRUST=1
		docker push $HUB_DOMAIN/$HUB_NAMESPACE/$Image:$IMAGE_TAG
		if [ $? -ne 0 ]; then
			echo -e ${RED}[Error]${OFF} Failed to push and sign $HUB_DOMAIN/$HUB_NAMESPACE/$Image:$IMAGE_TAG
		else
			echo -e ${GREEN}[OK]${OFF} $Image:$IMAGE_TAG

			# statistics
			CNT=$((CNT+1))
		fi
	done
done
