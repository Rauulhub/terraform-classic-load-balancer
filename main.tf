terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
      version = "~>3.0"
    }
  }
}
#proveedor de servicios 
provider "aws" {
  region     = "us-east-1"
  access_key = "xxxx"
  secret_key = "xxxx"

}
#networking
resource "aws_vpc" "lab_vpc" {
  cidr_block =  "10.1.0.0/26"
  tags = {
    Name = "lab_vpc"
  }
}
resource "aws_subnet" "subnet_public" {
  vpc_id     = aws_vpc.lab_vpc.id
  cidr_block = "10.1.0.0/28"
  availability_zone = "us-east-1a" #debo establecer a que Az apunto, para el load balancer,
                                   #se configura de una vez en la publica y en la privada
                                   #
  tags = {
    Name = "subnet_public"
  }
}
resource "aws_subnet" "subnet_private" {
  vpc_id     = aws_vpc.lab_vpc.id
  cidr_block = "10.1.0.16/28"
  availability_zone = "us-east-1a"
  tags = {
    Name = "subnet_private"
  }
}
resource "aws_internet_gateway" "lab_internet_gw" {
  vpc_id = aws_vpc.lab_vpc.id
  tags = {
    Name = "lab_internet_gw"
  }
}
resource "aws_route_table" "internet" {
  vpc_id = aws_vpc.lab_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.lab_internet_gw.id
  }
  tags = {
    Name = "internet"
  }
}

resource "aws_route_table_association" "public_routetable" {
  subnet_id      = aws_subnet.subnet_public.id
  route_table_id = aws_route_table.internet.id
}
# se agrega configuracion de NAT GW para las redes privadas y asi puedan descargar el script
resource "aws_eip" "nat_eip" {
  
}
resource "aws_nat_gateway" "lab_natgw" {
  allocation_id = aws_eip.nat_eip.id
  subnet_id     = aws_subnet.subnet_public.id
  depends_on = [aws_internet_gateway.lab_internet_gw]
}
resource "aws_route_table" "nat" {
  vpc_id = aws_vpc.lab_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_nat_gateway.lab_natgw.id
  }
  tags = {
    Name = "nat"
  }
}
resource "aws_route_table_association" "private_routetable" {
  subnet_id      = aws_subnet.subnet_private.id
  route_table_id = aws_route_table.nat.id
}
#roles Iam y y configuracion para asociarlo a las Ec2
resource "aws_iam_role" "ec2-ssm" {
  name = "ec2-ssm"

  # Terraform's "jsonencode" function converts a
  # Terraform expression result to valid JSON syntax.
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Sid    = ""
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      },
    ]
  })
}
resource "aws_iam_role_policy_attachment" "ec2-ssm-policy" {
  role       = aws_iam_role.ec2-ssm.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}
resource "aws_iam_instance_profile" "ec2-profile_private" {
  name = "ec2_ssm_private"
  role = aws_iam_role.ec2-ssm.name
}

#creacion Ec2 
resource "aws_instance" "ec2_private" { #creacion instancia test con linux 2
  count = 2 #create two similar Ec2
  ami           = "ami-0984f4b9e98be44bf"
  instance_type = "t2.micro"
  subnet_id = aws_subnet.subnet_private.id
  vpc_security_group_ids = [aws_security_group.LB_EC2.id]
  #security_groups = aws_security_group.LB_EC2.id
  iam_instance_profile = aws_iam_instance_profile.ec2-profile_private.name
  user_data = file("${path.module}/app_install.sh")
  tags = {
    Name = "ec2_private"
  }

}

# Create a new load balancer
resource "aws_elb" "loadbalancer" {
  name               = "loadbalancer"
  #availability_zones = ["us-east-1"] el classic load balancer solo permite especificar Az o subnets
  subnets = [aws_subnet.subnet_public.id] #a la subnet a la que se aloja o sea la publica
  security_groups = [aws_security_group.LB_SG.id]
  internal =  false #es publico, la subnet debe ir a internet
  listener {
    instance_port     = 80
    instance_protocol = "http"
    lb_port           = 80
    lb_protocol       = "http"
  }
  #listener {
  #  instance_port      = 80
  #  instance_protocol  = "http"
  #  lb_port            = 443
  #  lb_protocol        = "https"
    #ssl_certificate_id = "arn:aws:iam::123456789012:server-certificate/certName"
  #}       #para HTTPS requiere un certificado SSL, se puede usar AWS Certificate Manager (ACM)
  #         estoi es esencial en entornos de produccion por seguridad
  health_check {
    healthy_threshold   = 2
    unhealthy_threshold = 2
    timeout             = 3
    target              = "HTTP:80/"
    interval            = 30
  }
#for_each = aws_instance.ec2_private
instances= [for instance in aws_instance.ec2_private : instance.id]
#instances= local.instance_ids
}

#locals{
#instance_ids=tolist([for instance in aws_instance.ec2_private : instance.id])
#}
#Security group LB
resource "aws_security_group" "LB_SG" {
  name        = "LB_SG"
  description = "Allow  inbound traffic and all outbound traffic"
  vpc_id      = aws_vpc.lab_vpc.id
  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
  }
  # se debe habilitar trafico desde internet , se agrega cidr blocks
  ingress{
    protocol = "tcp"
    from_port =80
    to_port =80
    cidr_blocks = ["0.0.0.0/0"] # Permitir tráfico entrante desde cualquier dirección IP
  }
}
#resource "aws_vpc_security_group_ingress_rule" "allow_LB_HTTPS" {
#  security_group_id = aws_security_group.LB_SG.id
#  cidr_ipv4         = aws_vpc.lab_vpc.cidr_block
#  from_port         = 443
#  ip_protocol       = "HTTPS"
#  to_port           = 443
#}
#resource "aws_vpc_security_group_egress_rule" "allow_all_traffic_ipv4" {
#  security_group_id = aws_security_group.LB_SG.id
#  cidr_ipv4         = "0.0.0.0/0"
#  ip_protocol       = "-1" # semantically equivalent to all ports
#}

#Security group Ec2
resource "aws_security_group" "LB_EC2" {
  name        = "LB_EC2"
  description = "Allow  inbound traffic and all outbound traffic"
  vpc_id      = aws_vpc.lab_vpc.id
  egress {
      from_port        = 0
      to_port          = 0
      protocol         = "-1"
      cidr_blocks      = ["0.0.0.0/0"]
    }
  ingress{
    protocol = "tcp"
    from_port =80
    to_port =80
    cidr_blocks = ["0.0.0.0/0"]
  }
}
#resource "aws_vpc_security_group_ingress_rule" "allow_Ec2_HTTPS" {
#  security_group_id = aws_security_group.LB_Ec2.id
#  cidr_ipv4         = aws_vpc.lab_vpc.cidr_block
#  from_port         = 80
#  ip_protocol       = "HTTP"
#  to_port           = 80
#}
#resource "aws_vpc_security_group_egress_rule" "allow_all_traffic" {
#  security_group_id = aws_security_group.LB_Ec2.id
#  cidr_ipv4         = "0.0.0.0/0"
#  ip_protocol       = "-1" # semantically equivalent to all ports
#}
