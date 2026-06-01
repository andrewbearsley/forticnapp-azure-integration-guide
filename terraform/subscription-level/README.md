# Subscription-level Azure integration

Deploys the FortiCNAPP Config (CSPM), Activity Log, and DSPM integrations against a single Azure subscription in one `terraform apply`.

Generated from the `lacework generate cloud-account azure` command below, committed with values extracted as variables, and extended with the `lacework/dspm/azure` module for DSPM:

```bash
lacework generate cloud-account azure \
  --configuration \
  --activity_log \
  --subscription_id <sub>
```

## What this deploys

- One Azure AD application (service principal) granted Reader on the subscription
- One Storage Account + Event Hub in the same subscription for Activity Log forwarding
- Diagnostic setting on the subscription's Activity Log, exporting events to the Event Hub
- Three FortiCNAPP cloud-account integrations (Config + Activity Log + DSPM), bound to the AD application
- DSPM scanning infrastructure (Key Vault, Storage Account, Container App Job) deployed per region listed in `dspm_regions`

To skip DSPM, remove the `module "az_dspm"` block from `main.tf` and the `dspm_regions` variable from `variables.tf` before applying.

## Prerequisites

1. <a href="../../INSTALL-LACEWORK-CLI.md">Lacework CLI configured</a> (the Lacework Terraform provider reads `~/.lacework.toml` or `LW_*` env vars)
2. <a href="../../INSTALL-AZURE-CLI.md">Azure CLI</a> logged in via `az login --tenant <tenant_id>`
3. <a href="../../INSTALL-TERRAFORM.md">Terraform 1.9+</a>

## Apply-time permissions

The principal running `terraform apply` needs:

- **Owner** or **User Access Administrator** on the target subscription (to create role assignments)
- **Application Administrator** in Entra ID (to create the AD application), or if running as a service principal, the `Application.ReadWrite.OwnedBy` Microsoft Graph permission
- **Contributor** on the subscription is sufficient for Storage Account + Event Hub creation if a separate identity handles role assignments

## Apply

```bash
cp terraform.tfvars.example terraform.tfvars
# edit terraform.tfvars: set subscription_id and storage_account_network_rule_ip_rules
terraform init
terraform plan
terraform apply
```

`storage_account_network_rule_ip_rules` must include the public IP of the machine running apply, otherwise Terraform cannot create the diagnostic setting through the storage account firewall. To disable storage account network rules entirely, set the variable to `[]` and flip `use_storage_account_network_rules = false` in `main.tf`.

## Runtime permissions

The created AD application is granted:

- **Reader** on the subscription (Config reads)
- **Reader** on the Activity Log Event Hub / Storage Account (event pulls)
- No write permissions on monitored resources

## Verify

Console: **Settings → Integrations → Cloud Accounts**. Status flips to **Success** once Config has enumerated the subscription and Activity Log is receiving events. First compliance evaluation populates within 1-2 hours.

## References

- <a href="https://registry.terraform.io/modules/lacework/config/azure/latest" target="_blank">lacework/config/azure</a>
- <a href="https://registry.terraform.io/modules/lacework/activity-log/azure/latest" target="_blank">lacework/activity-log/azure</a>
- <a href="https://registry.terraform.io/modules/lacework/ad-application/azure/latest" target="_blank">lacework/ad-application/azure</a>
