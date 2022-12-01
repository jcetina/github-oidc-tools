#!/bin/bash
. common.sh

check_codespaces
OIDC_TOOLS_TEMPDIR=$(mktemp -d)
mkdir -p $OIDC_TOOLS_TEMPDIR/repo_source/.github/workflows

requirements_check
handle_azure_auth
handle_gh_auth

read -p "What org do you want to create the repo in? " org
read -p "What do you want to name the repo? " repo
read -p "What do you maint to name the main branch? [default: main] " branch
branch=${branch:-main}

# ### Azure Resource Creation
OIDC_TOOLS_APP_NAME="org-${org}-repo-${repo}"
create_azure_ad_app $OIDC_TOOLS_APP_NAME
create_azure_ad_sp $OIDC_TOOLS_APP_NAME

OIDC_TOOLS_RG_NAME="org-${org}-repo-${repo}-rg"
create_azure_rg $OIDC_TOOLS_RG_NAME
create_role_assignment $OIDC_TOOLS_APP_NAME

sed 's|BRANCH|'"${branch}"'|g' ./json/fics.json > $OIDC_TOOLS_TEMPDIR/fics.json
sed -i '' 's|ORG|'"${org}"'|g' $OIDC_TOOLS_TEMPDIR/fics.json
sed -i '' 's|REPO|'"${repo}"'|g' $OIDC_TOOLS_TEMPDIR/fics.json
created_federated_creds $OIDC_TOOLS_TEMPDIR/fics.json

# ### GitHub Repo Creation
gh repo create $org/$repo --public --confirm
set_custom_oidc_template $org $repo

# #Configure and commit the workflow after custom oidc claims are set
OIDC_TOOLS_AZ_TENANT_ID=$(get_tenant_id)
sed 's|BRANCH|'"${branch}"'|g' workflows/azure-account-show.yml > $OIDC_TOOLS_TEMPDIR/repo_source/.github/workflows/azure-account-show.yml
set_azure_secrets $org $repo
OIDC_TOOLS_PWD=$(pwd)
cd $OIDC_TOOLS_TEMPDIR/repo_source/
git init -b "${branch}"
git add .
git commit -m "Initial commit"
git remote add origin "https://github.com/${org}/${repo}.git"
git push -u origin "${branch}"
cd "${OIDC_TOOLS_PWD}"

# Give gh logged in user access to the repo
# gh_username=$(get_gh_username)
# set_collaborator $org $repo $gh_username

# Apply branch protection
if [ "${branch}" != "main" ]; then
    set_default_branch $org $repo $branch
fi
set_branch_protection $org $repo $branch

# sleeping a few seconds so the action can register
sleep 3
open "https://github.com/${org}/${repo}/actions"
