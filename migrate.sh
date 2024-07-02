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

function github_check_repository() {
  fetch_repository=$(curl -sL \
    -H "Accept: application/vnd.github+json" \
    -H "Authorization: token ${GITHUB_AUTH_TOKEN}" \
    -H "X-GitHub-Api-Version: 2022-11-28" \
    "${GITHUB_API_URL}/repos/${GITHUB_OWNER}/${GITHUB_REPO}")
    
  # GitHub repo HTTP status code
  http_status=$(echo "$fetch_repository" | jq -r 'if .message == "Not Found" then "404" elif .message == "Bad credentials" then "401" else "200" end')

  # GitHub repo metadata
  REPOSITORY_NAME=$(echo "$fetch_repository" | jq -r '.name')
  REPOSITORY_FULL_NAME=$(echo "$fetch_repository" | jq -r '.full_name')
  REPOSITORY_DESCRIPTION=$(echo "$fetch_repository" | jq -r '.description')
  REPOSITORY_OPEN_PR=$(echo "$fetch_repository" | jq -r '.open_issues')
  REPOSITORY_TOPICS=$(echo "$fetch_repository" | jq -r '.topics[]' | paste -sd ',')
}

function github_check_branch() {
  local BRANCHES_URL
  BRANCHES_URL=$(echo "$fetch_repository" | jq -r '.branches_url' | cut -d '{' -f1)
  
  get_branches=$(curl -sL \
    -H "Accept: application/vnd.github+json" \
    -H "Authorization: token ${GITHUB_AUTH_TOKEN}" \
    -H "X-GitHub-Api-Version: 2022-11-28" \
    "${BRANCHES_URL}")

  branches=$(echo "$get_branches" | jq -r ' .[].name | select(startswith("main") or startswith("develop") or startswith("staging"))')
  count_branches=$(echo "$branches" | wc -l)
  format_branches=$(echo "$branches" | paste -sd ',')

  if [ "$count_branches" -eq 3 ]; then
    SOURCE_BRANCH_TYPE="git flow"
    OUTPUT_BRANCH_TYPE="github flow"
    BRANCH_PATTERN="main"
  else
    SOURCE_BRANCH_TYPE="github flow"
    OUTPUT_BRANCH_TYPE="git flow"
    BRANCH_PATTERN="main,develop,staging"
  fi
}

function github_create_repository() {
  repo_name="$1"
  repo_description="$2"
  repo_topics="$3"
  repo_branches="$4"

  IFS=',' read -r -a _tp <<< "$repo_topics"
  IFS=',' read -r -a _br <<< "$repo_branches"
  
  echo "Creating repository ..."
  sleep 1
  curl -sL \
    -H "Accept: application/vnd.github+json" \
    -H "Authorization: token ${GITHUB_AUTH_TOKEN}" \
    -H "X-GitHub-Api-Version: 2022-11-28" \
    "${GITHUB_API_URL}/user/repos" \
    -d "{
         \"name\": \"${repo_name}\",
         \"description\": \"${repo_description}\",
         \"auto_init\": \"true\"
       }" \
    -o /dev/null

  format_topics=$(echo "$repo_topics" | jq -R 'split(",") | {names: .}')

  echo "Add topics ..."
  sleep 1
  curl -sL \
    -X PUT \
    -H "Accept: application/vnd.github+json" \
    -H "Authorization: token ${GITHUB_AUTH_TOKEN}" \
    -H "X-GitHub-Api-Version: 2022-11-28" \
    "${GITHUB_API_URL}/repos/${GITHUB_OWNER}/${repo_name}/topics" \
    -d "$format_topics" \
    -o /dev/null

  for b in "${_br[@]}"
  do
    if [ "main" == "$b" ] && [ "git flow" == "$OUTPUT_BRANCH_TYPE" ]; then
      echo "Add branches ..."
    else
      continue
    fi
  done
}

function github_convert_branch_type() {
  if [ "$REPOSITORY_OPEN_PR" -gt 0 ]; then
    printf "This repository has open PRs!\nRepositories that have an open PR cannot be migrated."
    exit 1
  else
    NEW_REPOSITORY="$REPOSITORY_NAME-migrate"
    
    # Debug
    printf "Migrating repository braching strategy type from %s to %s\n\n" "$SOURCE_BRANCH_TYPE" "$OUTPUT_BRANCH_TYPE"  
    echo "--------------------------"
    printf "Source repository Metadata\n"
    printf "Repository: %s\n" "$REPOSITORY_FULL_NAME"
    printf "Branch type: %s\n" "${SOURCE_BRANCH_TYPE^}"
    printf "Branch patterns: %s\n" "$format_branches"
    echo "--------------------------"
    printf "Output repository Metadata\n"
    printf "Repository: %s/%s\n" "$GITHUB_OWNER" "$NEW_REPOSITORY"
    printf "Branch type: %s\n" "${OUTPUT_BRANCH_TYPE^}"
    printf "Branch patterns: %s\n\n" "${BRANCH_PATTERN[@]}"
    echo "--------------------------"
    printf "\n"

    github_create_repository "$NEW_REPOSITORY" "$REPOSITORY_DESCRIPTION" "$REPOSITORY_TOPICS" "$BRANCH_PATTERN"

    echo "Mirroring repository ..."
    sleep 1
    mkdir bare-repo && cd bare-repo || exit
    git clone --bare -q "${GITHUB_URL}/${GITHUB_OWNER}/${REPOSITORY_NAME}.git"
    cd "${REPOSITORY_NAME}.git" || exit
    git push --mirror -q "${GITHUB_URL}/${GITHUB_OWNER}/${NEW_REPOSITORY}.git"
    cd ../..
    rm -rf bare-repo/
  fi
}

github_check_repository

function main() {
  
  case "$http_status" in
    200)
      # If the repository exist, migrate braching strategy.
      #printf "Migrating braching strategy type ...\n\n"
      github_check_branch
      github_convert_branch_type
      exit 0
      ;;
    401)
      # HTTP status code for GitHub bad credentials.
      printf "GitHub bad credentials, review your GITHUB PAT."
      exit 1
      ;;
    404)
      # HTTP status code for repository not found.
      printf "Repository not found!"
      exit 1
      ;;
  esac

}

main
