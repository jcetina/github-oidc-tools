#!/bin/bash
. common.sh

OIDC_TOOLS_TEMPDIR=$(mktemp -d)
mkdir -p $OIDC_TOOLS_TEMPDIR/repo_source/.github/workflows

requirements_check
handle_aws_auth
handle_gh_auth




read -p "What org do you want to create the repo in? " org
read -p "What do you want to name the repo? " repo
read -p "What do you maint to name the main branch? [default: main] " branch
branch=${branch:-main}

### AWS Resource Creation
create_aws_gh_oidc_provider json/github-aws-oidc-config.json
OIDC_ARN=$(get_gh_oidc_arn)
sed 's|OIDC_PROVIDER_ARN|'"${OIDC_ARN}"'|g' json/assume-role-policy-doc.json > $OIDC_TOOLS_TEMPDIR/assume-role-policy-doc.json
sed -i '' 's/ORG/'"${org}"'/g' "${OIDC_TOOLS_TEMPDIR}/assume-role-policy-doc.json"
sed -i '' 's/REPO/'"${repo}"'/g' "${OIDC_TOOLS_TEMPDIR}/assume-role-policy-doc.json"
sed -i '' 's/BRANCH/'"${branch}"'/g' "${OIDC_TOOLS_TEMPDIR}/assume-role-policy-doc.json"
OIDC_TOOLS_ROLE_NAME="org-${org}-repo-${repo}-oidc-role"
create_iam_role $OIDC_TOOLS_ROLE_NAME $OIDC_TOOLS_TEMPDIR/assume-role-policy-doc.json

### GitHub Repo Creation
gh repo create $org/$repo --public --confirm
set_custom_oidc_template $org $repo

#Configure and commit the workflow after custom oidc claims are set
OIDC_TOOLS_AWS_ACCOUNT_ID=$(get_account_id)
OIDC_TOOLS_ROLE_ARN="arn:aws:iam::${OIDC_TOOLS_AWS_ACCOUNT_ID}:role/${OIDC_TOOLS_ROLE_NAME}"
sed 's|AWS_ROLE_TO_ASSUME|'"${OIDC_TOOLS_ROLE_ARN}"'|g' workflows/aws-caller-id.yml > $OIDC_TOOLS_TEMPDIR/repo_source/.github/workflows/aws-caller-id.yml
sed -i '' 's|BRANCH|'"${branch}"'|g' $OIDC_TOOLS_TEMPDIR/repo_source/.github/workflows/aws-caller-id.yml
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
