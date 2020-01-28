provider "aws" {
  region     = "eu-central-1"
  profile    = "krzywda"
  # project     = "echo-terraform-engineering-day"
}

##############################################################
# Data sources to get VPC, subnets and security group details
##############################################################
data "aws_vpc" "default" {
  default = true
}

data "aws_subnet_ids" "all" {
  vpc_id = data.aws_vpc.default.id
}

data "aws_security_group" "default" {
  vpc_id = data.aws_vpc.default.id
  name   = "default"
}

module "http_sg" {
  source = "terraform-aws-modules/security-group/aws//modules/http-80"

  name        = "http-sg"
  description = "Security group with HTTP ports open for everybody (IPv4 CIDR), egress ports are all world open"
  vpc_id      = data.aws_vpc.default.id

  ingress_cidr_blocks = ["0.0.0.0/0"]
}

module "http_elb" {
  source = "terraform-aws-modules/security-group/aws//modules/http-80"

  name        = "http-elb"
  description = "Security group with HTTP ports open for everybody (IPv4 CIDR), egress ports are all world open"
  vpc_id      = data.aws_vpc.default.id

  ingress_cidr_blocks = ["0.0.0.0/0"]

}

# data "aws_ami" "amazon_linux" {
#   most_recent = true
#   owners      = ["525414821691"] # Marek Bytnar
#
#   filter {
#     name = "id"
#
#     values = [
#       "ami-0b76a50a2627e2c16",
#     ]
#   }
# }

######
# Launch configuration and autoscaling group
######
module "example_asg" {
  source = "terraform-aws-modules/autoscaling/aws"

  name = "example-with-elb"

  # Launch configuration
  #
  # launch_configuration = "my-existing-launch-configuration" # Use the existing launch configuration
  # create_lc = false # disables creation of launch configuration
  lc_name = "example-lc"

  image_id        = "ami-00bdd96ebae87b550"
  instance_type   = "t2.micro"
  security_groups = [module.http_elb.this_security_group_id]
  load_balancers  = [module.elb.this_elb_id]

  # ebs_block_device = [
  #   {
  #     device_name           = "/dev/xvdz"
  #     volume_type           = "gp2"
  #     volume_size           = "50"
  #     delete_on_termination = true
  #   },
  # ]

  root_block_device = [
    {
      volume_size = "50"
      volume_type = "gp2"
    },
  ]

  # Auto scaling group
  asg_name                  = "echo-terrafun-asg"
  vpc_zone_identifier       = data.aws_subnet_ids.all.ids
  health_check_type         = "EC2"
  min_size                  = 1
  max_size                  = 4
  desired_capacity          = 1
  wait_for_capacity_timeout = 0

  tags = [
    {
      key                 = "Environment"
      value               = "dev"
      propagate_at_launch = true
    },
    {
      key                 = "Project"
      value               = "echo terrafun"
      propagate_at_launch = true
    },
  ]
}

######
# ELB
######
module "elb" {
  source = "terraform-aws-modules/elb/aws"

  name = "elb-example"

  subnets         = data.aws_subnet_ids.all.ids
  security_groups = [module.http_sg.this_security_group_id]
  internal        = false

  listener = [
    {
      instance_port     = "80"
      instance_protocol = "HTTP"
      lb_port           = "80"
      lb_protocol       = "HTTP"
    },
  ]

  health_check = {
    target              = "HTTP:80/"
    interval            = 30
    healthy_threshold   = 2
    unhealthy_threshold = 2
    timeout             = 5
  }

  tags = {
    Owner       = "user"
    Environment = "dev"
  }
}
