/**
 * A terraform module that creates a tagged S3 bucket with federated assumed role access and default kms key encryption.

 * Note that the `role_users` and `roles` must be valid roles that exist in the same account that the script is run in.
 */

resource "aws_s3_bucket" "bucket" {
  bucket        = "${var.bucket_name}"
  force_destroy = "true"

  versioning {
    enabled = "${var.versioning}"
  }

  tags {
    team          = "${var.tag_team}"
    application   = "${var.tag_application}"
    environment   = "${var.tag_environment}"
    contact-email = "${var.tag_contact-email}"
    customer      = "${var.tag_customer}"
  }

  server_side_encryption_configuration {
    rule {
      apply_server_side_encryption_by_default {
        sse_algorithm     = "aws:kms"
        kms_master_key_id = "${aws_kms_key.bucket_key.arn}"
      }
    }
  }

  lifecycle_rule {
    id                                     = "auto-delete-incomplete-after-x-days"
    prefix                                 = ""
    enabled                                = "${var.multipart_delete}"
    abort_incomplete_multipart_upload_days = "${var.multipart_days}"
  }
}

resource "aws_s3_bucket_policy" "bucket_policy" {
  bucket = "${aws_s3_bucket.bucket.id}"
  policy = "${data.template_file.bucket_policy.rendered}"
}

data "aws_caller_identity" "current" {}

//render dynamic list of users for s3
data "template_file" "s3_user_principal" {
  count    = "${length(var.role_users)}"
  template = "arn:aws:sts::$${account}:assumed-role/$${user}"

  vars {
    account = "${data.aws_caller_identity.current.account_id}"
    user    = "${var.role_users[count.index]}"
  }
}

//render dynamic list of iam users for s3
data "template_file" "s3_iam_user_principal" {
  count    = "${length(var.users)}"
  template = "arn:aws:iam::$${account}:user/$${user}"

  vars {
    account = "${data.aws_caller_identity.current.account_id}"
    user    = "${var.users[count.index]}"
  }
}

//render dynamic list of roles for s3
data "template_file" "s3_role_principal" {
  count    = "${length(var.roles)}"
  template = "arn:aws:sts::$${account}:assumed-role/$${role}/*"

  vars {
    account = "${data.aws_caller_identity.current.account_id}"
    role    = "${var.roles[count.index]}"
  }
}

//render bucket policy including dynamic principals
data "template_file" "bucket_policy" {
  template = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [    
    {
      "Sid": "DenyWriteToAllExceptRoleUsers",
      "Effect": "Deny",
      "Principal": "*",
      "Action": [ 
        "s3:GetObject",
        "s3:Delete*",
        "s3:Put*",
        "s3:Replicate*",
        "s3:Restore*"
      ],
      "Resource": [
        "${aws_s3_bucket.bucket.arn}",
        "${aws_s3_bucket.bucket.arn}/*"
      ],
      "Condition": {
        "StringNotLike": {
          "aws:arn": $${principals}
        }
      }
    },
    {
      "Sid": "AllowRoleUsersToRead",
      "Effect": "Allow",
      "Principal": "*",
      "Action": [         
        "s3:Get*",
        "s3:List*"
      ],
      "Resource": [
        "${aws_s3_bucket.bucket.arn}",
        "${aws_s3_bucket.bucket.arn}/*"
      ],
      "Condition": {
        "StringLike": {
          "aws:arn": $${principals}
        }
      }      
    }, 
    {
      "Sid": "AllowSamlAccountUsersToReadTagsAndAcl",
      "Effect": "Allow",
      "Principal": "*",
      "Action": [         
        "s3:GetBucketTagging",
        "s3:GetBucketAcl"
      ],
      "Resource": [
        "${aws_s3_bucket.bucket.arn}",
        "${aws_s3_bucket.bucket.arn}/*"
      ],
      "Condition": {
        "StringLike": {
          "aws:arn": "arn:aws:sts::${data.aws_caller_identity.current.account_id}:*"
        }
      }      
    }
  ]
}
EOF

  vars {
    principals = "${jsonencode(concat(concat(data.template_file.s3_user_principal.*.rendered, data.template_file.s3_role_principal.*.rendered),data.template_file.s3_iam_user_principal.*.rendered))}"
  }
}
