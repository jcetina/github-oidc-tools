#!/bin/bash

## General functions
command_check() {
    if ! command -v $1 &> /dev/null
    then
        echo "Please install $1"
        exit 1
    fi
}

confirm() {
    while true; do

        read -p "Do you want to proceed? (y/n) " yn

        case $yn in 
            [yY] ) echo ok, we will proceed;
                break;;
            [nN] ) echo exiting...;
                exit;;
            * ) echo invalid response;;
        esac

    done
}

requirements_check() {
    for cmd in gh jq aws az; do
        command_check $cmd
    done
}


## GitHub functions
get_default_branch() {
    gh api "repos/${1}/${2}" | jq -r '.default_branch'
}

get_gh_username() {
    gh api user | jq -r '.login'
}

handle_gh_auth() {
    echo "Checking GitHub CLI authentication status"
    if [ $(gh auth status) ]; then
        echo "Logging in to GitHub via CLI:"
        gh auth login
    fi
}

set_branch_protection() {
    echo "Setting branch protection for $1/$2 for branch $3"
    confirm
    gh api -X PUT "repos/${1}/${2}/branches/${3}/protection" \
        --input ./json/simple-branch-protection.json

}

set_collaborator() {
    echo "Setting $3 as a collaborator on $1/$2"
    confirm
    gh api -X PUT "repos/${1}/${2}/collaborators/${3}" \
        --input ./json/admin-permission.json
}

set_default_branch() {
    echo "Setting default branch for $1/$2 to $3"
    confirm
    gh api -X PATCH "repos/${1}/${2}" \
        --input <(echo '{"default_branch": "${3}"}')
}

## AWS functions
create_aws_gh_oidc_provider() {
    local arn=$(get_gh_oidc_arn)
    aws iam get-open-id-connect-provider --open-id-connect-provider-arn "${arn}" --profile $aws_profile
    if [ $? -eq 0 ]; then
        echo "OpenID Connect provider already exists"
    else
        echo "Creating AWS OIDC provider for GitHub"
        confirm
        aws iam create-open-id-connect-provider \
        --url https://token.actions.githubusercontent.com \
        --thumbprint-list 6938fd4d98bab03faadb97b34396831e3780aea1 \
        --profile $aws_profile        
    fi
}

get_account_id() {
    local account=$(aws sts get-caller-identity --query "Account" --output text --profile ${aws_profile})
    echo $account
}

get_gh_oidc_arn() {
    local aws_account=$(get_account_id)
    echo "arn:aws:iam::${aws_account}:oidc-provider/token.actions.githubusercontent.com"
}

handle_aws_auth() {
    echo "Checking AWS CLI authentication status"
    echo "The profile you choose requires IAM write permissions to create an OIDC provider, and various IAM roles and policies."
    echo "Here are your existing AWS profiles:"
    aws configure list-profiles
    read -p "What aws cli profile do you want to use? [default: None] " aws_profile
    aws sts get-caller-identity --profile $aws_profile
    if [ $? != 0 ]; then
        echo "Profile can not authenticate. Please check your credentials."
        exit
    fi
}




