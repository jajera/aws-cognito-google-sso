locals {
  google_federation_enabled = var.google_client_id != "" && nonsensitive(var.google_client_secret != "")
  google_creds_partial      = (var.google_client_id == "") != nonsensitive(var.google_client_secret == "")
  cognito_domain_url        = "https://${aws_cognito_user_pool_domain.main.domain}.auth.${var.region}.amazoncognito.com"
  web_app_url               = "https://${aws_cloudfront_distribution.web.domain_name}"
  web_source_dir            = "${path.module}/../web"
  web_config_js             = <<-EOT
    window.APP_CONFIG = {
      cognitoDomain: ${jsonencode(local.cognito_domain_url)},
      clientId: ${jsonencode(aws_cognito_user_pool_client.main.id)},
      redirectUri: ${jsonencode(local.web_app_url)},
      logoutUri: ${jsonencode(local.web_app_url)}
    };
  EOT
}
