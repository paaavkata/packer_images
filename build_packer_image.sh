# !/bin/bash

function parse_yaml {
   local prefix=$2
   local s='[[:space:]]*' w='[a-zA-Z0-9_]*' fs=$(echo @|tr @ '\034')
   sed -ne "s|^\($s\):|\1|" \
        -e "s|^\($s\)\($w\)$s:$s[\"']\(.*\)[\"']$s\$|\1$fs\2$fs\3|p" \
        -e "s|^\($s\)\($w\)$s:$s\(.*\)$s\$|\1$fs\2$fs\3|p"  $1 |
   awk -F$fs '{
      indent = length($1)/2;
      vname[indent] = $2;
      for (i in vname) {if (i > indent) {delete vname[i]}}
      if (length($3) > 0) {
         vn=""; for (i=0; i<indent; i++) {vn=(vn)(vname[i])("_")}
         printf("%s%s%s=%s\n", "'$prefix'",vn, $2, $3);
      }
   }'
}

IMAGE_NAME=$1
TAG=${2:-local}

main_dir=$pwd
cd docker/$1
config=$(parse_yaml config.yaml)

# Before
before_args=$(echo "${config}" | grep before_)
for argument in ${before_args}; do
   if [[ $argument == before_sh=* ]]; then
      sh ${argument:10}
   fi
done

# Docker build
docker_args=$(echo "${config}" | grep docker_args_)
docker_env_vars=""
for argument in ${docker_args}; do
    docker_env_vars="${docker_env_vars} --build-arg ${argument:17}"
done

docker build ${docker_env_vars} -t "${IMAGE_NAME}":"${TAG}" . && echo "Image successfuly build. Can be found as $IMAGE_NAME:$TAG" || echo "Failed"

cd $main_dir
