#! /bin/sh

set -e

DOCKER_NAME="jasonish/evebox"
BRANCH_PREFIX=$(git rev-parse --abbrev-ref HEAD | awk '{split($0,a,"/"); print a[1]}')

BUILD_REV=$(git rev-parse --short HEAD)
export BUILD_REV

build_docker() {
    docker build --build-arg "BUILD_REV=${BUILD_REV}" -t ${DOCKER_NAME}:${BRANCH_PREFIX} .
}

build_all() {
    rm -rf dist

    build_docker
    ./docker.sh webapp
    ./docker.sh release-linux
    ./docker.sh release-windows
    ./docker.sh release-macos
}

release_arm7() {
    DOCKERFILE="./docker/builder/Dockerfile.arm"
    TAG="evebox/builder:arm"
    docker build --rm \
	   -t ${TAG} \
	   -f ${DOCKERFILE} .
    exec docker run ${IT} --rm \
         -v "$(pwd)/target:/src/target" \
         -v "$(pwd)/dist:/src/dist" \
         -v /var/run/docker.sock:/var/run/docker.sock \
         -w /src \
         -e REAL_UID="$(id -u)" \
         -e REAL_GID="$(id -g)" \
         -e BUILD_REV="${BUILD_REV}" \
         -e TARGET="armv7-unknown-linux-musleabihf" \
         -e CARGO="cross" \
         ${TAG} make dist
}

docker_arm7() {
    docker buildx build --platform linux/arm/v7 -f docker/Dockerfile.arm \
           -t ${DOCKER_NAME}:${BRANCH_PREFIX}-armv7 .
}

push() {
    docker push ${DOCKER_NAME}:${BRANCH_PREFIX}

    (cd dist && sha256sum *.zip *.rpm *.deb > CHECKSUMS.txt)

    if [ "${EVEBOX_RSYNC_PUSH_DEST}" ]; then
        rsync -av \
              --filter "+ *.rpm" \
              --filter "+ *.deb" \
              --filter "+ *.zip" \
              --filter "+ CHECKSUMS.txt" \
              --filter "- *" \
              dist/ \
              "${EVEBOX_RSYNC_PUSH_DEST}"
    else
        echo "error: EVEBOX_RSYNC_PUSH_DEST environment variable not set"
    fi
}

case "$1" in
    docker)
        build_docker
        ;;

    release-arm7)
        release_arm7
        docker_arm7
        ;;

    docker-arm7)
        docker_arm7
        ;;
    
    all)
        build_all
        release_arm7
        ;;

    push)
        push
        ;;

    *)
        cat <<EOF
usage: $0 <command>

Commands:
    release-arm7       Build arm7 Linux Release (RPi) - zip
    all
EOF
        ;;
esac
