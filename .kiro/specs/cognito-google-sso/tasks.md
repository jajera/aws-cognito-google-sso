# Implementation Plan: Cognito Google SSO

## Overview

This plan implements a Terraform-first walkthrough that deploys Amazon Cognito Google SSO plus a vanilla JavaScript demo app on private S3 behind CloudFront. It uses a two-step apply (Shell_Apply then Federation_Apply), PKCE in the browser, an optional Phase 2 pre-sign-up email allowlist Lambda on `nodejs24.x`, and a README as the primary deliverable.

## Tasks

- [x] 1. Set up project structure and Terraform foundation
  - [x] 1.1 Create infra/versions.tf with terraform block and required_providers
  - [x] 1.2 Create infra/providers.tf with AWS provider configuration
  - [x] 1.3 Create infra/variables.tf with all input variables
  - [x] 1.4 Create infra/.gitignore
  - [x] 1.5 Create infra/terraform.tfvars.example with placeholder values

- [x] 2. Implement core Cognito resources in main.tf
  - [x] 2.1 Create infra/main.tf with locals, random_id, and Cognito User Pool
  - [x] 2.2 Add Cognito Domain resource to main.tf
  - [x] 2.3 Add Google Identity Provider resource to main.tf
  - [x] 2.4 Add User Pool Client resource to main.tf

- [x] 3. Implement Cognito outputs
  - [x] 3.1 Create infra/outputs.tf with Cognito and Google Console outputs

- [x] 4. Checkpoint — Validate Shell_Apply configuration (pre-web-app baseline)

- [x] 5. Implement Phase 2 pre-sign-up email allowlist Lambda
  - [x] 5.1 Create infra/lambda/index.mjs with the pre-sign-up handler
  - [x] 5.2 Add Lambda resources and user-pool trigger to main.tf
  - [x] 5.3 Add fixture-based unit tests for the Lambda handler

- [x] 6. Checkpoint — Validate full Terraform configuration (pre-web-app)

- [x] 7. Create initial README walkthrough documentation

- [x] 9. Add AWS-hosted demo web app
  - [x] 9.1 Create web/ static assets (index.html, styles.css, app.js)
    - Implement Sign in with Google, PKCE, token exchange, claim display, sign-out
    - Keep tokens in memory; store only PKCE verifier/state in sessionStorage
    - _Requirements: 12.4, 12.5, 12.6, 12.7, 8.6_

  - [x] 9.2 Add S3 + CloudFront hosting resources to main.tf
    - Private S3 bucket with public access blocked
    - CloudFront OAC (`signing_behavior = always`), HTTPS redirect, default root object
    - Bucket policy scoped to the distribution ARN
    - Upload web assets and generated config.js (no secrets)
    - Point Cognito callback_urls and logout_urls at web_app_url
    - _Requirements: 4.5, 4.6, 12.1, 12.2, 12.3_

  - [x] 9.3 Update outputs.tf for web_app_url and CloudFront redirect_uri
    - Output `web_app_url`
    - Update authorize_url redirect_uri to Web_App_URL
    - _Requirements: 5.5, 5.7, 6.4_

  - [x] 9.4 Add web/app.test.mjs unit tests for PKCE helpers and claim decoding
    - _Requirements: 12.4, 12.5_

- [x] 10. Update README for hosted app flow
  - Document web_app_url-based test sign-in, PKCE, CloudFront delay, S3/CloudFront pricing
  - Remove localhost connection-error guidance
  - _Requirements: 7.1, 7.6, 7.7, 7.8, 9.4_

- [x] 11. Checkpoint — Validate hosted-app Terraform and tests
  - `terraform fmt`, `terraform validate`, `terraform test`
  - Assert hosting resources and CloudFront callback URLs in mock tests
  - Run Lambda and web app unit tests
  - _Requirements: 6.1, 12.1, 12.2_

- [x] 8. Final checkpoint — End-to-end acceptance validation
  - Shell_Apply outputs include cognito_domain, google_redirect_uri, javascript_origin, web_app_url
  - Federation_Apply and clean plan
  - Open web_app_url, complete Google sign-in, confirm claims displayed after PKCE exchange
  - `terraform destroy` leaves empty state
  - _Requirements: 10.1, 10.2, 10.3, 10.4, 10.5, 10.6_

## Notes

- CloudFront is intentionally included for HTTPS demo hosting; VPC, API Gateway, DynamoDB, and SQS remain excluded
- Live AWS/Google E2E (task 8) requires credentials and is not automated in CI
- Phase 2 Lambda remains optional at runtime

## Task Dependency Graph

```json
{
  "waves": [
    { "id": 0, "tasks": ["9.1"] },
    { "id": 1, "tasks": ["9.2", "9.3"] },
    { "id": 2, "tasks": ["9.4", "10"] },
    { "id": 3, "tasks": ["11"] },
    { "id": 4, "tasks": ["8"] }
  ]
}
```
