terraform{
    required_providers{
        aws = {
            source = "hashicorp/aws"
            version = "~> 3.0"
        }
    }
}

provider "aws" {
    region = "us-east-1"
}

resource "aws_instance" "instance_1"{
    ami             = "ami-011899242bb902164"
    instance_type   = "t2.micro"
    security_groups = [aws_security_group.instances.name]
    user_data       = <<-EOF
                        #!/bin/bash
                        echo "Hello, World 1" > index.html
                        python3 -m http.server 8080 &
                        EOF
}

resource "aws_instance" "instance_2"{
    ami             = "ami-011899242bb902164"
    instance_type   = "t2.micro"
    security_groups = [aws_security_group.instances.name]
    user_data       = <<-EOF
                        #!/bin/bash
                        echo "Hello, World 2" > index.html
                        python3 -m http.server 8080 &
                        EOF
}

data "aws_vpc" "default_vpc"{
    default = true
}

data "aws_subnet_ids" "default_subnet"{
    vpc_id = data.aws_vpc.default_vpc.id
}

resource "aws_security_group" "instances"{
    name = "instance-security-group"
}

resource "aws_security_group_rule" "allow_http_inbound"{
    type                  =   "ingress"
    security_group_id = aws_security_group.instances.id

    from_port       = 8080
    to_port         = 8080
    protocol        = "tcp"
    cidr_blocks     = ["0.0.0.0/0"]
}

resource "aws_lb_listener" "http"{
    load_balancer_arn = aws_lb.load_balancer.arn
    port = 80
    protocol = "HTTP"

# By default, return a simple 404 page
    default_action{
        type = "fixed-response"

        fixed_response{
            content_type    = "text/plain"
            message_body    = "404: page not found"
            status_code     = 404
        }
    }
}

resource "aws_lb_target_group" "instances"{
    name        = "example-target-group"
    port        = 8080
    protocol    = "HTTP"
    vpc_id      = data.aws_vpc.default_vpc.id

    health_check{
        path        = "/"
        protocol    = "HTTP"
        matcher     = "200"
        interval    = 15
        timeout     = 3
        healthy_threshold   = 2
        unhealthy_threshold = 2
    }
}

resource "aws_lb_target_group_attachment" "instance_1" {
    target_group_arn    = aws_lb_target_group.instances.arn
    target_id           = aws_instance.instance_1.id
    port                = 8080
}

resource "aws_lb_target_group_attachment" "instance_2" {
    target_group_arn    = aws_lb_target_group.instances.arn
    target_id           = aws_instance.instance_2.id
    port                = 8080
}

resource "aws_lb_listener_rule" "instances" {
    listener_arn        = aws_lb_listener.http.arn
    priority            = 100

    condition{
        path_pattern {
            values      = ["*"]
        }
    }

    action{
        type                = "forward"
        target_group_arn    = aws_lb_target_group.instances.arn
    }
}

resource "aws_security_group" "alb"{
    name            = "alb-security-group"
}

resource "aws_security_group_rule" "allow_alb_http_inbound"{
    type            = "ingress"
    security_group_id   = aws_security_group.alb.id

    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    cidr_blocks     = ["0.0.0.0/0"]
}

resource "aws_security_group_rule" "allow_alb_all_outbound"{
    type            = "egress"
     security_group_id   = aws_security_group.alb.id

    from_port       = 80
    to_port         = 80
    protocol        = "-1"
    cidr_blocks     = ["0.0.0.0/0"]
}

resource "aws_lb" "load_balancer" {
    name            = "web-app-lb"
    load_balancer_type  =   "application"
    subnets               = data.aws_subnet_ids.default_subnet.ids
    security_groups     = [aws_security_group.alb.id]
}

resource "aws_acm_certificate" "teknowsolutions" {
  domain_name       = "teknowsolutions.com"
  validation_method = "DNS"

  tags = {
    Name = "teknowsolutions-cert"
  }
}

resource "aws_acm_certificate_validation" "teknowsolutions" {
  certificate_arn         = aws_acm_certificate.teknowsolutions.arn
  validation_record_fqdns = [aws_route53_record.teknowsolutions.fqdn]
}

resource "aws_route53_record" "teknowsolutions" {
  name    = element(aws_acm_certificate.teknowsolutions.domain_validation_options[*].resource_record_name, 0)
  type    = element(aws_acm_certificate.teknowsolutions.domain_validation_options[*].resource_record_type, 0)
  zone_id = aws_route53_zone.primary.zone_id
  records = [element(aws_acm_certificate.teknowsolutions.domain_validation_options[*].resource_record_value, 0)]
  ttl     = 60
}

resource "aws_lb_listener" "https" {
  load_balancer_arn = aws_lb.load_balancer.arn
  port              = "443"
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-2016-08"
  certificate_arn   = aws_acm_certificate.teknowsolutions.arn

  default_action {
    type = "forward"
    target_group_arn = aws_lb_target_group.instances.arn
  }
}

resource "aws_route53_zone" "primary"{
    name                = "teknowsolutions.com"
}

resource "aws_route53_record" "root"{
    zone_id             = aws_route53_zone.primary.zone_id
    name                = "teknowsolutions.com"
    type                = "A"

    alias{
        name            = aws_lb.load_balancer.dns_name
        zone_id         = aws_lb.load_balancer.zone_id
        evaluate_target_health  = true
    } 
}

