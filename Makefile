.DEFAULT_GOAL := all
.PHONY: clean test deploy all

NAME=dit4c-helper-listener-ssh
BASE_DIR=.
BUILD_DIR=${BASE_DIR}/build
OUT_DIR=${BASE_DIR}/dist
TARGET_IMAGE=${OUT_DIR}/${NAME}.linux.amd64.aci

MKDIR_P=mkdir -p
GPG=gpg2

ALPINE_DOCKER_IMAGE=alpine:3.5
ALPINE_ACI=${BUILD_DIR}/library-alpine-3.5.aci

ACBUILD=${BUILD_DIR}/acbuild
ACBUILD_VERSION=0.4.0
ACBUILD_URL=https://github.com/containers/build/releases/download/v${ACBUILD_VERSION}/acbuild-v${ACBUILD_VERSION}.tar.gz

DOCKER2ACI=${BUILD_DIR}/docker2aci
DOCKER2ACI_VERSION=0.15.0
DOCKER2ACI_URL=https://github.com/appc/docker2aci/releases/download/v${DOCKER2ACI_VERSION}/docker2aci-v${DOCKER2ACI_VERSION}.tar.gz

RKT_VERSION=1.25.0
ACBUILD=build/acbuild
RKT=build/rkt/rkt
BIN_FILES=$(shell find ${BASE_DIR}/bin)

${BUILD_DIR}:
	${MKDIR_P} ${BUILD_DIR}

${OUT_DIR}:
	${MKDIR_P} ${OUT_DIR}

clean:
	rm -rf ${BUILD_DIR} ${OUT_DIR}

${ACBUILD}: | ${BUILD_DIR}
	curl -sL ${ACBUILD_URL} | tar xz --touch --strip-components=1 -C ${BUILD_DIR}

${DOCKER2ACI}: | ${BUILD_DIR}
	curl -sL ${DOCKER2ACI_URL} | tar xz --touch --strip-components=1 -C ${BUILD_DIR}

${ALPINE_ACI}: ${DOCKER2ACI}
	cd ${BUILD_DIR} && ../${DOCKER2ACI} docker://${ALPINE_DOCKER_IMAGE}

${TARGET_IMAGE}: ${ACBUILD} ${ALPINE_ACI} ${BUILD_DIR}/jwt ${BIN_FILES} | ${OUT_DIR}
	sudo rm -rf .acbuild
	sudo ${ACBUILD} --debug begin ${ALPINE_ACI}
	sudo ${ACBUILD} --debug copy build/jwt /usr/bin/jwt
	sudo ${ACBUILD} --debug copy-to-dir install.sh /
	sudo ${ACBUILD} --debug copy-to-dir bin /opt
	sudo sh -c 'PATH=${shell echo $$PATH}:${BUILD_DIR} ${ACBUILD} --debug run --engine chroot -- sh -c "./install.sh && rm -f install.sh"'
	sudo ${ACBUILD} --debug set-exec -- /opt/bin/run.sh
	sudo ${ACBUILD} --debug set-name ${NAME}
	sudo ${ACBUILD} --debug environment add ROUTING_SCHEME http
	sudo ${ACBUILD} --debug environment add ROUTING_DOMAIN example.test
	sudo ${ACBUILD} --debug environment add PGP_LOOKUPURL 'https://dit4c.net/instances/<REMOTE_USER>/pgp-keys'
	sudo ${ACBUILD} --debug port add ssh tcp 22
	sudo ${ACBUILD} --debug port add http tcp 80
	sudo ${ACBUILD} --debug port add https tcp 443
	sudo ${ACBUILD} --debug write --overwrite $@
	sudo ${ACBUILD} --debug end
	sudo chown $(shell id -u):$(shell id -g) $@

${TARGET_IMAGE}.asc: ${TARGET_IMAGE} signing.key
	$(eval TMP_PUBLIC_KEYRING := $(shell mktemp -p ./build))
	$(eval TMP_SECRET_KEYRING := $(shell mktemp -p ./build))
	$(eval GPG_FLAGS := --batch --no-default-keyring --keyring $(TMP_PUBLIC_KEYRING) --secret-keyring $(TMP_SECRET_KEYRING) )
	$(GPG) $(GPG_FLAGS) --import signing.key
	rm -f $@
	$(GPG) $(GPG_FLAGS) --armour --detach-sign $<
	rm $(TMP_PUBLIC_KEYRING) $(TMP_SECRET_KEYRING)

${BUILD_DIR}/jwt: | ${RKT}
	$(eval RKT_TMPDIR := $(shell mktemp -d -p ./build))
	sudo -v && sudo $(RKT) --dir=$(RKT_TMPDIR) run \
		--dns=8.8.8.8 --insecure-options=image \
    --volume output-dir,kind=host,source=`pwd`/build \
    docker://golang:alpine \
    --set-env CGO_ENABLED=0 \
    --set-env GOOS=linux \
    --mount volume=output-dir,target=/output \
    --exec /bin/sh --  -c "apk add --update git make && /usr/local/go/bin/go get -v --ldflags '-extldflags \"-static\"' github.com/knq/jwt/cmd/jwt && install -t /output -o $(shell id -u) -g $(shell id -g) /go/bin/*"
	sudo -v && sudo ${RKT} --dir=${RKT_TMPDIR} gc --grace-period=0s
	sudo rm -rf ${RKT_TMPDIR}

build/bats: | build
	curl -sL https://github.com/sstephenson/bats/archive/master.zip > build/bats.zip
	unzip -d build build/bats.zip
	mv build/bats-master build/bats
	rm build/bats.zip

$(RKT): | build
	curl -sL https://github.com/coreos/rkt/releases/download/v${RKT_VERSION}/rkt-v${RKT_VERSION}.tar.gz | tar xz -C build
	mv build/rkt-v${RKT_VERSION} build/rkt

test: build/bats ${RKT} ${TARGET_IMAGE}
	sudo -v && echo "" && build/bats/bin/bats -t test

all: ${TARGET_IMAGE}

deploy: ${TARGET_IMAGE} ${TARGET_IMAGE}.asc
