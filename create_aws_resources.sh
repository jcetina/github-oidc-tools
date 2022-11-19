#!/bin/bash
. common.sh

requirements_check
handle_aws_auth
create_aws_gh_oidc_provider