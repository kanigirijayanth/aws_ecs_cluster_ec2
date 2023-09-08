resource "aws_security_group" "alb-ecs-tf-sg" {
  name        = "alb-ecs-tf-sg"
  description = "SG for ALB-ECS"

  ingress {
    from_port   = 0
    to_port     = 65535
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

}

resource "aws_security_group" "ecs-tf-sg" {
  name        = "ecs-tf-sg"
  description = "SG for ECS"

  ingress {
    from_port = 0
    to_port   = 0
    protocol  = "-1"
    self      = true
  }

  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    from_port       = 0
    to_port         = 65535
    protocol        = "tcp"
    security_groups = [aws_security_group.alb-ecs-tf-sg.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

}

resource "aws_alb" "ecs-tf-alb" {
  name                             = "ecs-tf-alb"
  internal                         = false
  load_balancer_type               = "application"
  security_groups                  = [aws_security_group.alb-ecs-tf-sg.id]
  subnets                          = ["subnet-040ab07bd6cc8d560", "subnet-0d167f50967409095", "subnet-0b86675b85dfdf165"]
  enable_cross_zone_load_balancing = "true"
}

resource "aws_lb_target_group" "ecs-alb-tf-tg" {
  name        = "ecs-alb-tf-tg"
  target_type = "instance"
  port        = 80
  protocol    = "HTTP"
  vpc_id      = "vpc-0134ef99c4daac0b3"
  health_check {
    healthy_threshold   = 3
    interval            = 20
    unhealthy_threshold = 2
    timeout             = 10
    path                = "/"
    port                = 80
  }
}

resource "aws_lb_listener" "listener" {
  load_balancer_arn = aws_alb.ecs-tf-alb.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.ecs-alb-tf-tg.id
  }
}

resource "aws_launch_template" "launch-temp-tf" {
  name                   = "launch-temp-tf"
  image_id               = "ami-0700df939e7249d03"
  instance_type          = "t2.micro"
  vpc_security_group_ids = [aws_security_group.ecs-tf-sg.id]
  user_data              = base64encode("#!/bin/bash\necho ECS_CLUSTER=ecs-cluster-tf >> /etc/ecs/ecs.config")
  iam_instance_profile {
	name = "ecsTaskExecutionRole1"
  }
}

resource "aws_autoscaling_group" "asg-ecs-tf" {
  name                = "asg-ecs-tf"
  vpc_zone_identifier = ["subnet-0b86675b85dfdf165", "subnet-040ab07bd6cc8d560"]

  desired_capacity          = 1
  min_size                  = 1
  max_size                  = 1
  health_check_grace_period = 20
  health_check_type         = "EC2"

  launch_template {
    id      = aws_launch_template.launch-temp-tf.id
    version = "$Latest"
  }
}

resource "aws_ecs_capacity_provider" "provider-ecs-tf" {
  name = "provider-ecs-tf"
  auto_scaling_group_provider {
    auto_scaling_group_arn = aws_autoscaling_group.asg-ecs-tf.arn

    managed_scaling {
      status                    = "ENABLED"
      target_capacity           = 1
      minimum_scaling_step_size = 1
      maximum_scaling_step_size = 100
    }
  }
}

resource "aws_ecs_cluster" "cluster-ecs-tf" {
  name = "ecs-cluster-tf"

}

resource "aws_ecs_cluster_capacity_providers" "providers" {
  cluster_name       = aws_ecs_cluster.cluster-ecs-tf.name
  capacity_providers = [aws_ecs_capacity_provider.provider-ecs-tf.name]

  default_capacity_provider_strategy {
    base              = 1
    weight            = 100
    capacity_provider = aws_ecs_capacity_provider.provider-ecs-tf.name
  }
}

resource "aws_ecs_task_definition" "ngnix-taskdef-tf" {
  family                   = "ngnix-taskdef-tf"
  requires_compatibilities = ["EC2"]

  container_definitions = jsonencode([
    {

      essential = true
      memory    = 1024
      name      = "ngnix"
      cpu       = 512
      image     = "ngnix:latest"
      portMappings : [
        {
          name : "ngnix-80-tcp",
          containerPort : 80
          hostPort : 80
          appProtocol : "http"
          protocol : "tcp"
        }
      ]
    }
  ])
}

resource "aws_ecs_service" "test_service_tf" {

  cluster         = aws_ecs_cluster.cluster-ecs-tf.id
  launch_type     = "EC2"
  task_definition = aws_ecs_task_definition.ngnix-taskdef-tf.arn

  scheduling_strategy = "REPLICA"
  desired_count       = 1
  name                = "test_service_tf"
}

add new line