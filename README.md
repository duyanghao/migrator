docker/migrator
=================

Tool to migrate Docker images from v1 registry to a v2 registry

## Usage

```
bash migrator.sh V1_REGISTRY V2_REGISTRY
```

#### Required

  * `V1_REGISTRY` - DNS hostname of your v1 registry (Do not include `http://`,192.168.128.128:5000 for example)
  * `V2_REGISTRY` - DNS hostname of your v2 registry (Do not include `http://`,192.167.23.334:5000 for example)


## Prerequisites
This migration tool assumes the following:

  * You have a v1 registry and you are planning on migrating to a v2 registry
  * The new v2 registry is running using a different DNS name as the v1 registry
  * The docker engine has enough disk space(more than 1T free)
  * The docker engine must run with the option "--insecure-registry V1_REGISTRY --insecure-registry V2_REGISTRY"
  * The docker engine version must be at least 1.6(>=1.6)
  * bc,sed and gawk tools are needed in running environments	
  * The name of docker images must be namespace/repo:tag, namespace,repo and tag are all to be required!!!
  * During the Migration,it is suggested that there is no push to neither v1 registry nor v2 registry 

It is suggested that you run this container on a Docker engine that is located near your registry as you will need to pull down images from your v1 registry and push them to the v2 registry to complete the migration.  This also means that you will need enough disk space on your local Docker engine to temporarily store images.

## How Migration Works
The migration occurs using an automated script. Running using the above usage will work as expected.

1. Init and Verify
	1. Init the arguments and display information
	 	* Init the V1_REGISTRY and V2_REGISTRY
	  * Init the display information(something about the color:INFO ERROR OK)
	2. Verify the arguments,disk sapce and docker engine
2. Query the v1 registry for a list of all repositories
3. With the list of images, query the v1 registry for all tags for each repository.This becomes the list of all images with tags that exist in v1 registry
4. Do the same as step 2 and 3 to get the list of all images with tags that exist in v2 registry
5. Exclude the images that exist in v2 registry from v1 registry image list to get the actual image list to be Migrated
6. Get the user list from actual image list
7. Using a Docker engine, pull images from the actual image list,tag images,push images to the v2 registry and delete local cached images
8. Migrating scheme:Loop through all images in the same namespace(user) before deleting locally
  * Check the local disk space and ensure that 100G amount of disk space is free before removing the currently cached images locally
9. Verify whether or not the migration was successful(completed!) 
  * By check whether v1 registry images all exist in v2 registry


## Logging Migration Output
If you need to log the output from migrator, add `>> migration.log 2>&1 ` to the end of the command shown above to capture the output to a file of your choice.
