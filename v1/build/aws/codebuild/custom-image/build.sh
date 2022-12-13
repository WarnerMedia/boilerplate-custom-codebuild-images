#!/bin/sh
#Only dashisms allowed (https://wiki.archlinux.org/index.php/Dash).

echo "Build Started on $(date)"

#------------------------------------------------------------------------
# BEGIN: Declare some functions
#------------------------------------------------------------------------

#Function to check if the Docker build completed successfully.
check_docker_status () {
  #The $? variable always contains the status code of the previously run command.
  #We can either pass in $? or this function will use it as the default value if nothing is passed in.
  local prev=${1:-$?}

  if [ $prev -eq 0 ]; then
    echo "The docker command has succeeded."
    #Set the deployment tag to "true" since the build has succeeded.
    RUN_DEPLOY="true"
  else
    echo "The docker command has failed."
    #Set the deployment tag to "false" since the build has failed.
    RUN_DEPLOY="false"
    export_variable "RUN_DEPLOY"
    #Kill the build script so that we go no further.
    exit 1
  fi
}

#Because CodeBuild doesn't pass environment between phases, putting in a patch.
export_variable () {
  local key="$1"

  export $key

  local temp=$(printenv | grep -w $key)

  echo "$temp" >> /tmp/build
}

#Function for tagging the image that was just built.
tag_docker_image () {
  local local_image_url="$1"
  local custom_image_tag="$2"
  local remote_image_url="$3"

  docker tag "$local_image_url:$custom_image_tag-latest" "$remote_image_url:$custom_image_tag-$GIT_REVISION_TAG"
  check_docker_status $?

  docker tag "$local_image_url:$custom_image_tag-latest" "$remote_image_url:$custom_image_tag-$BUILD_ID_TAG"
  check_docker_status $?

  docker tag "$local_image_url:$custom_image_tag-latest" "$remote_image_url:$custom_image_tag-$VERSION_TAG"
  check_docker_status $?

  docker tag "$local_image_url:$custom_image_tag-latest" "$remote_image_url:$custom_image_tag-latest"
  check_docker_status $?
}

#------------------------------------------------------------------------
# END: Declare some functions
#------------------------------------------------------------------------

#------------------------------------------------------------------------
# BEGIN: Variable Check
#------------------------------------------------------------------------

#Source variables from pre_build section.
. /tmp/pre_build

touch /tmp/build

#------------------------------------------------------------------------
# END: Variable Check
#------------------------------------------------------------------------

#------------------------------------------------------------------------
# BEGIN: Run the build process
#------------------------------------------------------------------------

#Change the directory to the application directory...
if [ -z "$APP_BASE_FOLDER" ]; then
  cd "$CODEBUILD_SRC_DIR/$CUSTOM_IMAGE_PATH/$CUSTOM_IMAGE_TAG" || exit 1
else
  cd "$CODEBUILD_SRC_DIR/$APP_BASE_FOLDER/$CUSTOM_IMAGE_PATH/$CUSTOM_IMAGE_TAG" || exit 1
fi

if [ "$RUN_BUILD" = "true" ]; then

  echo "Checking the docker version..."
  docker version

  if [ -n "$DOCKERHUB_USERNAME" ] && [ -n "$DOCKERHUB_TOKEN" ]; then
    echo "Logging into Docker Hub to increase pull allowance..."
    docker login -u="$DOCKERHUB_USERNAME" -p="$DOCKERHUB_TOKEN"
    check_docker_status $?
  else
    echo "No Docker Hub credentials were set, cannot log in..."
  fi

  echo "Building image from the main Dockerfile..."
  docker build -t "$IMAGE_REPO_NAME:$CUSTOM_IMAGE_TAG-latest" .
  check_docker_status $?

  echo "Tag the image for the primary region..."
  tag_docker_image "$IMAGE_REPO_NAME" "$CUSTOM_IMAGE_TAG" "$FIRST_REGION_DOCKER_URL"

  if [ "$SECOND_REGION_DOCKER_URL" != "NONE" ]; then
    echo "Tag the image for the second region..."
    tag_docker_image "$IMAGE_REPO_NAME" "$CUSTOM_IMAGE_TAG" "$SECOND_REGION_DOCKER_URL"
  else
    echo "The second region wasn't set, so not going to tag anything for that region..."
  fi

  if [ "$THIRD_REGION_DOCKER_URL" != "NONE" ]; then
    echo "Tag the image for the third region..."
    tag_docker_image "$IMAGE_REPO_NAME" "$CUSTOM_IMAGE_TAG" "$THIRD_REGION_DOCKER_URL"
  else
    echo "The third region wasn't set, so not going to tag anything for that region..."
  fi

else
  echo "Docker image already exists for this GIT hash, not rebuilding image..."
  RUN_DEPLOY="false"
fi

#------------------------------------------------------------------------
# END: Run the build process
#------------------------------------------------------------------------

#------------------------------------------------------------------------
# BEGIN: Export variables to share with other shell scripts
#------------------------------------------------------------------------

export_variable "RUN_DEPLOY"

#------------------------------------------------------------------------
# END: Export variables to share with other shell scripts
#------------------------------------------------------------------------
