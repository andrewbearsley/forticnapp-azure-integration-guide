variable "subscription_id" {
  type        = string
  description = "Azure subscription ID where Lacework deployment resources (Storage Account, Event Hub, AD application owner) are created. This is the management subscription, not the monitored scope — Config and Activity Log cover all subscriptions under the management group."
}

variable "management_group_id" {
  type        = string
  description = "Azure management group ID at which the AD application is granted Reader. For the tenant root, this is the tenant ID. For a sub-tree (e.g. ALZ platform + workload management groups), use the parent group ID."
}

variable "storage_account_network_rule_ip_rules" {
  type        = list(string)
  description = "IPs allowed to reach the Activity Log Storage Account. Must include the public IP of the machine running terraform apply. Set to [] and flip use_storage_account_network_rules to false in main.tf to disable network rules."
  default     = []
}

variable "dspm_regions" {
  type        = list(string)
  description = "Azure regions where DSPM scanners are deployed (e.g. [\"australiaeast\"]). To skip DSPM entirely, remove the az_dspm module block from main.tf and this variable."
}
