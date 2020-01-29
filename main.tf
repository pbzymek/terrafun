provider "aws" {
  region     = "eu-central-1" # Frankfurt
  profile    = "<put your aws credentials profile>"
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

module "elb_http_80_sg" {
  source = "terraform-aws-modules/security-group/aws//modules/http-80"

  name        = "elb-http-80-sg"
  description = "Security group with HTTP ports open for everybody (IPv4 CIDR), egress ports are all world open"
  vpc_id      = data.aws_vpc.default.id

  ingress_cidr_blocks = ["0.0.0.0/0"]
}

module "webserver_http_80_sg" {
  source = "terraform-aws-modules/security-group/aws//modules/http-80"

  name        = "webserver-http-80-sg"
  description = "Security group with HTTP ports open for everybody (IPv4 CIDR), egress ports are all world open"
  vpc_id      = data.aws_vpc.default.id

  computed_ingress_with_source_security_group_id = [
    {
      rule                     = "http-80-tcp"
      source_security_group_id = "${module.elb_http_80_sg.this_security_group_id}"
    }
  ]
  number_of_computed_ingress_with_source_security_group_id = 1
}

######
# Launch configuration and autoscaling group
######
module "echo_terrafun_asg" {
  source = "terraform-aws-modules/autoscaling/aws"
  name = "Echo Terrafun with ELB"

  # Launch configuration
  #
  lc_name = "echo-terrafun-lc"

  image_id        = "ami-00bdd96ebae87b550"
  instance_type   = "t2.micro"
  security_groups = [module.webserver_http_80_sg.this_security_group_id]
  load_balancers  = [module.elb.this_elb_id]

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

  name = "echo-terrafun-elb"

  subnets         = data.aws_subnet_ids.all.ids
  security_groups = [module.elb_http_80_sg.this_security_group_id]
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
