terraform {
  required_version = ">= 1.5.0"

  # Configure S3 Remote State with Native Locking
  backend "s3" {
    bucket       = "portfolio-tf-state-1789491074"
    key          = "projects/static-website/terraform.tfstate"
    region       = "us-east-1"
    encrypt      = true
    use_lockfile = true # Native S3 locking
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# ------------------------------------------------------------------------------
# 1. AWS Provider Configuration
# ------------------------------------------------------------------------------
provider "aws" {
  region = "us-east-1"
}

# ------------------------------------------------------------------------------
# 2. S3 Bucket for Static Website Hosting
# ------------------------------------------------------------------------------
resource "aws_s3_bucket" "website" {
  bucket        = "my-portfolio-static-site-1789491074" # Unique name for public content
  force_destroy = true
}

# Block all direct public access to the S3 bucket (CloudFront only access)
resource "aws_s3_bucket_public_access_block" "website_public_block" {
  bucket                  = aws_s3_bucket.website.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# ------------------------------------------------------------------------------
# 3. CloudFront Origin Access Control (OAC)
# ------------------------------------------------------------------------------
resource "aws_cloudfront_origin_access_control" "oac" {
  name                              = "s3-website-oac"
  description                       = "OAC for secure access to static website bucket"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

# ------------------------------------------------------------------------------
# 4. CloudFront Global CDN Distribution
# ------------------------------------------------------------------------------
resource "aws_cloudfront_distribution" "cdn" {
  enabled             = true
  is_ipv6_enabled     = true
  default_root_object = "index.html"

  origin {
    domain_name              = aws_s3_bucket.website.bucket_regional_domain_name
    origin_id                = "S3Origin"
    origin_access_control_id = aws_cloudfront_origin_access_control.oac.id
  }

  default_cache_behavior {
    allowed_methods  = ["GET", "HEAD"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "S3Origin"

    forwarded_values {
      query_string = false
      cookies {
        forward = "none"
      }
    }

    viewer_protocol_policy = "redirect-to-https"
    min_ttl                = 0
    default_ttl            = 3600
    max_ttl                = 86400
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

# ------------------------------------------------------------------------------
# 5. S3 Bucket Policy (Allows CloudFront OAC Read Access)
# ------------------------------------------------------------------------------
data "aws_iam_policy_document" "s3_oac_policy" {
  statement {
    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.website.arn}/*"]

    principals {
      type        = "Service"
      identifiers = ["cloudfront.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "AWS:SourceArn"
      values   = [aws_cloudfront_distribution.cdn.arn]
    }
  }
}

resource "aws_s3_bucket_policy" "attach_oac_policy" {
  bucket = aws_s3_bucket.website.id
  policy = data.aws_iam_policy_document.s3_oac_policy.json
}

# ------------------------------------------------------------------------------
# 6. Outputs
# ------------------------------------------------------------------------------
output "cloudfront_domain_name" {
  description = "Public URL of the CloudFront distribution"
  value       = aws_cloudfront_distribution.cdn.domain_name
}

output "website_bucket_name" {
  description = "Name of the website S3 bucket"
  value       = aws_s3_bucket.website.id
}