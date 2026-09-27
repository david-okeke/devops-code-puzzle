variable "project_name" {
  description = "Short name used to prefix/tag all resources"
  type        = string
  default     = "devops-code-puzzle"   #change
}

variable "environment" {
  description = "Deployment environment (dev or prod)"
  type        = string
  validation {
    condition     = contains(["dev", "prod"], var.environment)
    error_message = "environment must be 'dev' or 'prod'."
  }
}

variable "aws_region" {
  description = "AWS region to deploy into"
  type        = string
  default     = "us-east-1"   #change
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidrs" {
  description = "CIDRs for two public subnets (RDS needs 2+ AZs for its subnet group)"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "instance_type" {
  description = "EC2 instance type for the app server"
  type        = string
  default     = "t3.micro"
}

variable "db_instance_class" {
  description = "RDS instance class"
  type        = string
  default     = "db.t3.micro"
}

variable "db_allocated_storage" {
  description = "RDS storage in GB (free tier covers 20GB)"
  type        = number
  default     = 20
}

variable "db_backup_retention_days" {
  description = "How many days of automated RDS backups to keep"
  type        = number
  default     = 1
}

variable "db_name" {
  description = "Application database name"
  type        = string
  default     = "appdb"
}

variable "db_username" {
  description = "Application database master username (password is generated, never set here)"
  type        = string
  default     = "appadmin"
}

variable "domain_name" {
  description = "Public domain name pointed at the app's Elastic IP. Leave empty to use a self-signed cert instead of Let's Encrypt."
  type        = string
  default     = ""   #set in your .tfvars file if you own a domain
}

variable "sns_alarm_email" {
  description = "Optional email to subscribe to CloudWatch alarms. Leave empty to skip."
  type        = string
  default     = ""   #set in your .tfvars file if you want alarm emails
}