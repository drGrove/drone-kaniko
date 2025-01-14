#!/busybox/sh

set -euo pipefail

export PATH=$PATH:/kaniko/

REGISTRY=${PLUGIN_REGISTRY:-https://index.docker.io/v1/}

if [ "${PLUGIN_USERNAME:-}" ] || [ "${PLUGIN_PASSWORD:-}" ]; then
    DOCKER_AUTH=`echo -n "${PLUGIN_USERNAME}:${PLUGIN_PASSWORD}" | base64 | tr -d "\n"`

    cat > /kaniko/.docker/config.json <<DOCKERJSON
{
    "auths": {
        "${REGISTRY}": {
            "auth": "${DOCKER_AUTH}"
        }
    }
}
DOCKERJSON
fi

# If we're using dockerhub we have to convert from URL with protocol to
# standard format for use throughout the rest of the system
if [ "${REGISTRY}" == "https://index.docker.io/v1/" ]; then
  REGISTRY="docker.io"
fi

if [ "${PLUGIN_JSON_KEY:-}" ];then
    echo "${PLUGIN_JSON_KEY}" > /kaniko/gcr.json
    export GOOGLE_APPLICATION_CREDENTIALS=/kaniko/gcr.json
fi

DOCKERFILE=${PLUGIN_DOCKERFILE:-Dockerfile}
CONTEXT=${PLUGIN_CONTEXT:-$PWD}
LOG=${PLUGIN_LOG:-info}
EXTRA_OPTS=""
SHOW_DIGEST="true"
DIGEST_FILE=${PLUGIN_DIGEST_FILE:-/tmp/digest}

if [[ -n "${PLUGIN_TARGET:-}" ]]; then
    TARGET="--target=${PLUGIN_TARGET}"
fi

if [[ "${PLUGIN_SKIP_TLS_VERIFY:-}" == "true" ]]; then
  EXTRA_OPTS="${EXTRA_OPTS} --skip-tls-verify=true"
fi

if [[ "${PLUGIN_CACHE:-}" == "true" ]]; then
    CACHE="--cache=true"
fi

if [ -n "${PLUGIN_CACHE_REPO:-}" ]; then
    CACHE_REPO="--cache-repo=${REGISTRY}/${PLUGIN_CACHE_REPO}"
fi

if [ -n "${PLUGIN_CACHE_TTL:-}" ]; then
    CACHE_TTL="--cache-ttl=${PLUGIN_CACHE_TTL}"
fi

if [ -n "${PLUGIN_BUILD_ARGS:-}" ]; then
    BUILD_ARGS=$(echo "${PLUGIN_BUILD_ARGS}" | tr ',' '\n' | while read build_arg; do echo "--build-arg=${build_arg}"; done)
fi

if [ -n "${PLUGIN_BUILD_ARGS_FROM_ENV:-}" ]; then
    BUILD_ARGS_FROM_ENV=$(echo "${PLUGIN_BUILD_ARGS_FROM_ENV}" | tr ',' '\n' | while read build_arg; do echo "--build-arg ${build_arg}=$(eval "echo \$$build_arg")"; done)
fi

if [ -n "${PLUGIN_REPRODUCIBLE:-}" ]; then
  EXTRA_OPTS="${EXTRA_OPTS} --reproducible"
fi

if [ -n "${PLUGIN_SINGLE_SNAPSHOT:-}" ]; then
  EXTRA_OPTS="${EXTRA_OPTS} --single-snapshot"
fi


# auto_tag, if set auto_tag: true, auto generate .tags file
# support format Major.Minor.Release or start with `v`
# docker tags: Major, Major.Minor, Major.Minor.Release and latest
if [[ "${PLUGIN_AUTO_TAG:-}" == "true" ]]; then
    TAG=$(echo "${DRONE_TAG:-}" |sed 's/^v//g')
    part=$(echo "${TAG}" |tr '.' '\n' |wc -l)
    # expect number
    echo ${TAG} |grep -E "[a-z-]" &>/dev/null && isNum=1 || isNum=0

    if [ ! -n "${TAG:-}" ];then
        echo "latest" > .tags
    elif [ ${isNum} -eq 1 -o ${part} -gt 3 ];then
        echo "${TAG},latest" > .tags
    else
        major=$(echo "${TAG}" |awk -F'.' '{print $1}')
        minor=$(echo "${TAG}" |awk -F'.' '{print $2}')
        release=$(echo "${TAG}" |awk -F'.' '{print $3}')

        major=${major:-0}
        minor=${minor:-0}
        release=${release:-0}

        echo "${major},${major}.${minor},${major}.${minor}.${release},latest" > .tags
    fi
fi

if [ -n "${PLUGIN_TAGS:-}" ]; then
    DESTINATIONS=$(echo "${PLUGIN_TAGS}" | tr ',' '\n' | while read tag; do echo "--destination=${REGISTRY}/${PLUGIN_REPO}:${tag} "; done)
    EXTRA_OPTS="${EXTRA_OPTS} --image-name-tag-with-digest-file=${DIGEST_FILE}"
elif [ -f .tags ]; then
    DESTINATIONS=$(cat .tags| tr ',' '\n' | while read tag; do echo "--destination=${REGISTRY}/${PLUGIN_REPO}:${tag} "; done)
    EXTRA_OPTS="${EXTRA_OPTS} --image-name-tag-with-digest-file=${DIGEST_FILE}"
elif [ -n "${PLUGIN_REPO:-}" ]; then
    DESTINATIONS="--destination=${REGISTRY}/${PLUGIN_REPO}:latest"
    EXTRA_OPTS="${EXTRA_OPTS} --image-name-tag-with-digest-file=${DIGEST_FILE}"
else
    DESTINATIONS="--no-push"
    # Cache is not valid with --no-push
    CACHE=""
    SHOW_DIGEST="false"
fi

/kaniko/executor -v ${LOG} \
    --context=${CONTEXT} \
    --dockerfile=${DOCKERFILE} \
    ${EXTRA_OPTS} \
    ${DESTINATIONS} \
    ${CACHE:-} \
    ${CACHE_TTL:-} \
    ${CACHE_REPO:-} \
    ${TARGET:-} \
    ${BUILD_ARGS:-} \
    ${BUILD_ARGS_FROM_ENV:-}

if [ "${SHOW_DIGEST}" == "true" ]; then
  cat "${DIGEST_FILE}"
fi
