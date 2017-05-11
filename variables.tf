variable "aws_region" {
  description = "The AWS region to create things in."
  default     = "eu-central-1"
}

# custom image
variable "aws_amis" {
  default = {
    "eu-central-1" = "ami-9b38e6f4"
  }
}

# NAT image
variable "aws_natami" {
  default = "ami-9b38e6f4"
  description = "Nat AMI"
}

variable "availability_zones" {
  default     = "eu-central-1a"
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
  default     = "stage-cvo"
}

variable "instance_type" {
  default     = "t2.micro"
  description = "AWS instance type"
}
