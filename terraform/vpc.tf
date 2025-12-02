variable "azs" {
 type        = list(string)
 description = "Availability Zones"
 default     = ["ap-northeast-2a", "ap-northeast-2b"]
}

variable "ab" {
 type        = list(string)
 description = "ab"
 default     = ["a", "b"]
}

variable "public_subnet_cidrs" {
 type        = list(string)
 description = "Public Subnet CIDR values"
 default     = ["10.0.0.0/24", "10.0.2.0/24"]
}

variable "private_subnet_cidrs" {
 type        = list(string)
 description = "Private Subnet CIDR values"
 default     = ["10.0.1.0/24", "10.0.3.0/24"]
}

resource "aws_vpc" "vpc" {
 cidr_block = "10.0.0.0/16"
 
 tags = {
   Name = "Dui-vpc"
 }
}

resource "aws_subnet" "public_subnets" {
 count             = length(var.public_subnet_cidrs)
 vpc_id            = aws_vpc.vpc.id
 cidr_block        = element(var.public_subnet_cidrs, count.index)
 availability_zone = element(var.azs, count.index)
 
 tags = {
   Name = "Dui-pub-${var.ab[count.index]}"
 }
}
 
resource "aws_subnet" "private_subnets" {
 count             = length(var.private_subnet_cidrs)
 vpc_id            = aws_vpc.vpc.id
 cidr_block        = element(var.private_subnet_cidrs, count.index)
 availability_zone = element(var.azs, count.index)
 
 tags = {
   Name = "Dui-priv-${var.ab[count.index]}"
 }
}

resource "aws_internet_gateway" "igw" {
 vpc_id = aws_vpc.vpc.id
 tags = {
   Name = "Dui-igw"
 }
}

resource "aws_eip" "nat_eip" {
  domain = "vpc"
  depends_on = [aws_internet_gateway.igw]
}

resource "aws_eip" "nat_eip2" {
  domain = "vpc"
  depends_on = [aws_internet_gateway.igw]
}

resource "aws_nat_gateway" "ngw_a" {
  allocation_id = aws_eip.nat_eip.id
  subnet_id     = aws_subnet.public_subnets[0].id
  tags = {
    Name = "nat-gateway-a"
  }
}

resource "aws_nat_gateway" "ngw_b" {
  allocation_id = aws_eip.nat_eip2.id
  subnet_id     = aws_subnet.public_subnets[1].id
  tags = {
    Name = "nat-gateway-b"
  }
}

resource "aws_route_table" "Dui_pub_rt" {
 vpc_id = aws_vpc.vpc.id

 route {
   cidr_block = "0.0.0.0/0"
   gateway_id = aws_internet_gateway.igw.id
 }
 
 tags = {
   Name = "Dui-pub-rt"
 }
}

resource "aws_route_table" "Dui_priv_rt_a" {
 vpc_id = aws_vpc.vpc.id
 
 route {
   cidr_block = "0.0.0.0/0"
   nat_gateway_id = aws_nat_gateway.ngw_a.id
 }
 
 tags = {
   Name = "Dui-priv-rt-a"
 }
}

resource "aws_route_table" "Dui_priv_rt_b" {
 vpc_id = aws_vpc.vpc.id
 
 route {
   cidr_block = "0.0.0.0/0"
   nat_gateway_id = aws_nat_gateway.ngw_b.id
 }
 
 tags = {
   Name = "Dui-priv-rt-b"
 }
}

resource "aws_route_table_association" "public_subnet_asso" {
 count = length(var.public_subnet_cidrs)
 subnet_id      = element(aws_subnet.public_subnets[*].id, count.index)
 route_table_id = aws_route_table.Dui_pub_rt.id
}

resource "aws_route_table_association" "private_subnet_a_asso" {
 subnet_id      = aws_subnet.private_subnets[0].id
 route_table_id = aws_route_table.Dui_priv_rt_a.id
}

resource "aws_route_table_association" "private_subnet_b_asso" {
 subnet_id      = aws_subnet.private_subnets[1].id
 route_table_id = aws_route_table.Dui_priv_rt_b.id
}
