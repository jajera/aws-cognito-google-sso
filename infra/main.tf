resource "random_id" "domain_suffix" {
  byte_length = 4
}

resource "aws_iam_role" "lambda_exec" {
  count = var.enable_email_allowlist_lambda ? 1 : 0

  name = "cognito-pre-signup-email-allowlist"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "lambda.amazonaws.com"
      }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_basic" {
  count = var.enable_email_allowlist_lambda ? 1 : 0

  role       = aws_iam_role.lambda_exec[0].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

data "archive_file" "lambda_zip" {
  count = var.enable_email_allowlist_lambda ? 1 : 0

  type        = "zip"
  source_file = "${path.module}/lambda/index.mjs"
  output_path = "${path.module}/lambda/email-allowlist.zip"
}

resource "aws_lambda_function" "email_allowlist" {
  count = var.enable_email_allowlist_lambda ? 1 : 0

  function_name    = "cognito-pre-signup-email-allowlist"
  role             = aws_iam_role.lambda_exec[0].arn
  runtime          = "nodejs24.x"
  handler          = "index.handler"
  filename         = data.archive_file.lambda_zip[0].output_path
  source_code_hash = data.archive_file.lambda_zip[0].output_base64sha256

  memory_size = 128
  timeout     = 5

  environment {
    variables = {
      ALLOWED_EMAILS = jsonencode(var.allowed_emails)
    }
  }

  lifecycle {
    precondition {
      condition = (
        length(var.allowed_emails) > 0 &&
        alltrue([
          for email in var.allowed_emails :
          trimspace(email) != "" &&
          can(regex("^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$", trimspace(email)))
        ])
      )
      error_message = "allowed_emails must contain one or more valid email addresses when enable_email_allowlist_lambda is true."
    }
  }

  depends_on = [aws_iam_role_policy_attachment.lambda_basic]
}

resource "aws_cognito_user_pool" "main" {
  name = "google-sso-demo"

  username_attributes      = ["email"]
  auto_verified_attributes = ["email"]
  mfa_configuration        = "OFF"
  deletion_protection      = "INACTIVE"

  admin_create_user_config {
    allow_admin_create_user_only = true
  }

  dynamic "lambda_config" {
    for_each = var.enable_email_allowlist_lambda ? [1] : []

    content {
      pre_sign_up = aws_lambda_function.email_allowlist[0].arn
    }
  }
}

resource "aws_lambda_permission" "cognito" {
  count = var.enable_email_allowlist_lambda ? 1 : 0

  statement_id  = "AllowCognitoPreSignUpInvocation"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.email_allowlist[0].function_name
  principal     = "cognito-idp.amazonaws.com"
  source_arn    = aws_cognito_user_pool.main.arn
}

resource "aws_cognito_user_pool_domain" "main" {
  domain       = "google-sso-demo-${random_id.domain_suffix.hex}"
  user_pool_id = aws_cognito_user_pool.main.id
}

resource "aws_s3_bucket" "web" {
  bucket = "google-sso-demo-web-${random_id.domain_suffix.hex}"

  # Allow `terraform destroy` to remove the bucket even though Terraform-managed
  # web assets (and any CloudFront-created artifacts) still populate it.
  force_destroy = true
}

resource "aws_s3_bucket_ownership_controls" "web" {
  bucket = aws_s3_bucket.web.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_public_access_block" "web" {
  bucket = aws_s3_bucket.web.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_cloudfront_origin_access_control" "web" {
  name                              = "google-sso-demo-web-${random_id.domain_suffix.hex}"
  description                       = "OAC for Cognito Google SSO demo web app"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

resource "aws_cloudfront_distribution" "web" {
  enabled             = true
  is_ipv6_enabled     = true
  comment             = "Cognito Google SSO demo web app"
  default_root_object = "index.html"
  price_class         = "PriceClass_100"

  origin {
    domain_name              = aws_s3_bucket.web.bucket_regional_domain_name
    origin_id                = "s3-web"
    origin_access_control_id = aws_cloudfront_origin_access_control.web.id
  }

  default_cache_behavior {
    target_origin_id       = "s3-web"
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["GET", "HEAD", "OPTIONS"]
    cached_methods         = ["GET", "HEAD"]
    compress               = true

    # CachingDisabled — keep demo UI updates visible after apply
    cache_policy_id = "4135ea2d-6df8-44a3-9df3-4b5a84be39ad"
    # SecurityHeadersPolicy
    response_headers_policy_id = "67f7725c-6f97-4210-82d7-5512b31e9d03"
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }
}

data "aws_iam_policy_document" "web_bucket" {
  statement {
    sid    = "AllowCloudFrontServicePrincipalReadOnly"
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["cloudfront.amazonaws.com"]
    }

    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.web.arn}/*"]

    condition {
      test     = "StringEquals"
      variable = "AWS:SourceArn"
      values   = [aws_cloudfront_distribution.web.arn]
    }
  }
}

resource "aws_s3_bucket_policy" "web" {
  bucket = aws_s3_bucket.web.id
  policy = data.aws_iam_policy_document.web_bucket.json

  depends_on = [aws_s3_bucket_public_access_block.web]
}

resource "aws_cognito_identity_provider" "google" {
  count = local.google_federation_enabled ? 1 : 0

  user_pool_id  = aws_cognito_user_pool.main.id
  provider_name = "Google"
  provider_type = "Google"

  provider_details = {
    client_id                     = var.google_client_id
    client_secret                 = var.google_client_secret
    authorize_scopes              = "openid email"
    token_url                     = "https://oauth2.googleapis.com/token"
    token_request_method          = "POST"
    authorize_url                 = "https://accounts.google.com/o/oauth2/v2/auth"
    attributes_url                = "https://people.googleapis.com/v1/people/me?personFields="
    attributes_url_add_attributes = "true"
    oidc_issuer                   = "https://accounts.google.com"
  }

  attribute_mapping = {
    email    = "email"
    username = "sub"
    name     = "name"
  }
}

resource "aws_cognito_user_pool_client" "main" {
  name         = "google-sso-client"
  user_pool_id = aws_cognito_user_pool.main.id

  generate_secret                      = false
  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_flows                  = ["code"]
  allowed_oauth_scopes                 = ["openid", "email"]

  supported_identity_providers = local.google_federation_enabled ? ["Google"] : ["COGNITO"]

  callback_urls = [local.web_app_url]
  logout_urls   = [local.web_app_url]

  lifecycle {
    precondition {
      condition     = !local.google_creds_partial
      error_message = "Both google_client_id and google_client_secret must be provided together, or both left empty."
    }
  }

  depends_on = [aws_cognito_identity_provider.google]
}

resource "aws_s3_object" "index" {
  bucket        = aws_s3_bucket.web.id
  key           = "index.html"
  source        = "${local.web_source_dir}/index.html"
  etag          = filemd5("${local.web_source_dir}/index.html")
  content_type  = "text/html; charset=utf-8"
  cache_control = "no-cache, no-store, must-revalidate"
}

resource "aws_s3_object" "styles" {
  bucket        = aws_s3_bucket.web.id
  key           = "styles.css"
  source        = "${local.web_source_dir}/styles.css"
  etag          = filemd5("${local.web_source_dir}/styles.css")
  content_type  = "text/css; charset=utf-8"
  cache_control = "no-cache, no-store, must-revalidate"
}

resource "aws_s3_object" "app" {
  bucket        = aws_s3_bucket.web.id
  key           = "app.js"
  source        = "${local.web_source_dir}/app.js"
  etag          = filemd5("${local.web_source_dir}/app.js")
  content_type  = "text/javascript; charset=utf-8"
  cache_control = "no-cache, no-store, must-revalidate"
}

resource "aws_s3_object" "config" {
  bucket        = aws_s3_bucket.web.id
  key           = "config.js"
  content_type  = "text/javascript; charset=utf-8"
  content       = local.web_config_js
  etag          = md5(local.web_config_js)
  cache_control = "no-cache, no-store, must-revalidate"
}
