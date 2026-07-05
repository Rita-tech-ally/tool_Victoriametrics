resource "aws_lb" "main" {
  name               = "${var.project_name}-${var.environment}-app-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [var.sg_alb_id]
  subnets            = var.public_subnets

  tags = {
    Name = "${var.project_name}-${var.environment}-app-alb"
  }
}

resource "aws_lb_target_group" "vminsert" {
  name     = "${var.environment}-tg-vminsert"
  port     = 8480
  protocol = "HTTP"
  vpc_id   = var.vpc_id

  health_check {
    path                = "/health"
    port                = "8480"
    protocol            = "HTTP"
    matcher             = "200"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 3
    unhealthy_threshold = 3
  }
}

resource "aws_lb_target_group" "vmselect" {
  name     = "${var.environment}-tg-vmselect"
  port     = 8481
  protocol = "HTTP"
  vpc_id   = var.vpc_id

  health_check {
    path                = "/health"
    port                = "8481"
    protocol            = "HTTP"
    matcher             = "200"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 3
    unhealthy_threshold = 3
  }
}

resource "aws_lb_listener" "vminsert" {
  load_balancer_arn = aws_lb.main.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.vminsert.arn
  }
}

resource "aws_lb_listener" "vmselect" {
  load_balancer_arn = aws_lb.main.arn
  port              = "81"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.vmselect.arn
  }
}

resource "aws_lb_target_group_attachment" "vminsert" {
  target_group_arn = aws_lb_target_group.vminsert.arn
  target_id        = var.vminsert_instance_id
  port             = 8480
}

resource "aws_lb_target_group_attachment" "vmselect" {
  target_group_arn = aws_lb_target_group.vmselect.arn
  target_id        = var.vmselect_instance_id
  port             = 8481
}

resource "aws_autoscaling_group" "ingestion" {
  desired_capacity    = var.ingestion_asg_desired
  max_size            = 2
  min_size            = var.ingestion_asg_min
  vpc_zone_identifier = slice(var.private_subnets, 0, 2)
  target_group_arns   = [aws_lb_target_group.vminsert.arn]

  launch_template {
    id      = var.ingestion_launch_template_id
    version = "$Latest"
  }

  tag {
    key                 = "Name"
    value               = "${var.project_name}-${var.environment}-ingest"
    propagate_at_launch = true
  }
}

resource "aws_autoscaling_group" "query" {
  desired_capacity    = var.query_asg_desired
  max_size            = 2
  min_size            = var.query_asg_min
  vpc_zone_identifier = slice(var.private_subnets, 0, 2)
  target_group_arns   = [aws_lb_target_group.vmselect.arn]

  launch_template {
    id      = var.query_launch_template_id
    version = "$Latest"
  }

  tag {
    key                 = "Name"
    value               = "${var.project_name}-${var.environment}-query"
    propagate_at_launch = true
  }
}