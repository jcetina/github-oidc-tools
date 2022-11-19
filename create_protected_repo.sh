#!/bin/bash
. ./common.sh

requirements_check
handle_gh_auth

read -p "What org do you want to create the repo in? " org
read -p "What do you want to name the repo? " repo
read -p "What do you maint to name the main branch? [default: main] " branch
branch=${branch:-main}


gh repo create $org/$repo --public --confirm --add-readme
gh_username=$(get_gh_username)
set_collaborator $org $repo $gh_username
if [ "${branch}" != "main" ]; then
    set_default_branch $org $repo $branch
fi
set_branch_protection $org $repo $branch
