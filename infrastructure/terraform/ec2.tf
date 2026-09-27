resource "aws_instance" "web" {
  ami                    = data.aws_ami.amazon_linux.id
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.public[0].id
  vpc_security_group_ids = [aws_security_group.web.id]
  iam_instance_profile   = aws_iam_instance_profile.ec2.name

  user_data = templatefile("${path.module}/user_data.sh.tpl", {
    app_py_b64       = filebase64("${path.module}/../../app/app.py")
    requirements_b64 = filebase64("${path.module}/../../app/requirements.txt")
    dockerfile_b64   = filebase64("${path.module}/../../app/Dockerfile")
    db_host          = aws_db_instance.main.address
    db_port          = aws_db_instance.main.port
    db_name          = var.db_name
    db_username      = var.db_username
    secret_arn       = aws_ssm_parameter.db_password.arn # 👈 back to this
    aws_region       = var.aws_region
    environment      = var.environment
    project_name     = var.project_name
    domain_name      = var.domain_name
    metric_namespace = "${var.project_name}/${var.environment}"
  })
  user_data_replace_on_change = true

  tags = { Name = "${local.name_prefix}-web" }

  depends_on = [aws_db_instance.main]
}

resource "aws_eip" "web" {
  instance = aws_instance.web.id
  domain   = "vpc"
  tags     = { Name = "${local.name_prefix}-eip" }
}