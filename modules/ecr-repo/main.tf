# trivy:ignore:AVD-AWS-0033 # AES-256 is sufficient for image bytes
resource "aws_ecr_repository" "this" {
  name                 = data.context_label.this.rendered
  image_tag_mutability = "IMMUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "AES256"
  }

  tags = data.context_tags.this.tags
}

# Keep the rule shapes separate so HCL does not stringify countNumber while unifying them.
locals {
  lifecycle_policy = var.expire_after_days != null ? jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Expire images older than ${var.expire_after_days} days"
      selection = {
        tagStatus   = "any"
        countType   = "sinceImagePushed"
        countUnit   = "days"
        countNumber = var.expire_after_days
      }
      action = { type = "expire" }
    }]
    }) : jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Retain the ${coalesce(var.retain_n_images, 0)} most recent images"
      selection = {
        tagStatus   = "any"
        countType   = "imageCountMoreThan"
        countNumber = var.retain_n_images
      }
      action = { type = "expire" }
    }]
  })
}

resource "aws_ecr_lifecycle_policy" "this" {
  repository = aws_ecr_repository.this.name

  policy = local.lifecycle_policy

  lifecycle {
    precondition {
      condition     = (var.retain_n_images == null) != (var.expire_after_days == null)
      error_message = "set exactly one of retain_n_images (a release repository) or expire_after_days (a candidate repository)."
    }
  }
}
