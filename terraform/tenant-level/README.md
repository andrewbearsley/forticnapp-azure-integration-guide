# Tenant-level Azure integration

Deploys the FortiCNAPP Config (CSPM) and Activity Log integrations against an Azure management group, covering every subscription beneath it. Default choice for Azure Landing Zone deployments because newly-added subscriptions are picked up automatically.

Generated from `lacework generate cloud-account azure --configuration --activity_log --management_group --management_group_id <mg> --all_subscriptions --subscription_id <deployment-sub>` and committed with values extracted as variables.

## What this deploys

- One Azure AD application granted Reader at the specified management group (cascades to all child subscriptions)
- One Storage Account + Event Hub in the deployment subscription
- Diagnostic settings on every subscription under the management group, exporting Activity Log events to the central Event Hub
- Two FortiCNAPP cloud-account integrations (Config + Activity Log), bound to the AD application

## Prerequisites

1. <a href="../../INSTALL-LACEWORK-CLI.md">Lacework CLI configured</a> (the Lacework Terraform provider reads `~/.lacework.toml` or `LW_*` env vars)
2. <a href="../../INSTALL-AZURE-CLI.md">Azure CLI</a> logged in via `az login --tenant <tenant_id>`
3. <a href="../../INSTALL-TERRAFORM.md">Terraform 1.9+</a>

## Apply-time permissions

The principal running `terraform apply` needs:

- **Owner** or **User Access Administrator** at the **management group** scope (to create the management-group-scoped role assignment that grants the AD application Reader across all child subscriptions)
- **Contributor** or higher on the deployment subscription (to create the Storage Account + Event Hub)
- Permission to write diagnostic settings on every subscription under the management group (Reader is insufficient. Contributor or a custom role with `Microsoft.Insights/diagnosticSettings/write` works)
- **Application Administrator** in Entra ID (to create the AD application), or if running as a service principal, the `Application.ReadWrite.OwnedBy` Microsoft Graph permission

Tenant-level deployment usually needs Global Administrator or a platform team to delegate management-group permissions. Confirm the delegation path before scheduling the apply.

## Apply

```bash
cp terraform.tfvars.example terraform.tfvars
# edit terraform.tfvars: set subscription_id, management_group_id, and storage_account_network_rule_ip_rules
terraform init
terraform plan
terraform apply
```

`storage_account_network_rule_ip_rules` must include the public IP of the machine running apply. To disable storage account network rules entirely, set the variable to `[]` and flip `use_storage_account_network_rules = false` in `main.tf`.

## Runtime permissions

The created AD application is granted:

- **Reader** at the management group (Config reads across all child subscriptions)
- **Reader** on the Activity Log Event Hub / Storage Account (event pulls)
- No write permissions on monitored resources

New subscriptions added under the management group after deployment are picked up automatically without re-running Terraform.

## Verify

Console: **Settings → Integrations → Cloud Accounts**. Status flips to **Success** once Config has enumerated subscriptions under the management group and Activity Log is receiving events. First compliance evaluation populates within 1-2 hours.

## References

- <a href="https://registry.terraform.io/modules/lacework/config/azure/latest" target="_blank">lacework/config/azure</a>
- <a href="https://registry.terraform.io/modules/lacework/activity-log/azure/latest" target="_blank">lacework/activity-log/azure</a>
- <a href="https://registry.terraform.io/modules/lacework/ad-application/azure/latest" target="_blank">lacework/ad-application/azure</a>
