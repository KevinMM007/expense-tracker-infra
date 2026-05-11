# ---------------------------------------------------------------------------
# Elastic Container Registry repo that holds the Lambda container image.
#
# Free tier: 500 MB private storage / month for 12 months. Our image is
# ~250 MB, so the lifecycle policy below caps us at 5 retained images
# (~1.25 GB worst case) and lets older ones expire automatically.
#
# `force_delete = true` lets `terraform destroy` remove the repo even when
# it still contains images. Convenient for portfolio teardown; in real
# production you'd flip this off and prune images explicitly.
# ---------------------------------------------------------------------------

resource "aws_ecr_repository" "api" {
  name                 = "${local.name_prefix}-api"
  image_tag_mutability = "MUTABLE"
  force_delete         = true

  # Free vulnerability scan on every push - no reason not to enable it.
  image_scanning_configuration {
    scan_on_push = true
  }

  tags = {
    Name = "${local.name_prefix}-api"
  }
}

# Retention policy: keep the 5 most recent images, expire the rest.
# Keeps storage bounded inside the free tier.
resource "aws_ecr_lifecycle_policy" "api" {
  repository = aws_ecr_repository.api.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Keep last 5 images, expire older ones."
        selection = {
          tagStatus   = "any"
          countType   = "imageCountMoreThan"
          countNumber = 5
        }
        action = {
          type = "expire"
        }
      }
    ]
  })
}
