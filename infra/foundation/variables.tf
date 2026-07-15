variable "region" {
  description = "Region"
  type        = string
  default     = "ap-southeast-1"
}

variable "github_owner" {
  description = "GitHub org/user that owns the repo (the part before / in owner/repo)"
  type        = string
}

variable "github_repo" {
  description = "GitHub repository name (the part after /)"
  type        = string
}

variable "state_bucket_arn" {
  description = "ARN of the S3 bucket holding Terraform state (from the bootstrap stack)"
  type        = string
  default     = "arn:aws:s3:::tooltu-streamforge-state"
}

variable "state_kms_key_arn" {
  description = "ARN of the KMS key encrypting Terraform state (from the bootstrap stack)"
  type        = string
  default     = "arn:aws:kms:ap-southeast-1:252773257724:key/433fd16a-5558-4124-85a3-3a7592087c7e"
}
