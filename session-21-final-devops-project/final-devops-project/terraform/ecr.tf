resource "aws_ecr_repository" "kirana" {
  name                 = "kirana-final"
  image_tag_mutability = "IMMUTABLE" # a tag (git SHA) can never be overwritten
  force_delete         = true
  image_scanning_configuration {
    scan_on_push = true
  }
  encryption_configuration {
    encryption_type = "AES256"
  }
}

resource "aws_ecr_lifecycle_policy" "kirana" {
  repository = aws_ecr_repository.kirana.name
  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "keep the last 20 images"
      selection    = { tagStatus = "any", countType = "imageCountMoreThan", countNumber = 20 }
      action       = { type = "expire" }
    }]
  })
}
