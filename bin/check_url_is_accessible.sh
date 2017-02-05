#!/bin/sh

set -e

# Read each line in
while IFS= read -r URL; do
  curl -s "$URL" > /dev/null && echo "Verified $URL is accessible" >&2 || \
    (echo "Provided URL $URL is uncontactable!" >&2 && exit 1)
  echo "$URL"
done
