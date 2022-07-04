# ------------------------------------------------------------------------------------------
# AWS Caller Identity

data "aws_caller_identity" "current" {}

# ------------------------------------------------------------------------------------------
# ACM

resource "aws_acm_certificate" "certificate" {
  domain_name               = var.domain_name
  subject_alternative_names = var.alternate_domain_names
  validation_method         = "DNS"
}

resource "aws_acm_certificate_validation" "certificate_validation" {
  certificate_arn         = aws_acm_certificate.certificate.arn
  validation_record_fqdns = [for record in aws_route53_record.website_certificate_validation : record.fqdn]
}

# ------------------------------------------------------------------------------------------
# CloudFront

resource "aws_cloudfront_origin_access_identity" "identity" {
  comment = "access-identity-${var.domain_name}.s3.amazonaws.com"
}

resource "aws_cloudfront_function" "url_rewrite" {
  name    = "url-rewrite"
  runtime = "cloudfront-js-1.0"
  comment = "Adds index.html to viewer requests if missing"
  publish = true
  code    = file("cloudfront_functions/url-rewrite.js")
}

resource "aws_cloudfront_response_headers_policy" "custom_security_headers_policy" {
  name    = "CustomSecurityHeadersPolicy"
  comment = "Adds a set of security headers to every response"

  security_headers_config {
    content_security_policy {
      content_security_policy = var.content_security_policy
      override                = true
    }
    content_type_options {
      override = true
    }
    frame_options {
      frame_option = var.frame_options
      override     = true
    }
    referrer_policy {
      referrer_policy = var.referrer_policy
      override        = true
    }
    strict_transport_security {
      access_control_max_age_sec = var.strict_transport_security_max_age
      include_subdomains         = true
      override                   = true
      preload                    = true
    }
    xss_protection {
      mode_block = true
      override   = true
      protection = true
    }
  }
}

resource "aws_cloudfront_distribution" "cloudfront_distribution" {
  aliases = [
    var.domain_name,
    "www.${var.domain_name}",
  ]
  custom_error_response {
    error_caching_min_ttl = 300
    error_code            = 403
    response_code         = 403
    response_page_path    = "/403.html"
  }
  custom_error_response {
    error_caching_min_ttl = 300
    error_code            = 404
    response_code         = 404
    response_page_path    = "/404.html"
  }
  default_root_object = "index.html"
  default_cache_behavior {
    allowed_methods = [
      "GET",
      "HEAD",
    ]
    cached_methods = [
      "GET",
      "HEAD",
    ]
    cache_policy_id            = var.cloudfront_caching_optimized_policy_id
    compress                   = true
    response_headers_policy_id = aws_cloudfront_response_headers_policy.custom_security_headers_policy.id
    target_origin_id           = "S3-${var.domain_name}"
    viewer_protocol_policy     = "redirect-to-https"
  }
  enabled         = true
  is_ipv6_enabled = true
  origin {
    domain_name = "${var.domain_name}.s3.amazonaws.com"
    origin_id   = "S3-${var.domain_name}"
    s3_origin_config {
      origin_access_identity = aws_cloudfront_origin_access_identity.identity.cloudfront_access_identity_path
    }
  }
  restrictions {
    geo_restriction {
      restriction_type = "none"
      locations        = []
    }
  }
  viewer_certificate {
    acm_certificate_arn      = aws_acm_certificate.certificate.arn
    minimum_protocol_version = "TLSv1.2_2021"
    ssl_support_method       = "sni-only"
  }
}

# ------------------------------------------------------------------------------------------
# IAM

data "aws_iam_policy_document" "policy_for_cloudfront_invalidation_lambda" {
  policy_id = "policy_for_cloudfront_invalidation_lambda"
  statement {
    actions = [
      "cloudfront:CreateInvalidation",
    ]
    resources = [
      "arn:aws:cloudfront::${data.aws_caller_identity.current.account_id}:distribution/*",
    ]
    sid = "1"
  }
  statement {
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
    ]
    resources = [
      "arn:aws:logs:*:${data.aws_caller_identity.current.account_id}:log-group:*",
    ]
    sid = "2"
  }
  statement {
    actions = [
      "logs:PutLogEvents",
    ]
    resources = [
      "arn:aws:logs:*:${data.aws_caller_identity.current.account_id}:log-group:*:log-stream:*",
    ]
    sid = "3"
  }
  statement {
    actions = [
      "s3:GetBucketTagging",
    ]
    resources = [
      "arn:aws:s3:::*",
    ]
    sid = "4"
  }
}

resource "aws_iam_policy" "policy_for_cloudfront_invalidation_lambda" {
  name = "policy_for_cloudfront_invalidation_lambda"

  policy = data.aws_iam_policy_document.policy_for_cloudfront_invalidation_lambda.json
}

data "aws_iam_policy_document" "policy_for_cloudfront_invalidation_lambda_assume_role_policy" {
  policy_id = "policy_for_cloudfront_invalidation_lambda_assume_role_policy"
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type = "Service"
      identifiers = [
        "lambda.amazonaws.com",
      ]
    }
    sid = "1"
  }
}

resource "aws_iam_role" "policy_for_cloudfront_invalidation_lambda" {
  name = "policy_for_cloudfront_invalidation_lambda"

  assume_role_policy = data.aws_iam_policy_document.policy_for_cloudfront_invalidation_lambda_assume_role_policy.json
}

resource "aws_iam_role_policy_attachment" "policy_for_cloudfront_invalidation_lambda" {
  role       = aws_iam_role.policy_for_cloudfront_invalidation_lambda.name
  policy_arn = aws_iam_policy.policy_for_cloudfront_invalidation_lambda.arn
}

data "aws_iam_policy_document" "policy_for_cloudfront_private_content" {
  statement {
    actions = [
      "s3:GetObject",
    ]
    principals {
      type = "AWS"
      identifiers = [
        aws_cloudfront_origin_access_identity.identity.iam_arn,
      ]
    }
    resources = [
      "${aws_s3_bucket.website_s3_bucket.arn}/*",
    ]
    sid = "1"
  }
}

# ------------------------------------------------------------------------------------------
# Lambda

data "archive_file" "cloudfront_invalidation_lambda_archive_file" {
  type        = "zip"
  source_dir  = "lambda_functions/lambda_invalidate_cloudfront"
  output_path = "lambda_functions/lambda_invalidate_cloudfront.zip"
}

resource "null_resource" "cloudfront_invalidation_lambda_archive_file" {
  triggers = {
    hash = data.archive_file.cloudfront_invalidation_lambda_archive_file.output_base64sha256,
  }
}

resource "aws_lambda_function" "cloudfront_invalidation_lambda" {
  filename         = "lambda_functions/lambda_invalidate_cloudfront.zip"
  function_name    = "cloudfront_invalidation_lambda"
  handler          = "lambda_invalidate_cloudfront.lambda_handler"
  publish          = true
  runtime          = "python3.9"
  role             = aws_iam_role.policy_for_cloudfront_invalidation_lambda.arn
  source_code_hash = data.archive_file.cloudfront_invalidation_lambda_archive_file.output_base64sha256
}

resource "aws_lambda_alias" "cloudfront_invalidation_lambda_latest_alias" {
  name             = "cloudfront_invalidation_lambda_latest_alias"
  function_name    = aws_lambda_function.cloudfront_invalidation_lambda.function_name
  function_version = "$LATEST"
}

resource "aws_lambda_permission" "cloudfront_invalidation_lambda" {
  action              = "lambda:InvokeFunction"
  function_name       = aws_lambda_function.cloudfront_invalidation_lambda.arn
  principal           = "s3.amazonaws.com"
  source_account      = data.aws_caller_identity.current.account_id
  source_arn          = aws_s3_bucket.website_s3_bucket.arn
  statement_id_prefix = "cloudfront_invalidation_lambda_"
}

# ------------------------------------------------------------------------------------------
# Route53

resource "aws_route53_record" "website_a_record" {
  for_each = setunion([var.domain_name], var.alternate_domain_names)

  zone_id = var.hosted_zone_id
  name    = each.key
  type    = "A"

  alias {
    name                   = aws_cloudfront_distribution.cloudfront_distribution.domain_name
    zone_id                = var.cloudfront_distribution_zone_id
    evaluate_target_health = false
  }
}

resource "aws_route53_record" "website_certificate_validation" {
  for_each = {
    for dvo in aws_acm_certificate.certificate.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  }

  name    = each.value.name
  records = [each.value.record]
  ttl     = 300
  type    = each.value.type
  zone_id = var.hosted_zone_id
}

# ------------------------------------------------------------------------------------------
# S3

resource "aws_s3_bucket" "website_s3_bucket" {
  bucket = var.domain_name
  tags = {
    distribution_id = aws_cloudfront_distribution.cloudfront_distribution.id
  }
}

resource "aws_s3_bucket_acl" "s3_bucket_private_acl" {
  bucket = aws_s3_bucket.website_s3_bucket.id
  acl    = "private"
}

resource "aws_s3_bucket_policy" "policy_for_cloudfront_private_content" {
  bucket = aws_s3_bucket.website_s3_bucket.id
  policy = data.aws_iam_policy_document.policy_for_cloudfront_private_content.json
}

resource "aws_s3_bucket_notification" "cloudfront_invalidation_lambda" {
  bucket = var.domain_name
  lambda_function {
    lambda_function_arn = aws_lambda_function.cloudfront_invalidation_lambda.arn
    events = [
      "s3:ObjectCreated:*",
      "s3:ObjectRemoved:*"
    ]
  }
  depends_on = [
    aws_lambda_function.cloudfront_invalidation_lambda,
    aws_lambda_permission.cloudfront_invalidation_lambda,
  ]
}

resource "aws_s3_object" "website_s3_object" {
  for_each = fileset(var.website_content_directory_path, "**")

  bucket       = var.domain_name
  content_type = lookup(jsondecode(file("mime_types.json")), regex("\\.[^.]+$", each.value), null)
  etag         = filemd5("${var.website_content_directory_path}/${each.value}")
  key          = each.value
  source       = "${var.website_content_directory_path}/${each.value}"
}
