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
check_codespaces() {
    IS_CODESPACE=${CODESPACES:-"false"}
    if $IS_CODESPACE == "true"
    then
        echo "This script doesn't work in GitHub Codespaces.  See this issue for updates. https://github.com/Azure/azure-cli/issues/21025 "
        exit 0
    fi
}

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

# set_collaborator() {
#     echo "Setting $3 as a collaborator on $1/$2"
#     confirm
#     gh api -X PUT "repos/${1}/${2}/collaborators/${3}" \
#         --input ./json/admin-permission.json
# }

set_default_branch() {
    echo "Setting default branch for $1/$2 to $3"
    confirm
    gh api -X PATCH "repos/${1}/${2}" \
        --input <(echo '{"default_branch": "${3}"}')
}

set_custom_oidc_template() {
    echo "Setting custom OIDC template for $1/$2"
    confirm
    gh api -X PUT "repos/${1}/${2}/actions/oidc/customization/sub" \
     --input json/custom-subject-claims.json
}

set_repo_secret() {
    gh secret set $1 --body "${2}" --repo "${3}/${4}"
    if [ $? -eq 1 ]; then
        echo "Failed to set secret. Exiting."
    fi
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
        --cli-input-json file://$1 \
        --profile $aws_profile        
    fi
}

create_iam_role() {
    aws iam get-role --role-name $1 --profile $aws_profile
    if [ $? -eq 0 ]; then
        echo "IAM role already exists"
    else
        echo "Creating IAM role $1"
        confirm
        aws iam create-role \
            --role-name $1 \
            --assume-role-policy-document file://$2 \
            --profile $aws_profile 2>&1 > /dev/null
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

## Azure functions
azure_login() {
    echo "Logging in to Azure"
    az login
    if [ $? != 0 ]; then
        echo "Login failed. Please check your credentials."
        exit
    fi
}

handle_azure_auth() {
    echo "Checking Azure CLI authentication status"
    echo "The profile you choose requires Azure AD write permissions to create the proper Azure IAM resources."
    echo "Checking login status:"
    az ad signed-in-user show
    if [ $? != 0 ]; then
        echo "You are not logged in. Please log in to Azure CLI."
        azure_login
    fi
    az account list --query "[].[id, name]" -o table
    echo "This script will create a resource group in this subscription, and grant the identity for your repo admin access to it."
    read -p "Please select a subscription uuid from the list above? [default: None] " azure_subscription
    az account show -s $azure_subscription
    if [ $? != 0 ]; then
        echo "Invalid subscription entered. Exiting."
        exit
    fi
}

create_azure_ad_app() {
    echo "Creating AD app ${1}"
    confirm
    APP_ID=$(az ad app create --display-name ${1} --query appId -o tsv)
    if [ $? != 0 ]; then
        echo "App creation failed. Exiting."
        exit
    fi
    echo "Sleeping for 30 seconds to give time for the APP to be created."
    sleep 30
}

create_azure_ad_sp() {
    echo "Creating Service Principal for ${1}"
    confirm
    SP_ID=$(az ad sp create --id $APP_ID --query id -o tsv)

    if [ $? != 0 ]; then
        echo "SP creation failed. Exiting."
        exit
    fi
    echo "Sleeping for 30 seconds to give time for the SP to be created."
    sleep 30
}

create_azure_rg() {
    echo "Creating resource group ${1}"
    confirm
    RG_ID=$(az group create --name "${1}" --location eastus --subscription $azure_subscription --query id -o tsv)
    if [ $? != 0 ]; then
        echo "Resource group creation failed. Exiting."
        exit
    fi
    echo "Sleeping for 30 seconds to give time for the RG to be created."
    sleep 30
}

create_role_assignment() {
    echo "Creating role assignment for ${1}"
    confirm
    az role assignment create --assignee "${SP_ID}" --role "Contributor" --scope "${RG_ID}"
    if [ $? != 0 ]; then
        echo "Role assignment failed. Exiting."
        exit
    fi
}

created_federated_creds() {
    for FIC in $(cat "${1}" | jq -c '.[]'); do
        SUBJECT=$(jq -r '.subject' <<< "$FIC")
        
        echo "Creating FIC with subject '${SUBJECT}'."
        az ad app federated-credential create --id  $APP_ID --parameters ${FIC}
        if [ $? != 0 ]; then
            echo "FIC creation failed. Exiting."
            exit
        fi
    done
}

get_tenant_id() {
    az account show --query tenantId -o tsv
}

set_azure_secrets() {
    TENANT_ID=$(az account show --query tenantId -o tsv)
    set_repo_secret "AZURE_CLIENT_ID" "${APP_ID}" "${1}" "${2}"
    set_repo_secret "AZURE_SUBSCRIPTION_ID" "${azure_subscription}" "${1}" "${2}"
    set_repo_secret "AZURE_TENANT_ID" "${TENANT_ID}" "${1}" "${2}"
}
