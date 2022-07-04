variable "domain_name" {
  description = "Domain name for the website, e.g. example.com"
  type        = string
}

variable "alternate_domain_names" {
  description = "List of alternate domain names for the website, e.g. www.example.com"
  type        = list(string)
  default     = []
}

variable "hosted_zone_id" {
  description = "Route53 hosted zone ID in which to create DNS records for the website"
  type        = string
}

variable "content_security_policy" {
  description = "Security headers - content security policy to enforce on the website"
  type        = string
  default     = "default-src 'none'; object-src 'none'; base-uri 'none'; frame-ancestors 'none'; form-action 'none'; media-src 'self'; script-src 'self'; frame-src 'self'; img-src 'self'; style-src 'self'; font-src 'self'"
}

variable "frame_options" {
  description = "Security headers - frame options policy to enforce on the website"
  type        = string
  default     = "DENY"
}

variable "referrer_policy" {
  description = "Security headers - referrer policy to enforce on the website"
  type        = string
  default     = "same-origin"
}

variable "strict_transport_security_max_age" {
  description = "Security headers - HTTP Strict Transport Security max age to enforce on the website, in seconds"
  type        = string
  default     = "63072000"
}

variable "cloudfront_caching_optimized_policy_id" {
  description = "Static AWS-managed CloudFront caching-optimized policy ID"
  type        = string
  default     = "658327ea-f89d-4fab-a63d-7e88639e58f6"
}

variable "cloudfront_distribution_zone_id" {
  description = "Static zone ID used for all AWS CloudFront distributions"
  type        = string
  default     = "Z2FDTNDATAQYW2"
}
