#!/usr/bin/env bash

#set -euo pipefail
#set -x

if [ "$#" -lt 1 ]; then
  echo "Missing arguments."
  exit 1
fi

GITHUB_URL="https://github.com"
GITHUB_API_URL=${GITHUB_URL/https:\/\//https:\/\/api.}
GITHUB_OWNER="$(echo "$1" | cut -d / -f 1)"
GITHUB_REPO="$(echo "$1" | cut -d / -f 2)"

function fetch_repository() {
  fetch_repository=$(curl -sL \
    -H "Accept: application/vnd.github+json" \
    -H "Authorization: token ${GITHUB_AUTH_TOKEN}" \
    -H "X-GitHub-Api-Version: 2022-11-28" \
    "${GITHUB_API_URL}/repos/${GITHUB_OWNER}/${GITHUB_REPO}")
    
  # GitHub repo HTTP status code
  http_status=$(echo "$fetch_repository" | jq -r 'if .message == "Not Found" then "404" elif .message == "Bad credentials" then "401" else "200" end')

  # GitHub repo metadata
  if [ "$http_status" -eq 200 ]; then
    FETCH_JSON="$fetch_repository"
    REPOSITORY_NAME=$(echo "$fetch_repository" | jq -r '.name')
    REPOSITORY_FULL_NAME=$(echo "$fetch_repository" | jq -r '.full_name')
    REPOSITORY_DESCRIPTION=$(echo "$fetch_repository" | jq -r '.description')
    REPOSITORY_PR_COUNT=$(echo "$fetch_repository" | jq -r '.open_issues_count')
    REPOSITORY_TOPICS=$(echo "$fetch_repository" | jq -r '.topics[]' | paste -sd ',')
    REPOSITORY_TEMPLATE=$(echo "$fetch_repository" | jq -r '.is_template')
    REPOSITORY_API_URL=$(echo "$fetch_repository" | jq -r '.url')
    REPOSITORY_CLONE_URL=$(echo "$fetch_repository" | jq -r '.clone_url')
  fi
}

function deployments() {
  deployments_url="${1/%/\/deployments}"

  fetch=$(curl -sL \
    -H "Accept: application/vnd.github+json" \
    -H "Authorization: Bearer ${GITHUB_AUTH_TOKEN}" \
    -H "X-GitHub-Api-Version: 2022-11-28" \
    "$deployments_url")

  is_empty=$(echo "$fetch" | jq -r 'if . == [] then "true" else "false" end')

  echo "Fetching deployments ..."
  sleep 1
  if [ "$is_empty" == "true" ]; then
    echo "No deployments found!"
  else
    DEPLOYMENTS=$(echo "$fetch" | jq -r '.[].name')
    echo "$DEPLOYMENTS"
  fi
}

function releases() {
  releases_url="${1/%/\/releases}"

  fetch=$(curl -sL \
    -H "Accept: application/vnd.github+json" \
    -H "Authorization: Bearer ${GITHUB_AUTH_TOKEN}" \
    -H "X-GitHub-Api-Version: 2022-11-28" \
    "$releases_url")
  
  is_empty=$(echo "$fetch" | jq -r 'if . == [] then "true" else "false" end')
  
  echo -e "\nFetching releases ..."
  sleep 1
  if [ "$is_empty" == "true" ]; then
    echo "No releases found!"
  else
    RELEASES=$(echo "$fetch" | jq -r '.[].tag_name' | sort | paste -sd ',')

    IFS=',' read -r -a _r <<< "$RELEASES"

    for release in "${_r[@]}"; do
      echo "Release: $release"
    done
  fi
}

function tags() {
  tags_url="${1/%/\/tags}"

  fetch=$(curl -sL \
    -H "Accept: application/vnd.github+json" \
    -H "Authorization: Bearer ${GITHUB_AUTH_TOKEN}" \
    -H "X-GitHub-Api-Version: 2022-11-28" \
    "$tags_url")
  
  is_empty=$(echo "$fetch" | jq -r 'if . == [] then "true" else "false" end')
  
  echo -e "\nFetching tags ..."
  sleep 1
  if [ "$is_empty" == "true" ]; then
    echo "No tags found!"
  else
    TAGS=$(echo "$fetch" | jq -r '.[].name' | sort | paste -sd ',')
    
    IFS=',' read -r -a _t <<< "$TAGS"

    for tag in "${_t[@]}"; do
      echo "Tag: $tag"
    done
  fi
}

function secrets() {
  secrets_url="${1/%/\/actions\/secrets}"

  fetch=$(curl -sL \
    -H "Accept: application/vnd.github+json" \
    -H "Authorization: Bearer ${GITHUB_AUTH_TOKEN}" \
    -H "X-GitHub-Api-Version: 2022-11-28" \
    "$secrets_url")

  is_empty=$(echo "$fetch" | jq -r 'if .total_count == 0 then "true" else "false" end')

  echo -e "\nFetching secrets ..."
  sleep 1
  if [ "$is_empty" == "true" ]; then
    echo "No secrets found!"
  else
    SECRETS=$(echo "$fetch" | jq -r '.secrets[].name')
    SECRETS_COUNT=$(echo "$fetch" | jq -r '.total_count')
    printf "%s secrets found.\n%s\n" "$SECRETS_COUNT" "$SECRETS"
    return 0
  fi
}

function display() {
  echo "--------------------------"
  printf "SOURCE REPOSITORY METADATA\n"
  printf "Repository: %s\n" "$REPOSITORY_FULL_NAME"
  printf "Repository description: %s\n" "$REPOSITORY_DESCRIPTION"
  printf "Repository open PR: %s\n" "$REPOSITORY_PR_COUNT"
  printf "Repository template: %s\n" "${REPOSITORY_TEMPLATE^}"
  printf "Repository clone URL: %s\n" "${REPOSITORY_API_URL/api.github.com\/repos/github.com}.git"
  echo "--------------------------"
  printf "\n"
  #printf "%s\n" "$FETCH_JSON"
}

fetch_repository
display
#deployments "$REPOSITORY_API_URL"
#releases "$REPOSITORY_API_URL"
#tags "$REPOSITORY_API_URL"
#secrets "$REPOSITORY_API_URL"
