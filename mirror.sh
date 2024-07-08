#!/usr/bin/env bash

#set -euo pipefail
#set -x

if [ "$#" -lt 1 ]; then
  echo "Missing arguments."
  exit 1
fi

GITHUB_URL="https://github.com"
GITHUB_API_URL=${GITHUB_URL/https:\/\//https:\/\/api.}
GITHUB_OWNER="$(echo "$1" | cut -d'/' -f 1)"
GITHUB_REPO="$(echo "$1" | cut -d'/' -f 2)"

function fetch_repository() {

  if [ -z "$GITHUB_AUTH_TOKEN" ]; then
    echo "GitHub PAT token is not defined!"
    exit 1
  fi

  fetch_repository=$(curl -sL \
    -H "Accept: application/vnd.github+json" \
    -H "Authorization: token ${GITHUB_AUTH_TOKEN}" \
    -H "X-GitHub-Api-Version: 2022-11-28" \
    "${GITHUB_API_URL}/repos/${GITHUB_OWNER}/${GITHUB_REPO}")

  # GitHub repo HTTP status code
  HTTP_STATUS=$(echo "$fetch_repository" | jq -r 'if .message == "Not Found" then "404" elif .message == "Bad credentials" then "401" else "200" end')

  # GitHub repo metadata
  if [ "$HTTP_STATUS" -eq 200 ]; then
    FETCH_JSON="$fetch_repository"
    REPOSITORY_NAME=$(echo "$fetch_repository" | jq -r '.name')
    REPOSITORY_FULL_NAME=$(echo "$fetch_repository" | jq -r '.full_name')
    REPOSITORY_DESCRIPTION=$(echo "$fetch_repository" | jq -r '.description')
    REPOSITORY_PR_COUNT=$(echo "$fetch_repository" | jq -r '.open_issues_count')
    REPOSITORY_TOPICS=$(echo "$fetch_repository" | jq -r '.topics[]' | paste -sd ',')
    REPOSITORY_TEMPLATE=$(echo "$fetch_repository" | jq -r '.is_template')
    REPOSITORY_VISIBILITY=$(echo "$fetch_repository" | jq -r '.visibility')
    REPOSITORY_API_URL=$(echo "$fetch_repository" | jq -r '.url')
    REPOSITORY_ORG=$(echo "$fetch_repository" | jq -r 'if .organization then "true" else "false" end')
  fi
}

# Repository environments
# This function will get all
# deployment environments from a repository.
function environments() {
  environments_url="${1/%/\/environments}"

  fetch=$(curl -sL \
    -H "Accept: application/vnd.github+json" \
    -H "Authorization: Bearer ${GITHUB_AUTH_TOKEN}" \
    -H "X-GitHub-Api-Version: 2022-11-28" \
    "$environments_url")

  is_empty=$(echo "$fetch" | jq -r 'if (. == [] or (.message? == "Not Found")) then "true" else "false" end // "false"')
  has_environments=false

  echo -e "\nFetch environments ..."
  sleep 1
  echo
  if [ "$is_empty" == "true" ]; then
    echo "No environments found!"
    has_environments=false
  else
    environments=$(echo "$fetch" | jq -r '.environments[].name' | sort)
    total_count=$(echo "$fetch" | jq -r '.total_count')
    has_environments=true

    # Test if environments is a empty string.
    if [ -z "$environments" ]; then
      echo "No environments found!"
      return 0
    fi
    
    if [ "$total_count" -eq 3 ]; then
      environment_type="git-flow"
    else
      environment_type="github-flow"
    fi
    echo "$environments"
  fi
}

# Repository secrets
# This function will get all
# secrets from a repository.
function secrets() {
  secrets_url="${1/%/\/actions\/secrets}"

  fetch=$(curl -sL \
    -H "Accept: application/vnd.github+json" \
    -H "Authorization: Bearer ${GITHUB_AUTH_TOKEN}" \
    -H "X-GitHub-Api-Version: 2022-11-28" \
    "$secrets_url")

  is_empty=$(echo "$fetch" | jq -r 'if .secrets == [] then "true" else "false" end')

  echo -e "\nFetching secrets ..."
  echo
  sleep 1
  if [ "$is_empty" == "true" ]; then
    echo "No secrets found!"
  else
    secrets=$(echo "$fetch" | jq -r '.secrets[] | "\(.name)=sensitive-value"')
    total_count=$(echo "$fetch" | jq -r '.total_count')
    echo "$secrets"
  fi
}

# Repository teams
# This function will get all teams
# from the repository.
function teams() {
  teams_url="${1/%/\/teams}"

  fetch=$(curl -sL \
    -H "Accept: application/vnd.github+json" \
    -H "Authorization: Bearer ${GITHUB_AUTH_TOKEN}" \
    -H "X-GitHub-Api-Version: 2022-11-28" \
    "$teams_url")

  is_empty=$(echo "$fetch" | jq -r 'if (. == [] or (.message? == "Not Found")) then "true" else "false" end // "false"')

  echo -e "\nFetching teams ..."
  echo
  sleep 1
  if [ "$is_empty" == "true" ]; then
    echo "No teams found!"
    PRODUCT_TEAM_SLUG="NA"
  else
    team_prefix_filter=$(echo "$REPOSITORY_NAME" | sed -E 's/^(([^-]*-){1,2}).*/\1/' | sed 's/-$//')
    team_slug=$(echo "$fetch" | jq -r '.[] | "\(.parent.slug)=\(.slug)/\(.name)"')
    filter=$(echo "$team_slug" | grep -E "$team_prefix_filter")

    if [[ "$filter" =~ $team_prefix_filter ]]; then
      slug=$(echo "$filter" | cut -d'=' -f1)
      count_slug=$(echo "$slug" | wc -l)
      if [ "$count_slug" -ge 2 ]; then
        PRODUCT_TEAM_SLUG=$(echo "$slug" | awk 'NR==1')
        echo "$PRODUCT_TEAM_SLUG"
      else
        PRODUCT_TEAM_SLUG="$slug"
        echo "$PRODUCT_TEAM_SLUG"
      fi
    else
      PRODUCT_TEAM_SLUG="NA"
      echo "Failed to match product team slug!"
    fi
    return 0
  fi
}

# Repository variables
# This function get all variables at repository level
# and find by RUNNER_VARS variables
# RUNNER_GROUP and RUNNER_LABELS.
function variables() {
  variables_url="${1/%/\/actions\/variables}"

  fetch=$(curl -sL \
    -H "Accept: application/vnd.github+json" \
    -H "Authorization: Bearer ${GITHUB_AUTH_TOKEN}" \
    -H "X-GitHub-Api-Version: 2022-11-28" \
    "$variables_url")

  is_empty=$(echo "$fetch" | jq -r 'if .variables == [] then "true" else "false" end')

  echo -e "\nFetching variables ..."
  echo
  sleep 1
  if [ "$is_empty" == "true" ]; then
    echo "No variables found!"
    RUNNER_GROUP="NA"
    RUNNER_LABELS="NA"
  else
    RUNNER_GROUP_FILTER=$(echo "$fetch" | jq -r '.variables[] | select(.name == "RUNNER_GROUP") | "\(.name)=\(.value)"')
    RUNNER_LABEL_FILTER=$(echo "$fetch" | jq -r '.variables[] | select(.name == "RUNNER_LABELS") | "\(.name)=\(.value)"')
    if [ -n "$RUNNER_GROUP_FILTER" ] && [ -n "$RUNNER_LABEL_FILTER" ]; then
      echo "Runner variables are defined."
      RUNNER_GROUP=$(echo "$RUNNER_GROUP_FILTER" | awk 'NR==1' | cut -d'=' -f2)
      RUNNER_LABELS=$(echo "$RUNNER_LABEL_FILTER" | awk 'NR==2' | cut -d'=' -f2 | cut -d'"' -f2)
    else
      echo "Runner variables are not defined."
    fi
    return 0
  fi
}

# Create repository
# This functions will create the target repository
# using the metadata outputs.
function create_repository() {
  dest_repo_url="${1/%/--migrate}"
  dest_repo_name="${2/%/--migrate}"
  dest_repo_description="$3"
  dest_repo_topics="$4"
  is_org="$5"

  if [ "$dest_repo_description" == "null" ]; then
    dest_repo_description="Repository migrate testing!"
  fi

  if [ -z "${dest_repo_topics:-}" ]; then
    dest_repo_topics="migrate"
  fi

  if [ "$is_org" == "true" ]; then
    url="${GITHUB_API_URL}/orgs/${GITHUB_OWNER}/repos"
  else
    url="${GITHUB_API_URL}/user/repos"
  fi

  echo -e "\nCreating repository ..."
  sleep 1
  curl -sL \
    -H "Accept: application/vnd.github+json" \
    -H "Authorization: token ${GITHUB_AUTH_TOKEN}" \
    -H "X-GitHub-Api-Version: 2022-11-28" \
    "$url" \
    -d "{
         \"name\": \"${dest_repo_name}\",
         \"description\": \"${dest_repo_description}\",
         \"auto_init\": \"true\"
       }" \
    -o /dev/null

  format_topics=$(echo "$dest_repo_topics" | jq -R 'split(",") | {names: .}')

  echo "Add topics ..."
  sleep 1
  curl -sL \
    -X PUT \
    -H "Accept: application/vnd.github+json" \
    -H "Authorization: token ${GITHUB_AUTH_TOKEN}" \
    -H "X-GitHub-Api-Version: 2022-11-28" \
    "${dest_repo_url}/topics" \
    -d "$format_topics" \
    -o /dev/null
}

# Mirroring repository
# This function will mirror the source repository
# to target repository.
# https://docs.github.com/en/repositories/creating-and-managing-repositories/duplicating-a-repository
function mirror() {
  clone_url="${1/api.github.com\/repos/github.com}.git"
  mirror_url="${1/api.github.com\/repos/github.com}--migrate.git"

  echo "Mirroring repository ..."
  sleep 1

  mkdir source-repo && cd source-repo || exit
  git clone --bare -q "$clone_url"
  cd "${REPOSITORY_NAME}.git" || exit
  git push --mirror -q "$mirror_url"
  cd ../..
  rm -rf source-repo/
}

# Archive source repository
# This function use `gh` to archive source repository.
function archive() {
  repo_full_name="$1"
  
  if ! hash gh 2> /dev/null; then
    echo "error: you do not have 'gh' installed which is required for this script."
    exit 1
  fi
  
  echo "Archiving source repository ..."
  gh repo archive "$repo_full_name" -y > /dev/null 2>&1
}

# Repository metadata
# This function will display
# all variables obtained from the fetch_repository function.
function display() {
  if [ "$HTTP_STATUS" -eq 200 ]; then
    echo
    echo "--------------------------"
    printf "SOURCE REPOSITORY METADATA\n"
    printf "Repository: %s\n" "$REPOSITORY_FULL_NAME"
    printf "Repository description: %s\n" "$REPOSITORY_DESCRIPTION"
    printf "Repository open PR: %s\n" "$REPOSITORY_PR_COUNT"
    printf "Repository template: %s\n" "${REPOSITORY_TEMPLATE^}"
    printf "Repository visibility: %s\n" "${REPOSITORY_VISIBILITY^}"
    printf "Repository topics: %s\n" "${REPOSITORY_TOPICS}"
    printf "Repository clone URL: %s\n" "${REPOSITORY_API_URL/api.github.com\/repos/github.com}.git"
    printf "Repository organization: %s\n" "${REPOSITORY_ORG^}"
    echo "--------------------------"
    #printf "%s\n" "$FETCH_JSON"
    #echo -e "./create-repository.sh \n --name '$REPOSITORY_NAME-migrate' \n --description '$REPOSITORY_DESCRIPTION' \n --team '$PRODUCT_TEAM_SLUG' \n --code-type 'NA' \n --topics '$REPOSITORY_TOPICS' \n --runner-group '$RUNNER_GROUP' \n --runner-labels '$RUNNER_LABELS'"
  else
    echo "No metadata fetched!"
    exit 1
  fi
}

# Fetch metadata.
fetch_repository
display

# Fetch GitHub objects.
environments "$REPOSITORY_API_URL"
secrets "$REPOSITORY_API_URL"
variables "$REPOSITORY_API_URL"
teams "$REPOSITORY_API_URL"

# Create, mirror and archive repository.
#create_repository "$REPOSITORY_API_URL" "$REPOSITORY_NAME" "$REPOSITORY_DESCRIPTION" "$REPOSITORY_TOPICS" "$REPOSITORY_ORG"
#mirror "$REPOSITORY_API_URL"
#archive "$REPOSITORY_FULL_NAME"
