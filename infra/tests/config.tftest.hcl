mock_provider "archive" {}
mock_provider "aws" {}
mock_provider "random" {}

override_resource {
  target          = aws_cloudfront_distribution.web
  override_during = plan
  values = {
    domain_name = "d111111abcdef8.cloudfront.net"
  }
}

run "shell_apply_plan" {
  command = plan

  variables {
    google_client_id              = ""
    google_client_secret          = ""
    enable_email_allowlist_lambda = false
    allowed_emails                = []
  }

  assert {
    condition     = length(aws_cognito_identity_provider.google) == 0
    error_message = "Shell_Apply must not create the Google identity provider."
  }

  assert {
    condition     = contains(aws_cognito_user_pool_client.main.supported_identity_providers, "COGNITO")
    error_message = "Shell_Apply must temporarily enable the COGNITO provider."
  }

  assert {
    condition     = length(aws_lambda_function.email_allowlist) == 0
    error_message = "Lambda resources must be absent by default."
  }

  assert {
    condition     = aws_s3_bucket_public_access_block.web.restrict_public_buckets
    error_message = "The demo web bucket must block public access."
  }

  assert {
    condition     = aws_cloudfront_origin_access_control.web.signing_behavior == "always"
    error_message = "CloudFront OAC must always sign origin requests."
  }

  assert {
    condition     = aws_cloudfront_distribution.web.default_cache_behavior[0].viewer_protocol_policy == "redirect-to-https"
    error_message = "CloudFront must redirect HTTP viewers to HTTPS."
  }

  assert {
    condition     = local.web_app_url == "https://d111111abcdef8.cloudfront.net"
    error_message = "web_app_url must be the HTTPS CloudFront URL."
  }

  assert {
    condition     = contains(aws_cognito_user_pool_client.main.callback_urls, "https://d111111abcdef8.cloudfront.net")
    error_message = "Cognito callback URL must be the CloudFront web_app_url."
  }

  assert {
    condition     = contains(aws_cognito_user_pool_client.main.logout_urls, "https://d111111abcdef8.cloudfront.net")
    error_message = "Cognito logout URL must be the CloudFront web_app_url."
  }
}

run "partial_google_credentials_rejected" {
  command = plan

  variables {
    google_client_id              = "client-id-without-a-secret"
    google_client_secret          = ""
    enable_email_allowlist_lambda = false
    allowed_emails                = []
  }

  expect_failures = [aws_cognito_user_pool_client.main]
}

run "federation_apply_plan" {
  command = plan

  variables {
    google_client_id              = "test.apps.googleusercontent.com"
    google_client_secret          = "test-secret"
    enable_email_allowlist_lambda = false
    allowed_emails                = []
  }

  assert {
    condition     = length(aws_cognito_identity_provider.google) == 1
    error_message = "Federation_Apply must create one Google identity provider."
  }

  assert {
    condition     = contains(aws_cognito_user_pool_client.main.supported_identity_providers, "Google")
    error_message = "Federation_Apply must enable Google on the app client."
  }
}

run "email_allowlist_lambda_plan" {
  command = plan

  variables {
    enable_email_allowlist_lambda = true
    allowed_emails = [
      "operator@gmail.com",
      "admin@gmail.com",
    ]
  }

  assert {
    condition     = length(aws_lambda_function.email_allowlist) == 1
    error_message = "Enabling Phase 2 must create one Lambda function."
  }

  assert {
    condition     = aws_lambda_function.email_allowlist[0].runtime == "nodejs24.x"
    error_message = "The email allowlist function must use nodejs24.x."
  }

  assert {
    condition     = length(aws_cognito_user_pool.main.lambda_config) == 1
    error_message = "Phase 2 must attach a Cognito lambda_config block."
  }
}

run "invalid_allowed_emails_rejected" {
  command = plan

  variables {
    enable_email_allowlist_lambda = true
    allowed_emails                = ["not-an-email"]
  }

  expect_failures = [aws_lambda_function.email_allowlist]
}

run "empty_allowed_emails_rejected" {
  command = plan

  variables {
    enable_email_allowlist_lambda = true
    allowed_emails                = []
  }

  expect_failures = [aws_lambda_function.email_allowlist]
}
