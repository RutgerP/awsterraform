variable "aws_region" {
  description = "The AWS region to create things in."
  default     = "DEFAULT ZONE"
}

# custom image
variable "aws_amis" {
  default = {
    "YOUR ZONE" = "YOUR AMI"
  }
}

# NAT image
variable "aws_natami" {
  default = "YOUR AMI"
  description = "Nat AMI"
}

variable "availability_zones" {
  default     = "DEFAULT ZONES"
  description = "List of availability zones, use AWS CLI to find your "
}

variable "threshold_min" {
  default     = "40"
  description = "% threshold for scaling down instances"
}

variable "threshold_plus" {
  default     = "70"
  description = "% threshold for scaling up instances"
}

variable "key_name" {
  description = "Key name"
  default     = "KEY NAME"
}

variable "instance_type" {
  default     = "INSTANCE SIZE"
  description = "AWS instance type"
}
