terraform {
  required_version = ">= 1.5"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.81" # 5.81+ no longer requires an OIDC thumbprint
    }
  }
}

provider "aws" {
  region = var.region

  default_tags {
    tags = var.tags
  }
}

data "aws_caller_identity" "current" {}

locals {
  account_id  = data.aws_caller_identity.current.account_id
  trail_name  = "detection-lab-trail"
  trail_arn   = "arn:aws:cloudtrail:${var.region}:${local.account_id}:trail/${local.trail_name}"
  bucket_name = "detection-lab-cloudtrail-${local.account_id}"
}

# ---------------------------------------------------------------------------
# CloudTrail -> S3
# ---------------------------------------------------------------------------

resource "aws_s3_bucket" "cloudtrail" {
  bucket        = local.bucket_name
  force_destroy = true # lab bucket; lets terraform destroy clean up fully
}

resource "aws_s3_bucket_public_access_block" "cloudtrail" {
  bucket                  = aws_s3_bucket.cloudtrail.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "cloudtrail" {
  bucket = aws_s3_bucket.cloudtrail.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "cloudtrail" {
  bucket = aws_s3_bucket.cloudtrail.id
  rule {
    id     = "expire-raw-logs"
    status = "Enabled"
    filter {}
    expiration {
      days = var.log_retention_days # Sentinel holds the searchable copy
    }
  }
}

data "aws_iam_policy_document" "cloudtrail_bucket" {
  statement {
    sid       = "CloudTrailAclCheck"
    actions   = ["s3:GetBucketAcl"]
    resources = [aws_s3_bucket.cloudtrail.arn]
    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:SourceArn"
      values   = [local.trail_arn]
    }
  }

  statement {
    sid       = "CloudTrailWrite"
    actions   = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.cloudtrail.arn}/AWSLogs/${local.account_id}/*"]
    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "s3:x-amz-acl"
      values   = ["bucket-owner-full-control"]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:SourceArn"
      values   = [local.trail_arn]
    }
  }
}

resource "aws_s3_bucket_policy" "cloudtrail" {
  bucket = aws_s3_bucket.cloudtrail.id
  policy = data.aws_iam_policy_document.cloudtrail_bucket.json
}

resource "aws_cloudtrail" "lab" {
  name                          = local.trail_name
  s3_bucket_name                = aws_s3_bucket.cloudtrail.id
  is_multi_region_trail         = true
  include_global_service_events = true # IAM and console sign-in events
  enable_log_file_validation    = true

  depends_on = [aws_s3_bucket_policy.cloudtrail]
}

# ---------------------------------------------------------------------------
# S3 -> SQS: Sentinel polls this queue to learn which new log files to pull
# ---------------------------------------------------------------------------

resource "aws_sqs_queue" "cloudtrail" {
  name                      = "detection-lab-cloudtrail-notifications"
  message_retention_seconds = 345600 # 4 days
  sqs_managed_sse_enabled   = true
}

data "aws_iam_policy_document" "sqs" {
  statement {
    sid       = "AllowS3Notifications"
    actions   = ["sqs:SendMessage"]
    resources = [aws_sqs_queue.cloudtrail.arn]
    principals {
      type        = "Service"
      identifiers = ["s3.amazonaws.com"]
    }
    condition {
      test     = "ArnEquals"
      variable = "aws:SourceArn"
      values   = [aws_s3_bucket.cloudtrail.arn]
    }
  }
}

resource "aws_sqs_queue_policy" "cloudtrail" {
  queue_url = aws_sqs_queue.cloudtrail.id
  policy    = data.aws_iam_policy_document.sqs.json
}

resource "aws_s3_bucket_notification" "cloudtrail" {
  bucket = aws_s3_bucket.cloudtrail.id

  queue {
    queue_arn     = aws_sqs_queue.cloudtrail.arn
    events        = ["s3:ObjectCreated:*"]
    filter_prefix = "AWSLogs/${local.account_id}/CloudTrail/"
  }

  depends_on = [aws_sqs_queue_policy.cloudtrail]
}

# ---------------------------------------------------------------------------
# Sentinel access: OIDC federation, no long-lived AWS keys
# ---------------------------------------------------------------------------

resource "aws_iam_openid_connect_provider" "sentinel" {
  url            = "https://sts.windows.net/${var.sentinel_oidc_tenant}/"
  client_id_list = [var.sentinel_oidc_audience]
}

data "aws_iam_policy_document" "sentinel_trust" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.sentinel.arn]
    }
    condition {
      test     = "StringEquals"
      variable = "sts.windows.net/${var.sentinel_oidc_tenant}/:aud"
      values   = [var.sentinel_oidc_audience]
    }
    # Pins the role to one specific Sentinel workspace
    condition {
      test     = "StringEquals"
      variable = "sts:RoleSessionName"
      values   = ["MicrosoftSentinel_${var.sentinel_workspace_id}"]
    }
  }
}

# Name must start with OIDC_ or the Sentinel connector will not use it
resource "aws_iam_role" "sentinel" {
  name               = "OIDC_SentinelCloudTrailReader"
  assume_role_policy = data.aws_iam_policy_document.sentinel_trust.json
}

data "aws_iam_policy_document" "sentinel_read" {
  statement {
    sid       = "ReadCloudTrailObjects"
    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.cloudtrail.arn}/*"]
  }

  statement {
    sid = "ConsumeNotifications"
    actions = [
      "sqs:ReceiveMessage",
      "sqs:DeleteMessage",
      "sqs:ChangeMessageVisibility",
      "sqs:GetQueueUrl",
      "sqs:GetQueueAttributes",
    ]
    resources = [aws_sqs_queue.cloudtrail.arn]
  }
}

resource "aws_iam_role_policy" "sentinel_read" {
  name   = "cloudtrail-read"
  role   = aws_iam_role.sentinel.id
  policy = data.aws_iam_policy_document.sentinel_read.json
}
