#!/bin/sh
#Only dashisms allowed (https://wiki.archlinux.org/index.php/Dash).

echo "Pre-Build Started on $(date)"

#------------------------------------------------------------------------
# BEGIN: Set some default variables and files
#------------------------------------------------------------------------

#Set a default image tag.
DEFAULT_IMAGE_TAG="latest"
RUN_BUILD="false"
UPDATE_METADATA_FILE="false"

#Create a file for transporting variables to other phases.
touch /tmp/pre_build

#------------------------------------------------------------------------
# END: Set some default variables and files
#------------------------------------------------------------------------

#------------------------------------------------------------------------
# BEGIN: Declare some functions
#------------------------------------------------------------------------

#Build a docker URL...
build_docker_url () {
  local account_id="$1"
  local region="$2"
  local image_repo="$3"

  echo "$account_id.dkr.ecr.$region.amazonaws.com/$image_repo"
}

check_docker_image () {
  local repository="$1"
  local current_tag="${2:-$DEFAULT_IMAGE_TAG}"
  local region="${3:-$AWS_REGION}"

  local ecr_tag=$(aws --region "$region" ecr describe-images --repository-name "$repository" --image-ids imageTag="$current_tag" --output text --query 'imageDetails[].imageTags[?contains(@, `version-`)]')
  check_status $? "AWS CLI"

  echo "Check if the \"$current_tag\" tag is equal to the \"$ecr_tag\" tag..."
  if [ "$current_tag" = "$ecr_tag" ]; then
    echo "An image already exists in the ECS Repository with the \"$ecr_tag\" tag in the \"$region\" region."
    RUN_BUILD="false"
    UPDATE_METADATA_FILE="true"
    exit 1
  else
    echo "No image exists in the ECS Repository with the \"$current_tag\" tag in the \"$region\" region, so the image will be built."
    RUN_BUILD="true"
    UPDATE_METADATA_FILE="false"
  fi
}

check_cmd_exists () {
  local cmd="$1"

  if exists $cmd; then
    echo "The command \"$cmd\" is installed."
  else
    echo "The command \"$cmd\" is not installed."
    exit 1
  fi
}

check_variable () {
  local variable="$1"
  local message="$2"

  if [ -z "$variable" ]; then
    echo "The $message was not retrieved successfully."
    exit 1
  else
    echo "The $message is: $variable"
  fi
}

#Check if the AWS command was successful.
check_status () {
  #The $? variable always contains the status code of the previously run command.
  #We can either pass in $? or this function will use it as the default value if nothing is passed in.
  local prev=${1:-$?}
  local command="$2"

  if [ $prev -eq 0 ]; then
    echo "The $command command has succeeded."
    #Set the build tag to "true" since the build has succeeded.
    RUN_BUILD="true"
  else
    echo "The $command command has failed."
    #Set the build tag to "false" since the build has failed.
    RUN_BUILD="false"
    export_variable "RUN_BUILD"
    #Kill the build script so that we go no further.
    exit 1
  fi
}

#Check if required commands exist...
exists () {
  command -v "$1" >/dev/null 2>&1
}

#Because CodeBuild doesn't pass environment between phases, putting in a patch.
export_variable () {
  local key="$1"

  export $key

  local temp=$(printenv | grep -w $key)

  echo "$temp" >> /tmp/pre_build
}

increment_semver_patch_level () {
  local version="$1"
  local file="$2"
  local contents=""
  local result=""
  local major=0
  local minor=0
  local patch=0

  major=$(echo "$version" | cut -d. -f1);
  minor=$(echo "$version" | cut -d. -f2);
  patch=$(echo "$version" | cut -d. -f3);
  patch=$((patch+1));
  result="$major.$minor.$patch";

  #Update the METADATA file.
  contents="$(jq --arg version "$result" '.version = $version' "$file")"
  echo "${contents}" > "$file"

  echo "$result";
}

retrieve_github_organization () {
  local remote="$1"

  if [ "$(echo "$remote" | cut -c1-15)" = "git@github.com:" ]; then
    echo "$remote" | cut -c16- | cut -d/ -f1
  elif [ "$(echo "$remote" | cut -c1-19)" = "https://github.com/" ]; then
    echo "$remote" | cut -c20- | cut -d/ -f1
  else
    echo "UNKNOWN"
  fi
}

retrieve_github_repository () {
  local remote="$1"

  if [ "$(echo "$remote" | cut -c1-15)" = "git@github.com:" ]; then
    echo "$remote" | cut -c16- | rev | cut -c5- | rev | cut -d/ -f2-
  elif [ "$(echo "$remote" | cut -c1-19)" = "https://github.com/" ]; then
    echo "$remote" | cut -c20- | rev | cut -c5- | rev | cut -d/ -f2-
  else
    echo "UNKNOWN"
  fi
}

update_version () {

  echo "Checking if the Docker image already exists in the \"$AWS_REGION\" region..."
  check_docker_image "$IMAGE_REPO_NAME" "$VERSION_TAG"

  if [ "$AWS_SECOND_REGION" = "NONE" ]; then
    echo "The second region wasn't set, so not going to check that region..."
  else
    echo "Attempting to pull this image to see if it already exists in the \"$AWS_SECOND_REGION\" region..."
    check_docker_image "$IMAGE_REPO_NAME" "$VERSION_TAG" "$AWS_SECOND_REGION"
  fi

  if [ "$AWS_THIRD_REGION" = "NONE" ]; then
    echo "The third region wasn't set, so not going to check that region..."
  else
    echo "Attempting to pull this image to see if it already exists in the \"$AWS_THIRD_REGION\" region..."
    check_docker_image "$IMAGE_REPO_NAME" "$VERSION_TAG" "$AWS_THIRD_REGION"
  fi

}

update_version_tag () {
  #Set the version tag...
  if [ "$UNSTABLE_BRANCH" = "$GIT_BRANCH" ]; then
    echo "Adding the \"$GIT_BRANCH\" environment to the version tag..."
    VERSION_TAG="version-$VERSION-$GIT_BRANCH"
  else
    echo "Using the standard version tag..."
    VERSION_TAG="version-$VERSION"
  fi
}

#------------------------------------------------------------------------
# END: Declare some functions
#------------------------------------------------------------------------

#------------------------------------------------------------------------
# BEGIN: Check for prerequisite commands
#------------------------------------------------------------------------

check_cmd_exists "aws"

check_cmd_exists "curl"

check_cmd_exists "git"

check_cmd_exists "jq"

#------------------------------------------------------------------------
# END: Check for prerequisite commands
#------------------------------------------------------------------------

#------------------------------------------------------------------------
# BEGIN: Set a number of variables
#------------------------------------------------------------------------

#Change the directory to the application directory...
if [ -z "$APP_BASE_FOLDER" ]; then
  cd "$CODEBUILD_SRC_DIR/$CUSTOM_IMAGE_PATH/$CUSTOM_IMAGE_TAG" || exit 1
else
  cd "$CODEBUILD_SRC_DIR/$APP_BASE_FOLDER/$CUSTOM_IMAGE_PATH/$CUSTOM_IMAGE_TAG" || exit 1
fi

echo "Extract some METADATA from the \"$METADATA_FILE\" file..."
NAME=$(cat "$METADATA_FILE" | jq -r '.name')
VERSION=$(cat "$METADATA_FILE" | jq -r '.version')

echo "Extract the CodePipeline name and CodeBuild ID..."
CURRENT_PIPELINE=$(printf "%s" "$CODEBUILD_INITIATOR" | rev | cut -d/ -f1 | rev)
BUILD_ID=$(printf "%s" "$CODEBUILD_BUILD_ID" | sed "s/.*:\([[:xdigit:]]\{7\}\).*/\1/")

check_variable "$GIT_REMOTE_URL" "git remote URL"

check_variable "$GIT_FULL_REVISION" "git full revision"

check_variable "$GIT_BRANCH" "git branch"

check_variable "$GITHUB_REPOSITORY" "GitHub repository"

#Set a date variable...
DATETIME_ET=$(TZ="America/New_York" date +"%Y%m%d%H%M%S")

#Regional docker URL...
FIRST_REGION_DOCKER_URL=$(build_docker_url "$AWS_ACCOUNT_ID" "$AWS_REGION" "$IMAGE_REPO_NAME")

if [ "$AWS_SECOND_REGION" = "NONE" ]; then
  echo "The second region was not set, so not building the docker URL for the second region."
  SECOND_REGION_DOCKER_URL="NONE"
else
  SECOND_REGION_DOCKER_URL=$(build_docker_url "$AWS_ACCOUNT_ID" "$AWS_SECOND_REGION" "$IMAGE_REPO_NAME")
fi

if [ "$AWS_THIRD_REGION" = "NONE" ]; then
  echo "The third region was not set, so not building the docker URL for the third region."
  THIRD_REGION_DOCKER_URL="NONE"
else
  THIRD_REGION_DOCKER_URL=$(build_docker_url "$AWS_ACCOUNT_ID" "$AWS_THIRD_REGION" "$IMAGE_REPO_NAME")
fi

#------------------------------------------------------------------------
# END: Set a number of variables
#------------------------------------------------------------------------

#------------------------------------------------------------------------
# BEGIN: Check if docker images already exist and set variables
#------------------------------------------------------------------------

#Update the version tag...
update_version_tag

#Update the version, if needed.
update_version

echo "Setting some build tags..."
BUILD_ID_TAG="codebuild-$BUILD_ID"
GIT_REVISION_TAG="git-$GIT_FULL_REVISION" #Need the full hash for advanced git interactions.

#------------------------------------------------------------------------
# END: Check if docker images already exist and set variables
#------------------------------------------------------------------------

#------------------------------------------------------------------------
# BEGIN: Output a number of variables
#------------------------------------------------------------------------

#CodeBuild-specific environment variables...
echo "CodeBuild Source Version: $CODEBUILD_SOURCE_VERSION"

#General environment variables...
echo "Application name is: $NAME"
echo "Application version is: $VERSION"
echo "Build tag is: $BUILD_ID_TAG"
echo "Git revision tag is: $GIT_REVISION_TAG"
echo "Version tag is: $VERSION_TAG"
echo "Initiating CodePipeline is: $CODEBUILD_INITIATOR"
echo "Current CodePipeline name is: $CURRENT_PIPELINE"
echo "Full git revision is: $GIT_FULL_REVISION"
echo "Current time in the Eastern Time Zone is: $DATETIME_ET"
echo "First region docker URL: $FIRST_REGION_DOCKER_URL"
echo "Second region docker URL: $SECOND_REGION_DOCKER_URL"
echo "Third region docker URL: $THIRD_REGION_DOCKER_URL"

#------------------------------------------------------------------------
# END: Output a number of variables
#------------------------------------------------------------------------

#------------------------------------------------------------------------
# BEGIN: Export variables to share with other shell scripts
#------------------------------------------------------------------------

export_variable "BUILD_ID"
export_variable "BUILD_ID_TAG"
export_variable "CURRENT_PIPELINE"
export_variable "DATETIME_ET"
export_variable "DEFAULT_IMAGE_TAG"
export_variable "FIRST_REGION_DOCKER_URL"
export_variable "GIT_BRANCH"
export_variable "GIT_FULL_REVISION"
export_variable "GIT_REVISION_TAG"
export_variable "GITHUB_REPOSITORY"
export_variable "NAME"
export_variable "RUN_BUILD"
export_variable "SECOND_REGION_DOCKER_URL"
export_variable "THIRD_REGION_DOCKER_URL"
export_variable "VERSION"
export_variable "VERSION_TAG"

#------------------------------------------------------------------------
# END: Export variables to share with other shell scripts
#------------------------------------------------------------------------
