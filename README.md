# Terraform on AWS: Infrastructure as Code

This repository is a hands-on class project for learning how to describe AWS infrastructure with Terraform. Instead of creating each resource by hand in the AWS Console, the configuration in `main.tf` describes the desired infrastructure. Terraform compares that configuration with its state and AWS, then proposes the changes needed to make them match.

## Class goals

By working through this project, you can practice:

- Declaring AWS infrastructure as code with Terraform resources.
- Configuring a provider and reusable input variables.
- Connecting resources through Terraform references and dependencies.
- Building a VPC with public subnets, an internet gateway, and routing.
- Launching EC2 instances and attaching EBS storage.
- Using startup scripts to install and serve a website.
- Distributing HTTP requests with an Application Load Balancer (ALB).
- Scaling instances with an Auto Scaling Group (ASG).
- Reviewing plans, applying changes, reading outputs, and cleaning up resources.

## Infrastructure overview

The configuration creates a VPC in the `us-east-1` region with two public subnets. An internet gateway and route table provide internet routing. The ALB receives public HTTP traffic and forwards requests to a target group containing the instances launched by the ASG.

```text
Internet
   |
   | HTTP :80
   v
Application Load Balancer (public, two subnets / two AZs)
   |
   v
Target group :80  <---- health checks on /
   |
   +---- Auto Scaling Group: 2 desired, minimum 2, maximum 5
           Ubuntu instances use script.sh

Separate standalone EC2 instance in us-east-1b
   |-- uses ec2-script.sh
   `-- has a separate 5 GiB gp3 EBS data volume

All resources are inside the tech365 VPC.
```

The standalone EC2 instance is separate from the Auto Scaling Group. Scaling the group does not scale, replace, or manage that standalone instance or its attached EBS volume.

### Resources in this project

| Resource | Purpose |
| --- | --- |
| VPC `tech365-vpc` | Private network with CIDR `10.0.0.0/16`. |
| Subnets | Public subnets `10.0.1.0/24` in `us-east-1b` and `10.0.2.0/24` in `us-east-1a`. |
| Internet gateway and route table | Route public subnet traffic to the internet. |
| Security groups | Allow public HTTP and SSH to the standalone EC2 instance; allow public HTTP to the ALB; allow ALB-to-instance HTTP traffic for the ASG. |
| Standalone EC2 instance | Ubuntu 22.04 instance in the first subnet, initialized with `ec2-script.sh`. |
| EBS volume and attachment | A 5 GiB `gp3` volume in `us-east-1b`, attached to the standalone instance. |
| Launch template | Describes the Ubuntu AMI, instance type, security group, and startup script used by the ASG. |
| Auto Scaling Group | Keeps 2 instances by default, with a minimum of 2 and maximum of 5, across both subnets. |
| Application Load Balancer | Public HTTP entry point that sends traffic to healthy ASG instances. |

## Repository files

- `main.tf` — AWS provider configuration and the infrastructure resources.
- `variables.tf` — Region, instance type, and key pair input variables.
- `script.sh` — Startup script used by instances launched through the ASG launch template.
- `ec2-script.sh` — Startup script for the standalone EC2 instance.
- `.gitignore` — Excludes Terraform state, local provider files, variable files, and private SSH keys from Git.

## Prerequisites

1. An AWS account with permission to create VPC, EC2, EBS, Auto Scaling, security group, and Elastic Load Balancing resources.
2. Terraform installed. This project pins the AWS provider to version `6.69.0`.
3. AWS credentials configured locally. Use your organization's approved AWS access method, such as AWS IAM Identity Center (SSO) or a configured AWS CLI profile. Do not put access keys in Terraform files or commit them to Git.
4. A usable EC2 key pair if you need SSH access to the standalone instance.

## Important configuration notes

- The default AWS region is `us-east-1`. The subnet availability zones and EBS volume are also explicitly set to `us-east-1a` and `us-east-1b`. Changing the region requires updating those zone settings too.
- `var.key_name` defaults to `page_one_unv_key`, while the `aws_key_pair.tech365` resource creates a key pair named `tech365-key`. These names must be aligned for a fresh deployment, or the instance must reference an existing key pair matching `var.key_name`.
- The `ami` variable is currently declared but not used. The active EC2 and launch template AMI is selected by the `aws_ami.ubuntu` data source, which looks up the latest Canonical Ubuntu 22.04 image in the configured region.
- `ec2-script.sh` is for the standalone instance; `script.sh` is for the ASG instances. Editing one does not change the other.
- EC2 user data normally runs during the instance's first boot. Changing a local script does not automatically rerun it on an already running instance. To retry the standalone script, copy it to the instance and run it manually, or deliberately replace the instance. Replacing an instance can change its public IP and reset its root disk.
- The standalone instance security group currently allows SSH (`22`) from `0.0.0.0/0`. This is broad access. For a real deployment, restrict SSH to a trusted IP range or use Systems Manager Session Manager. The web listener uses HTTP, not HTTPS.
- The ASG's `script.sh` currently contains a `chmod` command written as `chmod 777/var/www/html/index.html`; the missing space means that command will fail. The ASG startup script should be corrected and verified before relying on the website content it installs.

## Typical Terraform workflow

Run these commands from the project directory:

```bash
# Download the pinned AWS provider and initialize the working directory
terraform init

# Format Terraform files
terraform fmt

# Check Terraform configuration syntax and provider schemas
terraform validate

# Preview proposed AWS changes
terraform plan

# Create or update the infrastructure after reviewing the plan
terraform apply
```

Terraform will ask for confirmation before applying. Review the plan carefully: AWS resources can incur charges, and changes such as replacing an instance can interrupt access or change its public IP.

After a successful apply, retrieve the outputs:

```bash
# Public URL for the load balancer
terraform output -raw load_balancer_url

# Public IP for the separate standalone EC2 instance
terraform output -raw instance_public_ip
```

Open the load balancer URL in a browser to test the ASG-backed website. The instance public IP is for the standalone EC2 instance and is not the load-balanced endpoint.

## How Terraform connects the resources

Terraform expressions such as `aws_vpc.tech365-vpc.id` pass the ID of one resource into another. For example, both subnets refer to the VPC, the route table refers to the internet gateway, the ALB refers to its security group and subnets, and the ASG refers to the launch template and target group. These references form a dependency graph, so Terraform creates resources in a workable order and can update related resources when configuration changes.

The `data "aws_ami" "ubuntu"` block is a data source: it looks up an existing Ubuntu image in AWS rather than creating an AMI. The `variable` blocks hold configurable inputs, while the `output` blocks display useful values after apply.

## Checking startup and load balancer health

If the standalone instance does not serve the expected page, connect to it and inspect cloud-init and Nginx:

```bash
sudo cloud-init status --long
sudo tail -n 100 /var/log/cloud-init-output.log
sudo systemctl status nginx
curl -I http://localhost
```

If the ALB URL does not serve the ASG website, check that the ASG has healthy instances and that the target group health checks on `/` pass. The ASG instances use `script.sh`, not `ec2-script.sh`.

## Terraform state and collaboration

Terraform state records the relationship between Terraform resource addresses and real AWS resources. This project uses local state by default. The `.gitignore` excludes `terraform.tfstate` and related files because state can contain sensitive infrastructure details. Do not delete or commit the state file while Terraform is managing deployed resources. For a team or shared environment, configure a remote backend with access controls and state locking.

## Clean up

When you are finished with the class lab, review the resources Terraform manages and remove them with:

```bash
terraform destroy
```

This deletes the infrastructure managed by the current Terraform state, including the EC2 instances, ASG, ALB, EBS volume, and network resources. Confirm that you no longer need any data on the EBS volume before destroying it. Check the AWS Console afterward for any resources created outside Terraform that may still incur charges.
