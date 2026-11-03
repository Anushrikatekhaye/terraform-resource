# Security best practices

## Implemented in this project

| Practice | Where |
|----------|-------|
| **Instances are private**: no public IPs, reachable only through the NLB | `vpc.tf`, `autoscaling.tf` |
| **Security group chaining**: web servers accept port 80 only from the NLB security group, never from the internet directly | `security_groups.tf` |
| **Restricted egress**: instances can only go out on 80/443, the NLB can only reach the web security group | `security_groups.tf` |
| **No open SSH**: SSH is allowed only from inside the VPC by default; shell access via SSM Session Manager | `variables.tf`, `main.tf` |
| **Least-privilege IAM**: the instance role has only `AmazonSSMManagedInstanceCore` | `main.tf` |
| **IMDSv2 required** (`http_tokens = "required"`, hop limit 1) | `launch_template.tf` |
| **Encrypted EBS** root volumes (gp3) | `launch_template.tf` |
| **Encrypted, versioned, private state bucket** with native locking | `provider.tf`, `scripts/bootstrap-state.sh` |
| **No secrets in Git**: only the public SSH key is read; `.gitignore` excludes state, `*.pem`, private keys, `backend.hcl`, local var files | `.gitignore` |
| **Nginx version hidden** (`server_tokens off`) | `userdata.sh` |
| **Consistent tagging** for ownership and cost tracking | `provider.tf`, `launch_template.tf`, `autoscaling.tf` |
| **Input validation** on CIDRs, capacity and credit mode | `variables.tf` |

## Recommended next steps for production

1. **TLS**: add a TLS listener on 443 with an ACM certificate (NLB TLS listener) or terminate TLS on Nginx; redirect or disable plain HTTP.
2. **Restrict `allowed_http_cidrs`** if the app is not public (VPN or corporate ranges).
3. **WAF and L7 protections**: use an Application Load Balancer + AWS WAF if you need request filtering.
4. **VPC Flow Logs** and **CloudTrail** to a dedicated log bucket; **GuardDuty** for threat detection.
5. **Patch management**: bake AMIs (Packer / EC2 Image Builder) or use SSM Patch Manager. The ASG `instance_refresh` already rolls new AMIs.
6. **State bucket hardening**: bucket policy denying non-TLS access, MFA delete, access logging, and a restricted IAM policy for who may read the state (state can contain sensitive values).
7. **Static analysis in CI**: `terraform fmt -check`, `terraform validate`, `tflint`, `checkov` or `trivy config`.
8. **Separate AWS accounts / state files per environment**, with IAM roles assumed by CI instead of long-lived access keys.
9. **Enable NLB deletion protection** (`enable_deletion_protection = true`) in production.
10. **CloudWatch Agent** for memory/disk metrics and log shipping (`/var/log/nginx`, `/var/log/user-data.log`).

## What never to commit

Terraform state, `*.tfplan`, private keys (`*.pem`, `id_*`), AWS access keys, `.env` files, `backend.hcl` (account-specific). If a secret is ever committed, **rotate it** - deleting it from Git history is not enough.
