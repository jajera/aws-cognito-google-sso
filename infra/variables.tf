variable "region" {
  description = "AWS region for all resources."
  type        = string
  default     = "ap-southeast-2"
}

variable "google_client_id" {
  description = "Google OAuth client ID. Leave empty with google_client_secret for Shell_Apply."
  type        = string
  default     = ""
}

variable "google_client_secret" {
  description = "Google OAuth client secret. Leave empty with google_client_id for Shell_Apply."
  type        = string
  default     = ""
  sensitive   = true
}

variable "enable_email_allowlist_lambda" {
  description = "Deploy the optional pre-sign-up email allowlist Lambda."
  type        = bool
  default     = false
}

variable "allowed_emails" {
  description = "Email addresses permitted when the email allowlist Lambda is enabled."
  type        = list(string)
  default     = []
}
