resource "aws_ecr_repository" "this" {
  for_each             = toset(var.services)
  name                 = "${var.name_prefix}/${each.key}"
  image_tag_mutability = "IMMUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }
}

resource "aws_ecr_lifecycle_policy" "this" {
  for_each   = aws_ecr_repository.this
  repository = each.value.name

  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Keep only the most recent ${var.image_count} images"
      selection = {
        tagStatus   = "any"
        countType   = "imageCountMoreThan"
        countNumber = var.image_count
      }

      action = {
        type = "expire"
      }
    }]


  })
}