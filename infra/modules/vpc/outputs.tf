output "vpc_id" {
  description = "Vpc id"
  value       = aws_vpc.main.id
}

output "private_subnet_ids" {
  description = "Private subnet ids"
  value       = [for s in aws_subnet.private : s.id]
}

output "public_subnet_ids" {
  description = "Public subnet ids"
  value       = [for s in aws_subnet.public : s.id]
}

output "vpc_cidr" {
  description = "Vpc CIDR"
  value       = var.vpc_cidr
}

