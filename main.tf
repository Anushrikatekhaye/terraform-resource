resource "aws_instance" "example" {
  ami           = "ami-0fe18bc3cfa53a248"
  instance_type = "t3.micro"
  key_name      = "ohiokey"
    tags = {
        Name    = "ExampleInstance" 
  }
}