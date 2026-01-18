# travel-website Terraform Deployment

This project automates the deployment of an Nginx web server for the **travel-website** an education website using **Terraform on AWS**.

## 🚀 Steps to Deploy

1. Install Terraform and AWS CLI.
2. Clone this project and edit `terraform.tfvars` with your AWS credentials.
3. Run the following commands:

```bash
terraform init
terraform plan
terraform apply -auto-approve
