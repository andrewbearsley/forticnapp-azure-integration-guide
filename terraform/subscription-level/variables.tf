variable "subscription_id" {
  type        = string
  description = "Azure subscription ID where Lacework deployment resources (Storage Account, Event Hub, AD application owner) are created. For subscription-level integration this is also the monitored subscription."
}

variable "location" {
  type        = string
  description = "Azure region where the Activity Log Storage Account, Event Hub, and supporting infrastructure are deployed. Must be set explicitly; the upstream module defaults to West US 2."
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
