provider "aws" {
  region = "${var.aws_region}"
}

#Virtual Private Network / NAT

resource "aws_vpc" "nat-vpc" {
  cidr_block           = "10.0.0.0/16"
 
  tags {
    Name = "tf_nat_vpc"
  }
}

resource "aws_internet_gateway" "nat-gateway" {
  vpc_id = "${aws_vpc.nat-vpc.id}"

  tags {
    Name = "tf_test_ig"
  }
}

resource "aws_security_group" "nat" {
	name = "nat"
	description = "Allow services from the private subnet through NAT"

	ingress {
		from_port = 0
		to_port = 65535
		protocol = "tcp"
		cidr_blocks = ["${aws_subnet.eu-central-1a-private.cidr_block}"]
	}

        egress {
               from_port   = 0
               to_port     = 0
               protocol    = "-1"
               cidr_blocks = ["0.0.0.0/0"]
        }

	vpc_id = "${aws_vpc.nat-vpc.id}"
}

resource "aws_instance" "nat" {
	ami = "${var.aws_natami}"
	availability_zone = "${var.availability_zones}"
	instance_type = "${var.instance_type}"
	key_name = "${var.key_name}"
	security_groups = ["${aws_security_group.nat.id}"]
	subnet_id = "${aws_subnet.eu-central-1a-public.id}"
	associate_public_ip_address = true
	source_dest_check = false
}

resource "aws_eip" "nat" {
	instance = "${aws_instance.nat.id}"
	vpc = true
}

# Public subnets

resource "aws_subnet" "eu-central-1a-public" {
	vpc_id = "${aws_vpc.nat-vpc.id}"

	cidr_block = "10.0.0.0/24"
	availability_zone = "${var.availability_zones}"
}

# Routing table for public subnets

resource "aws_route_table" "eu-central-1-public" {
	vpc_id = "${aws_vpc.nat-vpc.id}"

	route {
		cidr_block = "0.0.0.0/0"
		gateway_id = "${aws_internet_gateway.nat-gateway.id}"
	}
}

resource "aws_route_table_association" "eu-central-1a-public" {
	subnet_id = "${aws_subnet.eu-central-1a-public.id}"
	route_table_id = "${aws_route_table.eu-central-1-public.id}"
}

# Private subnets

resource "aws_subnet" "eu-central-1a-private" {
	vpc_id = "${aws_vpc.nat-vpc.id}"

	cidr_block = "10.0.1.0/24"
	availability_zone = "${var.availability_zones}"
}

# Routing table for private subnets

resource "aws_route_table" "eu-central-1-private" {
	vpc_id = "${aws_vpc.nat-vpc.id}"

	route {
		cidr_block = "0.0.0.0/0"
		instance_id = "${aws_instance.nat.id}"
	}
}

resource "aws_route_table_association" "eu-central-1b-private" {
	subnet_id = "${aws_subnet.eu-central-1a-private.id}"
	route_table_id = "${aws_route_table.eu-central-1-private.id}"
}

# Our default security group to access
# the instances over SSH and HTTP
resource "aws_security_group" "default" {
  name        = "instance_sg"
  description = "Instance Security Group"
  vpc_id      = "${aws_vpc.nat-vpc.id}"

  # HTTP access from anywhere
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # outbound internet access
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# Our elb security group to access
# the ELB over HTTP
resource "aws_security_group" "elb" {
  name        = "elb_sg"
  description = "Loadbalancer Security Group"

  vpc_id = "${aws_vpc.nat-vpc.id}"

  # HTTP access from anywhere
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # outbound internet access
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # ensure the VPC has an Internet gateway or this step will fail
  depends_on = ["aws_internet_gateway.nat-gateway"]
}

resource "aws_cloudwatch_metric_alarm" "memory-low" {
    alarm_name = "cpu-util-low-agents"
    comparison_operator = "LessThanOrEqualToThreshold"
    evaluation_periods = "1"
    metric_name = "CPUUtilization"
    namespace = "AWS/EC2"
    period = "120"
    statistic = "Average"
    threshold = "${var.threshold_min}"
    alarm_description = "This metric monitors ec2 memory for low utilization on agent hosts"
    alarm_actions = [
        "${aws_autoscaling_policy.agents-scale-down.arn}"
    ]
    dimensions {
        AutoScalingGroupName = "${aws_cloudformation_stack.autoscaling_group.name}"
    }
}

resource "aws_cloudformation_stack" "autoscaling_group" {
  lifecycle { create_before_destroy = true }
  name = "cvo-asg"
  template_body = <<STACK
{
  "Parameters" : {
    "LaunchConfig" : {
      "Type" : "String",
      "Default" : "${aws_launch_configuration.web-lc.name}",
      "Description" : "Enter the Launchconfiguration."
    }
  },
  "Resources": {
    "MyAsg": {
      "Type": "AWS::AutoScaling::AutoScalingGroup",
      "Properties": {
        "LaunchConfigurationName": { "Ref" : "LaunchConfig" },
        "TerminationPolicies": ["OldestLaunchConfiguration", "OldestInstance"],
        "MaxSize": "3",
        "MinSize": "2",
        "LoadBalancerNames": ["${aws_elb.web.name}"],
        "HealthCheckType": "ELB",
        "HealthCheckGracePeriod": "300",
        "DesiredCapacity": "2",
        "VPCZoneIdentifier": ["${aws_subnet.eu-central-1a-private.id}"],
        "Tags": [
         {
            "PropagateAtLaunch": true,
            "Value": "web-asg",
            "Key": "Name"
         }
        ]
      },
      "UpdatePolicy": {
        "AutoScalingRollingUpdate": {
          "MinInstancesInService": "2",
          "PauseTime": "PT3M"
          }
        }
      }
    },
    "Outputs": {
      "AsgName": {
        "Description": "The name of the auto scaling group",
         "Value": {"Ref": "MyAsg"}
    }
  }
}
STACK
}

resource "aws_autoscaling_policy" "agents-scale-up" {
    name = "agents-scale-up"
    scaling_adjustment = 1
    adjustment_type = "ChangeInCapacity"
    cooldown = 300
    autoscaling_group_name = "${aws_cloudformation_stack.autoscaling_group.outputs["AsgName"]}"
}

resource "aws_autoscaling_policy" "agents-scale-down" {
    name = "agents-scale-down"
    scaling_adjustment = -1
    adjustment_type = "ChangeInCapacity"
    cooldown = 300
    autoscaling_group_name = "${aws_cloudformation_stack.autoscaling_group.outputs["AsgName"]}"
}

resource "aws_cloudwatch_metric_alarm" "memory-high" {
    alarm_name = "cpu-util-high-agents"
    comparison_operator = "GreaterThanOrEqualToThreshold"
    evaluation_periods = "1"
    metric_name = "CPUUtilization"
    namespace = "AWS/EC2"
    period = "120"
    statistic = "Average"
    threshold = "${var.threshold_plus}"
    alarm_description = "This metric monitors ec2 memory for high utilization on agent hosts"
    alarm_actions = [
        "${aws_autoscaling_policy.agents-scale-up.arn}"
    ]
    dimensions {
        AutoScalingGroupName = "${aws_cloudformation_stack.autoscaling_group.name}"
    }
}

resource "aws_launch_configuration" "web-lc" {
  lifecycle { create_before_destroy = true }
  image_id      = "${lookup(var.aws_amis, var.aws_region)}"
  instance_type = "${var.instance_type}"
  user_data = "${file("init-agent-instance.sh")}"

  # Security group
  security_groups = ["${aws_security_group.default.id}"]
  key_name        = "${var.key_name}"
}

resource "aws_elb" "web" {
  name = "example-elb"

  # The same availability zone as our instance
  subnets = ["${aws_subnet.eu-central-1a-public.id}"]

  security_groups = ["${aws_security_group.elb.id}"]

  listener {
    instance_port     = 80
    instance_protocol = "http"
    lb_port           = 80
    lb_protocol       = "http"
  }

  health_check {
    healthy_threshold   = 2
    unhealthy_threshold = 2
    timeout             = 3
    target              = "HTTP:80/"
    interval            = 30
  }
}
