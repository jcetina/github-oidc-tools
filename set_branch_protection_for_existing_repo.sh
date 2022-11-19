#!/bin/bash

. ./common.sh

requirements_check
handle_gh_auth

read -p "What org is the target repo in? " org
read -p "What repo is the target branch in? " repo
read -p "What branch to you want to protect? [default: main] " branch
branch=${branch:-main}

set_branch_protection $org $repo $branch

echo "Done!"