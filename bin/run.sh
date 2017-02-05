#!/bin/sh

set -ex

# Import any extra environment we might need
if [[ -f /dit4c/env.sh ]]; then
  set -a
  source /dit4c/env.sh
  set +a
fi

if [[ "$DIT4C_INSTANCE_HELPER_AUTH_HOST" == "" ]]; then
  echo "Must specify DIT4C_INSTANCE_HELPER_AUTH_HOST to expose"
  exit 1
fi

if [[ "$DIT4C_INSTANCE_HELPER_AUTH_PORT" == "" ]]; then
  echo "Must specify DIT4C_INSTANCE_HELPER_AUTH_PORT to expose"
  exit 1
fi

if [[ ! -f "$DIT4C_INSTANCE_PRIVATE_KEY_PKCS1" ]]; then
  echo "Unable to find DIT4C_INSTANCE_PRIVATE_KEY_PKCS1: $DIT4C_INSTANCE_PRIVATE_KEY_PKCS1"
  exit 1
fi

if [[ "$DIT4C_INSTANCE_JWT_ISS" == "" ]]; then
  echo "Must specify DIT4C_INSTANCE_JWT_ISS for JWT auth token"
  exit 1
fi

if [[ "$DIT4C_INSTANCE_JWT_KID" == "" ]]; then
  echo "Must specify DIT4C_INSTANCE_JWT_KID for JWT auth token"
  exit 1
fi

if [[ "$DIT4C_INSTANCE_URI_UPDATE_URL" == "" ]]; then
  echo "Must specify DIT4C_INSTANCE_URI_UPDATE_URL"
  exit 1
fi

PORTAL_DOMAIN=$(echo $DIT4C_INSTANCE_URI_UPDATE_URL | awk -F/ '{print $3}')

while true
do
  SSH_SERVER=$(dig +short TXT $PORTAL_DOMAIN | grep -Eo "dit4c-ssh-router=[^\"]*" | cut -d= -f2 | xargs /opt/bin/sort_by_latency.sh | head -1)
  SSH_HOST=$(echo $SSH_SERVER | cut -d: -f1)
  SSH_PORT=$(echo $SSH_SERVER | cut -d: -f2)

  ssh -i $DIT4C_INSTANCE_PRIVATE_KEY_PKCS1 \
    -o "StrictHostKeyChecking no" -o "UserKnownHostsFile /dev/null" \
    -p $SSH_PORT \
    register@$SSH_HOST $DIT4C_INSTANCE_JWT_KID

  RANDOM_SUFFIX=$(tr -dc '[:alnum:]' < /dev/urandom | head -c32)
  SOCKET="/tmp/$DIT4C_INSTANCE_JWT_KID-$RANDOM_SUFFIX.sock"

  ssh -i $DIT4C_INSTANCE_PRIVATE_KEY_PKCS1 \
    -o "StrictHostKeyChecking no" -o "UserKnownHostsFile /dev/null" \
    -R $SOCKET:$DIT4C_INSTANCE_HELPER_AUTH_HOST:$DIT4C_INSTANCE_HELPER_AUTH_PORT \
    -p $SSH_PORT \
    listen@$SSH_HOST $SOCKET | \
    (/opt/bin/check_url_is_accessible.sh || pkill ssh) | \
    /opt/bin/notify_portal.sh
done
