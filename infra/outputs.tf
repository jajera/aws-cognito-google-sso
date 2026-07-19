output "user_pool_id" {
  description = "Cognito User Pool ID."
  value       = aws_cognito_user_pool.main.id
}

output "client_id" {
  description = "Cognito User Pool app client ID."
  value       = aws_cognito_user_pool_client.main.id
}

output "cognito_domain" {
  description = "Full Cognito managed-login domain URL."
  value       = local.cognito_domain_url
}

output "google_redirect_uri" {
  description = "Authorized redirect URI to configure on the Google OAuth client."
  value       = "${local.cognito_domain_url}/oauth2/idpresponse"
}

output "javascript_origin" {
  description = "Authorized JavaScript origin to configure on the Google OAuth client."
  value       = local.cognito_domain_url
}

output "web_app_url" {
  description = "HTTPS CloudFront URL for the demo web app."
  value       = local.web_app_url
}

output "authorize_url" {
  description = "Cognito authorization URL. It becomes usable after Federation_Apply."
  value = "${local.cognito_domain_url}/oauth2/authorize?${join("&", [
    "response_type=code",
    "client_id=${urlencode(aws_cognito_user_pool_client.main.id)}",
    "redirect_uri=${urlencode(local.web_app_url)}",
    "scope=${urlencode("openid email")}",
    "identity_provider=Google",
  ])}"
}
