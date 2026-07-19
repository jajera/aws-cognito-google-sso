# Requirements Document

## Introduction

This feature delivers a standalone, Terraform-first walkthrough that deploys Amazon Cognito Google SSO plus a basic AWS-hosted demo web app. It includes a two-step apply process to resolve the dependency between the Cognito Google IdP redirect URI and Google OAuth credentials, a README that can be followed from scratch, a vanilla JavaScript app on private S3 behind CloudFront that completes authorization-code + PKCE token exchange, and an optional Phase 2 pre-sign-up Lambda for email allowlisting.

## Glossary

- **Cognito_User_Pool**: The AWS Cognito User Pool resource that stores user identities and federation configuration
- **Cognito_Domain**: The hosted UI domain prefix attached to a Cognito User Pool, used to construct OAuth 2.0 endpoints
- **Google_Identity_Provider**: The Cognito Identity Provider resource configured for Google OAuth 2.0 federation
- **User_Pool_Client**: The Cognito App Client that defines allowed OAuth flows, scopes, and callback URLs
- **Demo_Web_App**: The vanilla HTML/CSS/JavaScript application uploaded to S3 and served through CloudFront
- **Web_App_URL**: The HTTPS CloudFront distribution URL that hosts the Demo_Web_App
- **Terraform_Module**: The collection of `.tf` files in the `infra/` directory that define all AWS resources
- **README_Walkthrough**: The README.md documentation that guides users through the entire setup process
- **Shell_Apply**: The first Terraform apply (Step A) that deploys Cognito, the web app hosting stack, and related outputs before Google credentials exist
- **Federation_Apply**: The second Terraform apply (Step C) that wires Google IdP credentials into the deployed infrastructure
- **Pre_Token_Lambda**: An optional Lambda function triggered before token generation to inject custom claims
- **Terraform_State**: The local terraform.tfstate file that contains resource metadata including sensitive values

## Requirements

### Requirement 1: Cognito User Pool Configuration

**User Story:** As a developer, I want Terraform to deploy a Cognito User Pool with native self-signup disabled and email as the username attribute, so that native users can only be created by an administrator and federated authentication can be delegated to Google.

#### Requirement 1 Acceptance Criteria

1. THE Terraform_Module SHALL deploy a Cognito_User_Pool with admin_create_user_config.allow_admin_create_user_only set to true
2. THE Terraform_Module SHALL configure email as the username attribute on the Cognito_User_Pool via username_attributes = ["email"]
3. THE Terraform_Module SHALL configure auto_verified_attributes to include email on the Cognito_User_Pool
4. THE Terraform_Module SHALL set mfa_configuration to OFF on the Cognito_User_Pool
5. THE Terraform_Module SHALL set deletion_protection to INACTIVE on the Cognito_User_Pool

### Requirement 2: Cognito User Pool Domain

**User Story:** As a developer, I want Terraform to create a globally unique Cognito domain prefix, so that the hosted UI endpoints are addressable without manual naming conflicts.

#### Requirement 2 Acceptance Criteria

1. THE Terraform_Module SHALL create a Cognito_Domain using a prefix that incorporates the AWS account ID or a random_id resource to ensure global uniqueness
2. THE Cognito_Domain prefix SHALL contain only lowercase letters, numbers, and hyphens, SHALL be between 1 and 63 characters, and SHALL NOT begin or end with a hyphen
3. WHEN the Cognito_Domain is created, THE Terraform_Module SHALL output the full domain URL in the format https://{prefix}.auth.{region}.amazoncognito.com for use in Google Console configuration

### Requirement 3: Google Identity Provider Resource

**User Story:** As a developer, I want Terraform to configure a Google Identity Provider on the User Pool with all provider_details defaults specified, so that subsequent applies do not produce plan drift.

#### Requirement 3 Acceptance Criteria

1. THE Terraform_Module SHALL create a Google_Identity_Provider resource of type "Google" on the Cognito_User_Pool
2. THE Terraform_Module SHALL accept google_client_id and google_client_secret as string input variables for the Google_Identity_Provider
3. THE Terraform_Module SHALL mark the google_client_secret variable as sensitive
4. THE Terraform_Module SHALL specify the following provider_details attributes explicitly on the Google_Identity_Provider to prevent plan drift: authorize_scopes, token_url, token_request_method, authorize_url, attributes_url, attributes_url_add_attributes, and oidc_issuer
5. THE Terraform_Module SHALL set authorize_scopes on the Google_Identity_Provider to include `openid` and `email`
6. THE Terraform_Module SHALL map the Google attribute "email" to the Cognito attribute "email", the Google attribute "sub" to the Cognito attribute "username", and the Google attribute "name" to the Cognito attribute "name" on the Google_Identity_Provider

### Requirement 4: User Pool Client Configuration

**User Story:** As a developer, I want Terraform to create a public User Pool Client configured for authorization code flow with Google as the only identity provider after federation is enabled, so that the hosted demo app can use OAuth 2.0 with PKCE without embedding a client secret.

#### Requirement 4 Acceptance Criteria

1. THE Terraform_Module SHALL create a User_Pool_Client with generate_secret set to false
2. THE Terraform_Module SHALL configure the User_Pool_Client with allowed_oauth_flows_user_pool_client set to true and allowed_oauth_flows set to ["code"] only
3. THE Terraform_Module SHALL set allowed_oauth_scopes to ["openid", "email"] on the User_Pool_Client
4. THE Terraform_Module SHALL set supported_identity_providers to ["Google"] on the User_Pool_Client when Google federation is enabled
5. THE Terraform_Module SHALL set callback_urls to the Web_App_URL root HTTPS URL on the User_Pool_Client
6. THE Terraform_Module SHALL set logout_urls to the Web_App_URL root HTTPS URL on the User_Pool_Client

### Requirement 5: Terraform Outputs

**User Story:** As a developer, I want Terraform to output all values needed to configure Google Cloud Console and open the hosted demo app, so that I can complete the setup without inspecting the AWS console.

#### Requirement 5 Acceptance Criteria

1. THE Terraform_Module SHALL output the user_pool_id value
2. THE Terraform_Module SHALL output the client_id value
3. THE Terraform_Module SHALL output the cognito_domain as a complete URL including the https:// scheme and the .auth.{region}.amazoncognito.com suffix
4. THE Terraform_Module SHALL output the google_redirect_uri value constructed as the cognito_domain URL appended with /oauth2/idpresponse
5. THE Terraform_Module SHALL output an authorize_url value with correctly URL-encoded `response_type=code`, `client_id`, `redirect_uri`, `scope=openid email`, and `identity_provider=Google` query parameters, where redirect_uri is the Web_App_URL
6. THE Terraform_Module SHALL output the javascript_origin value as the cognito_domain URL without a trailing slash or path, for use in Google Cloud Console OAuth client configuration
7. THE Terraform_Module SHALL output the web_app_url value as the HTTPS CloudFront distribution URL without a trailing slash

### Requirement 6: Two-Step Apply Process

**User Story:** As a developer, I want the Terraform configuration to support a two-step apply process, so that I can deploy the Cognito shell and web app first, configure Google Console with the output URIs, and then apply again to wire in Google federation.

#### Requirement 6 Acceptance Criteria

1. IF both google_client_id and google_client_secret are set to their default value of empty string (""), THEN THE Terraform_Module SHALL deploy the Cognito_User_Pool, Cognito_Domain, User_Pool_Client, Demo_Web_App hosting stack, and related outputs with supported_identity_providers set to COGNITO, without creating the Google_Identity_Provider (Shell_Apply)
2. IF both google_client_id and google_client_secret are set to non-empty string values, THEN THE Terraform_Module SHALL deploy the Google_Identity_Provider and configure the User_Pool_Client with supported_identity_providers set to Google (Federation_Apply)
3. THE Terraform_Module SHALL reject configurations in which exactly one of google_client_id or google_client_secret is empty
4. THE Terraform_Module SHALL output google_redirect_uri, javascript_origin, and web_app_url on every apply, including Shell_Apply
5. WHEN the Federation_Apply is executed after a Shell_Apply, THE Terraform_Module SHALL add the Google_Identity_Provider and update the User_Pool_Client in-place without destroying or recreating the Cognito_User_Pool, Cognito_Domain, User_Pool_Client, or CloudFront distribution resources
6. DURING Federation_Apply, THE Terraform_Module SHALL ensure that the Google_Identity_Provider is created before the User_Pool_Client is updated to reference Google

### Requirement 7: README Walkthrough Documentation

**User Story:** As a developer, I want a comprehensive README that documents the entire setup process from prerequisites to teardown, so that anyone can reproduce the demo from scratch without prior knowledge.

#### Requirement 7 Acceptance Criteria

1. THE README_Walkthrough SHALL include a section explaining what the demo teaches with an ASCII or Mermaid diagram showing the flow: Browser → Cognito managed login → Google sign-in → CloudFront demo app → Cognito token endpoint
2. THE README_Walkthrough SHALL include a prerequisites section listing AWS CLI v2 with configured credentials, Terraform >= 1.2, and access to a Google Cloud project in which OAuth credentials can be created
3. THE README_Walkthrough SHALL include Step A instructions with the exact terraform init and terraform apply commands to run from the infra/ directory
4. THE README_Walkthrough SHALL include numbered Google Cloud Console configuration steps with exact URI templates containing placeholder values derived from Terraform outputs (javascript_origin and google_redirect_uri)
5. THE README_Walkthrough SHALL include Step C instructions showing how to create terraform.tfvars with google_client_id and google_client_secret, then run terraform apply
6. THE README_Walkthrough SHALL include a test sign-in section instructing the user to open the web_app_url output, use Sign in with Google, and confirm that a successful flow displays authenticated user claims after PKCE token exchange
7. THE README_Walkthrough SHALL include a common failures troubleshooting section covering at minimum: redirect_uri_mismatch, wrong JavaScript origin, app client not Google-enabled, consent screen in Testing without test user, IdP provider_details perpetual plan drift, and CloudFront deployment delay
8. THE README_Walkthrough SHALL include teardown instructions with the exact terraform destroy command and confirmation that all resources are removed
9. THE README_Walkthrough SHALL include an optional appendix describing the email allowlist pre-sign-up Lambda configuration

### Requirement 8: Project Layout and Security

**User Story:** As a developer, I want the project to follow a clean directory structure with secrets excluded from version control, so that the demo is organized and safe to share publicly.

#### Requirement 8 Acceptance Criteria

1. THE Terraform_Module SHALL be organized under an infra/ directory containing versions.tf, providers.tf, variables.tf, main.tf, and outputs.tf
2. THE Terraform_Module SHALL include a terraform.tfvars.example file within the infra/ directory listing all required input variables (google_client_id, google_client_secret, and region) with non-functional placeholder values that are clearly not valid credentials
3. THE Terraform_Module SHALL include a .gitignore file within the infra/ directory that excludes terraform.tfvars, `.terraform/`, all local Terraform state files, and crash logs
4. THE README_Walkthrough SHALL include a warning that marking google_client_secret as sensitive only redacts CLI output and that the value remains stored in Terraform state; it SHALL recommend restricting access to the state file
5. THE Terraform_Module SHALL use a local backend for Terraform state
6. THE Demo_Web_App source SHALL live under a `web/` directory at the repository root and SHALL NOT contain secrets or private keys

### Requirement 9: Region and Cost Constraints

**User Story:** As a developer, I want the deployment to default to ap-southeast-2 with low-cost, minimal infrastructure, so that the demo is inexpensive to run and easy to destroy.

#### Requirement 9 Acceptance Criteria

1. THE Terraform_Module SHALL accept a region variable of type string with a default value of "ap-southeast-2"
2. THE Terraform_Module SHALL NOT include any resource blocks of type aws_vpc, aws_apigatewayv2_api, aws_api_gateway_rest_api, aws_dynamodb_table, or aws_sqs_queue
3. THE Terraform_Module SHALL set deletion_protection to INACTIVE on the Cognito_User_Pool and SHALL NOT set prevent_destroy lifecycle rules on any resource
4. THE README_Walkthrough SHALL state that AWS and Google pricing can change and SHALL direct users to current Cognito, S3, CloudFront, and Lambda pricing rather than promising zero cost

### Requirement 10: End-to-End Acceptance Validation

**User Story:** As a developer, I want the demo to be validated end-to-end, so that I am confident the walkthrough works as documented.

#### Requirement 10 Acceptance Criteria

1. WHEN the Shell_Apply is executed in an AWS account with no pre-existing Cognito resources in the target region, THE Terraform_Module SHALL exit with code 0 and produce outputs including cognito_domain, google_redirect_uri, javascript_origin, and web_app_url
2. WHEN Google OAuth credentials are created using the google_redirect_uri and javascript_origin from Shell_Apply outputs, THE Google Cloud OAuth client configuration SHALL accept those values as an Authorized Redirect URI and Authorized JavaScript Origin respectively
3. WHEN the Federation_Apply is executed with valid google_client_id and google_client_secret, THE Terraform_Module SHALL exit with code 0 and the User_Pool_Client shall list Google as a supported identity provider
4. WHEN a subsequent terraform plan is executed after Federation_Apply with no variable changes, THE Terraform_Module SHALL report zero resource changes
5. WHEN a user opens the web_app_url and completes Google sign-in, THE Demo_Web_App SHALL exchange the authorization code using PKCE and display authenticated identity claims from the ID token
6. WHEN terraform destroy is executed, THE Terraform_Module SHALL exit with code 0 and remove all deployed resources leaving zero resources in the Terraform state

### Requirement 11: Pre-Sign-Up Email Allowlist Lambda (Optional Phase 2)

**User Story:** As a developer, I want an optional Lambda that restricts federated sign-up to a configured list of email addresses, so that unauthorized Google accounts are rejected before Cognito creates a user.

#### Requirement 11 Acceptance Criteria

1. WHERE the Email_Allowlist_Lambda feature is enabled via a boolean Terraform variable, THE Terraform_Module SHALL deploy a Lambda function with an IAM execution role, triggered by the Cognito pre-sign-up event
2. WHERE the Email_Allowlist_Lambda feature is enabled, THE Email_Allowlist_Lambda SHALL compare the authenticated email against a list of addresses provided via a Terraform variable
3. WHERE the Email_Allowlist_Lambda feature is enabled, IF the authenticated email matches any configured allowlist address, THEN THE Email_Allowlist_Lambda SHALL auto-confirm and auto-verify the email for the federated sign-up
4. WHERE the Email_Allowlist_Lambda feature is enabled, IF the authenticated email does not match any configured allowlist address, THEN THE Email_Allowlist_Lambda SHALL deny sign-up with an error message indicating the email is not authorized
5. WHERE the Email_Allowlist_Lambda feature is enabled, THE Terraform_Module SHALL grant Cognito permission to invoke the Lambda function via a resource-based policy
6. WHERE the Email_Allowlist_Lambda feature is enabled, THE Terraform_Module SHALL require a non-empty allowlist and SHALL validate that each entry is syntactically an email address
7. WHERE the Email_Allowlist_Lambda feature is disabled, THE Terraform_Module SHALL deploy no Lambda or Lambda IAM resources and SHALL configure no Lambda trigger on the Cognito_User_Pool
8. WHERE the Email_Allowlist_Lambda feature is enabled, THE Terraform_Module SHALL use the AWS Lambda `nodejs24.x` managed runtime

### Requirement 12: AWS-Hosted Demo Web Application

**User Story:** As a developer, I want a basic HTTPS web app hosted in AWS that completes Google SSO through Cognito with PKCE, so that I can verify the full browser sign-in and token exchange without running a local server.

#### Requirement 12 Acceptance Criteria

1. THE Terraform_Module SHALL deploy a private S3 bucket with all public access blocked and object ownership set so that the Demo_Web_App assets are not publicly readable from S3 URLs
2. THE Terraform_Module SHALL deploy a CloudFront distribution with Origin Access Control that signs requests to the S3 origin and redirects HTTP viewers to HTTPS
3. THE Terraform_Module SHALL upload the Demo_Web_App static assets and a generated config file containing Cognito domain, client ID, and Web_App_URL values with no secrets
4. THE Demo_Web_App SHALL implement the OAuth 2.0 authorization code flow with PKCE, including generation of code_verifier, code_challenge (S256), and an opaque state value
5. WHEN the Demo_Web_App receives an authorization code and matching state, THEN it SHALL exchange the code at the Cognito token endpoint using the code_verifier and SHALL display selected ID token claims without storing tokens in localStorage
6. WHEN the Demo_Web_App receives an OAuth error or token exchange failure, THEN it SHALL display a generic error message without echoing secrets or full tokens
7. THE Demo_Web_App SHALL provide a sign-out control that redirects through the Cognito logout endpoint back to the Web_App_URL
8. THE Terraform_Module SHALL set force_destroy = true on the Demo_Web_App S3 bucket so that terraform destroy removes the bucket even when it still contains uploaded objects
