
variable "aws_region" {
  type        = string
  description = "The AWS region in which the resources will be deployed"
}

variable "project_name" {
  type        = string
  description = "The name of this project to be used as a prefix for resource names"
  default     = "my-project"
}

variable "stage" {
  type        = string
  description = "The environment stage"
  default     = "dev"
}

variable "database_name" {
  type        = string
  description = "The database name"
  default     = "testdb"
}

variable "database_master_username" {
  type        = string
  description = "MySQL Aurora DB master username"
  default     = "master"
}

variable "database_engine_version" {
  type        = string
  description = "MySQL Aurora DB engine version"
  default     = "5.7.mysql_aurora.2.10.2"
}

variable "database_instance_type" {
  type        = string
  description = "MySQL Aurora DB instance type"
  default     = "db.t3.small"
}

variable "rotation_interval" {
  type        = number
  description = "Specifies the number of days between automatic scheduled rotations of the secret"
  default     = 30
}
