variable "key_name" {
    type = string
    default = "page_one_unv_key"
  
}

variable "region" {
    type = string
    default = "us-east-1"
}

variable "instance_type" {
    type = string
    default = "t3.micro"
}

variable "ami" {
    type = string
    default = "ami-0c02fb55956c7d316"
}
