# Deployment Guide for FortiCNAPP Azure Integration

## Overview

This guide covers the end-to-end integration of an Azure environment with FortiCNAPP.

Once integrated, FortiCNAPP delivers:

- Continuous misconfiguration detection (CSPM) across all subscriptions in scope
- Identity over-privilege analysis (CIEM) for Entra ID
- Agentless VM scanning for CVEs, package inventory, and disk secrets
- Data Security Posture Management (DSPM) across Storage Accounts and blob containers
- Network exposure context via FortiGate Security Fabric integration
- Attack path analysis combining misconfiguration, identity, CVE, and network reachability
- Compliance reporting against CIS, PCI, HIPAA, NIST, ISO 27001, SOC 2, and custom frameworks
- Unified risk console consolidating findings from every source
- Outbound alert forwarding to Splunk, ServiceNow, Teams, email, and webhooks

The setup is organised into 4 steps. Most teams start with Step 1 (core integration, which now bundles CSPM, Activity Log, and DSPM) and add the rest as needed. Each step is independently deployable.

---

## Step 1: Core Azure Integration

The core integration is the prerequisite for everything else. It deploys an Azure AD application and grants it read access across the chosen scope, and configures Activity Log forwarding for audit-event correlation.

### Step 1.1: Decide integration level

- **Tenant-level**: monitors every subscription under a chosen Azure management group; single integration record; needs management-group-scoped permissions; auto-includes new subscriptions added under that scope. Available via Path A (Terraform).
- **Subscription-level**: monitors one specific subscription; subscription-scoped permissions; one integration record per subscription. Available via Path A (Terraform) or Path B (Console wizard).

Azure Landing Zone (ALZ) deployments typically use **tenant-level** because new subscriptions are added regularly under platform/workload management groups and tenant scope picks them up automatically.

### Step 1.2: Gather information

| Field | Where to find |
|---|---|
| Azure tenant ID | `az account show --query tenantId -o tsv` |
| Subscription IDs in scope | `az account list --query "[].{id:id, name:name}" -o table` |
| Management group ID (tenant-level only) | `az account management-group list -o table` |
| Default deployment region | Operational standard (e.g. `australiaeast`). Used as the `location` variable for the Activity Log Storage Account + Event Hub. Without this set, the upstream module defaults to `West US 2`. |

#### Permission delegation model

Confirm what you can do yourself versus what needs the platform team.

**Path A (Terraform)** needs:

- Owner or User Access Administrator at the deployment scope (subscription or management group)
- Application Administrator in Entra ID
- Write access to diagnostic settings on monitored subscriptions

**Path B (Console wizard)** needs:

- Ability to create App Registrations
- Owner on the target subscription
- Application Administrator + Privileged Role Administrator on the SP in Entra ID

#### Storage Account network rules

The Activity Log Storage Account is created with public network access locked down by default. The machine running `terraform apply` needs its public IP in the allowlist so the management-plane calls can reach the Storage Account during apply. FortiCNAPP itself reads from the Event Hub, not the Storage Account, so no FortiCNAPP IPs are needed.

Get the apply machine's public IP with `curl -s ifconfig.me` and add it to `storage_account_network_rule_ip_rules` in `terraform.tfvars`.

| Scenario | What to put |
|---|---|
| Engineer's laptop | Output of `curl -s ifconfig.me` |
| Multiple engineers might run apply | Each engineer's public IP as a separate list entry |
| Corporate NAT with stable egress | The shared NAT egress IP (covers everyone behind it) |
| CI/CD pipeline | The pipeline agent's egress IP (use a self-hosted runner with a known IP, or documented IP ranges for hosted agents) |
| No firewall (lower posture) | Set to `[]` and flip `use_storage_account_network_rules = false` in `main.tf` |

For private endpoint deployments, modify `main.tf` to set `use_storage_account_network_rules = false` and add an `azurerm_private_endpoint` resource pointing at the Storage Account.

### Step 1.3: Choose your integration path

| Scenario | Path |
|---|---|
| Enterprise / regulated environment with IaC-mandated delivery | **Path A (Terraform)** |
| ALZ / tenant-level integration covering multiple subscriptions | **Path A (Terraform)** |
| Deployment tenant restricts Privileged Role Administrator (common in corporate) | **Path A (Terraform)**: apply-time delegation easier to arrange |
| Single-subscription deployment with full admin rights | **Path B (Console wizard)** |

Most production enterprise deployments land on Path A. Path B is documented below for completeness and single-subscription scenarios.

### Step 1.4: Path A, Terraform

Direct Terraform deployment using the `lacework/config/azure`, `lacework/activity-log/azure`, `lacework/ad-application/azure`, and `lacework/dspm/azure` modules. The standard path for enterprise and regulated environments. The Path B wizard runs the Config + Activity Log modules internally; DSPM via Path B is enabled separately on the integration record after the wizard completes.

Use this path for:

- **Enterprise / IaC-mandated delivery**: version-controlled, code-reviewable, repeatable
- **Tenant-level Config + Activity Log**: Terraform supports management-group scope
- **Restricted deployment tenants**: apply-time RBAC delegation is easier to arrange than console-driven directory role assignment

#### Prerequisites

1. **Lacework CLI**: <a href="INSTALL-LACEWORK-CLI.md">Install and Configure Lacework CLI</a> (the Lacework Terraform provider reads `~/.lacework.toml` or `LW_*` env vars)
2. **Terraform**: <a href="INSTALL-TERRAFORM.md">Install Terraform</a>
3. **Azure CLI**: <a href="INSTALL-AZURE-CLI.md">Install and Configure Azure CLI</a>

#### Authenticate with Azure CLI

```bash
az login --tenant <tenant_id>
az account set --subscription <deployment-subscription-id>
```

#### Option 1: Apply the committed Terraform

Pick the variant matching your integration level from Step 1.1, edit the variables, and apply.

```bash
git clone https://github.com/andrewbearsley/forticnapp-azure-integration-guide.git
cd forticnapp-azure-integration-guide/terraform/<subscription-level|tenant-level>
cp terraform.tfvars.example terraform.tfvars
# edit terraform.tfvars
terraform init
terraform plan
terraform apply
```

Variant READMEs spell out the per-level apply-time IAM requirements: <a href="terraform/subscription-level/README.md">subscription-level</a> · <a href="terraform/tenant-level/README.md">tenant-level</a>.

#### Option 2: Generate fresh with `lacework generate`

Use this when you need a non-standard combination (existing AD application, specific Event Hub location, custom storage account naming).

```bash
# Subscription-level
lacework generate cloud-account azure \
  --noninteractive \
  --configuration \
  --activity_log \
  --subscription_id <deployment-subscription-id>

# Tenant-level (via Azure management group)
lacework generate cloud-account azure \
  --noninteractive \
  --configuration \
  --activity_log \
  --management_group \
  --management_group_id <management-group-id> \
  --all_subscriptions \
  --subscription_id <deployment-subscription-id>
```

Terraform files land in `~/lacework/azure` by default (override with `--output`).

Flags:

- `--configuration`: provision Azure Config (CSPM) integration
- `--activity_log`: provision Azure Activity Log integration
- `--subscription_id`: subscription where Lacework deployment resources are created (Storage Account + Event Hub for Activity Log, AD application owner)
- `--management_group` + `--management_group_id`: scope Config to a management group (tenant-level)
- `--all_subscriptions`: also enable Activity Log forwarding from every subscription under the management group

Drop `--noninteractive` to walk through prompts instead. Then:

```bash
cd ~/lacework/azure
terraform init
terraform plan
terraform apply
```

Reference: <a href="https://docs.fortinet.com/document/forticnapp/latest/cli-reference/635459/lacework-generate-cloud-account-azure" target="_blank">lacework generate cloud-account azure</a>

### Step 1.5: Path B, Console wizard

The wizard runs Terraform under the hood (the same modules used in Path A). It bundles app registration, role assignment, Storage Account + Event Hub creation, Activity Log diagnostic setting, and the FortiCNAPP integration into a two-step UI.

The wizard offers three methods, surfaced on Step 1:

| Method | What it does | Time |
|---|---|---|
| **Automated** (recommended) | Runs Terraform via a privileged SP you pre-create. Console executes the apply. | 5-10 min |
| **Guided** | Generates a `lacework generate` CLI command you copy and run locally. | 10 min |
| **Manual** | For environments with pre-existing AD app + resources you want to point the integration at. | 30 min |

The rest of this section covers the Automated method. For Guided, the generated command is the same shape as Path A Option 2 above. For Manual, follow the in-wizard prompts.

#### Prerequisites for the Automated method

1. <a href="INSTALL-AZURE-CLI.md">Azure CLI</a> logged in via `az login`
2. An Azure App Registration (service principal) with:
   - **Owner** role on the target subscription
   - **Application Administrator** + **Privileged Role Administrator** in Entra ID (on the deployment tenant), assigned to the SP

Create the SP with one command:

```bash
az ad sp create-for-rbac \
  --name "fcnapp-wizard" \
  --role Owner \
  --scopes /subscriptions/<SUB_ID>
```

Capture `appId`, `password`, and `tenant` from the JSON output. These become the wizard's Client ID, Client Secret, and Tenant ID.

Tighten the credential lifetime to a few hours (the wizard only needs them for the duration of the integration run):

```bash
# Linux / WSL (GNU date)
az ad sp credential reset --id <APP_ID> \
  --end-date "$(date -d '+6 hour' -u +'%Y-%m-%dT%H:%M:%SZ')"

# macOS (BSD date)
az ad sp credential reset --id <APP_ID> \
  --end-date "$(date -v +6H -u +'%Y-%m-%dT%H:%M:%SZ')"
```

Then assign the two Entra directory roles to the SP. Portal is fastest: **Microsoft Entra ID > Roles and administrators >** search **Application Administrator >** Add assignments > search for the SP. Repeat for **Privileged Role Administrator**.

**Gotcha:** corporate tenants commonly block this step. Assigning directory roles requires you to hold **Privileged Role Administrator** or **Global Administrator** yourself in the deployment tenant. In production corporate environments this is usually restricted to a small IT admin team. If `Add assignments` is greyed out, you have three choices:

- Ask IT to grant the SP those directory roles on your behalf
- Ask IT for a short-term Privileged Role Administrator assignment for yourself (via PIM if the tenant uses it)
- Switch to **Path A (Terraform)**: the apply needs the same permissions, but apply-time delegation is usually easier to arrange than console-driven role assignment

#### Wizard flow

1. Log in to your FortiCNAPP account using one of these methods:
   - **Via FortiCloud**: Services > Show More > Lacework FortiCNAPP
   - **Direct login**: `https://<account>.lacework.net`
2. **Settings > Integrations > Cloud Accounts > + Add New**

   ![Cloud Accounts page with Add New](screenshots/wizard-01-cloud-accounts.png)

3. Choose **Microsoft Azure**, select **Automated configuration**, click **Next**

   ![Select method - Microsoft Azure with three method options](screenshots/wizard-02-select-method.png)

4. On Step 1 of 2:
   - Tick the integrations you need: **Agentless Workload Scanning**, **Activity Log**, **Configuration** (any combination)
   - Paste the four SP values: Client ID, Client Secret, Subscription ID, Tenant ID
   - Optionally tick **Enable tenant level integration for Agentless** if you want Agentless to cover multiple subscriptions
   - **Next**

   ![Step 1 of 2 - integration checkboxes and credentials form](screenshots/wizard-03-step1-form.png)

5. On Step 2 of 2 (Discovery Summary): the wizard authenticates as the SP and shows Caller object/principal/tenant IDs, IsAdmin status, and the list of regions it can see. Each enabled integration shows **Ready to integrate**.
6. Configure each integration:
   - **Activity Log** and **Configuration** scope automatically to the SP's subscription. No input required
   - **Agentless**: select the Azure regions for the scanning infrastructure, and list the Monitored Subscription IDs (comma-separated)

   ![Step 2 of 2 - Discovery Summary and per-integration configuration](screenshots/wizard-04-step2.png)

7. Click **Integrate**. The wizard runs Terraform; failures roll back automatically.
8. Wait for the initial sync (typically 15-60 minutes for first-time Config evaluation).

#### Wizard scope limits

- **Activity Log and Configuration are scoped to the SP's single subscription.** There is no management-group (tenant-level) option for these integrations in the Automated wizard. For tenant-level Config + Activity Log, use **Path A** with the `--management_group` flag.
- Agentless can span multiple subscriptions via the Step 1 toggle and the Monitored Subscription IDs field on Step 2.
- DSPM is not offered as a checkbox on Step 1 of the wizard. Enable it after the wizard completes by opening the Azure integration record under **Settings > Integrations > Cloud Accounts**, toggling **DSPM** on, and providing the scanning regions.

Reference: <a href="https://docs.fortinet.com/document/forticnapp/latest/administration-guide/729300/integrating-your-azure-environment" target="_blank">Integrating your Azure environment</a> · <a href="https://docs.fortinet.com/document/forticnapp/latest/administration-guide/923035/integrating-dspm-scanning-with-your-azure-cloud-accounts" target="_blank">Integrating DSPM with Azure</a>

### Step 1.6: Verify

In the FortiCNAPP console, navigate to **Settings > Integrations > Cloud Accounts**. The Azure integration status displays as **Success** when Config has enumerated subscriptions and Activity Log is receiving events. Allow 1-2 hours for the first compliance evaluation to populate.

Reference: <a href="https://registry.terraform.io/modules/lacework/config/azure/latest" target="_blank">lacework/config/azure</a> · <a href="https://registry.terraform.io/modules/lacework/activity-log/azure/latest" target="_blank">lacework/activity-log/azure</a>

---

## Step 2: Agentless Workload Scanning

Agentless workload scanning provides VM-level CVE detection without installing agents. It scans both running and stopped VMs by snapshotting and analysing disk contents in a customer-controlled scanning subscription.

Common to both paths:

- Deploys per-region. Each Azure region where you have VMs needs its own regional module
- Uses an hourly scheduled Container App Job as orchestrator; spins up ephemeral scanning VMs per scan cycle
- Requires a dedicated **scanning subscription** with compute and storage capacity
- Default deployment uses a NAT Gateway + Public IP for outbound traffic. In environments with Azure Policy DENY on public IP creation, request an exemption scoped to the scanning subscription only (the public IP is on the egress NAT, not on scanning VMs)
- Secrets-on-disk detection is part of the same scanning job

### Step 2: Path A, Terraform

Full IaC control via the dedicated agentless deployment guide, which covers custom VNet/subnet, existing NAT reuse, Azure Policy DENY exemptions, and multi-region rollout patterns:

<a href="https://github.com/andrewbearsley/forticnapp-azure-agentless-workload-scanning-guide" target="_blank">forticnapp-azure-agentless-workload-scanning-guide</a>

Reference: <a href="https://registry.terraform.io/modules/lacework/agentless-scanning/azure/latest" target="_blank">lacework/agentless-scanning/azure</a>

### Step 2: Path B, Console wizard

Tick **Agentless Workload Scanning** in the Step 1 wizard and provide regions + monitored subscription IDs on Step 2 of the wizard. The wizard deploys a default agentless setup using FortiCNAPP-managed defaults for VNet, NAT, and scheduling. Good for single-subscription and standard environments.

---

## Step 3: FortiGate Security Fabric Integration

Bringing FortiGate-VMs deployed in Azure into FortiCNAPP enriches resource visibility with network exposure context: workloads reachable from the internet without a FortiGate in the path get a higher risk score than those behind one, even at the same CVE. FortiGates also show up in Resource Inventory under Next-Gen Firewall, and path analysis in the Explorer graph colours paths blue (FortiGate in path) or red (no FortiGate, exposed).

### How it actually works

There's no separate "add FortiGate" connector to configure in the FortiCNAPP console. The integration is passive on the FortiCNAPP side:

- The **Azure Config integration** from Step 1 already inventories every Azure resource in scope, including FortiGate-VMs
- FortiCNAPP recognises FortiGate-VMs as firewalls and uses the Azure network topology (NSGs, route tables, public IPs, load balancers) to determine whether a given workload's path to the internet traverses one
- No API token, no Fabric Connector configuration on the FortiCNAPP side

The work to do is on the FortiGate / Azure side: confirm the FortiGate-VMs are deployed in a pattern FortiCNAPP recognises.

### Supported Azure deployment patterns

| Pattern | Notes |
|---|---|
| **Single instance** | Standalone FortiGate-VM |
| **Fabric Connector Failover (SDN)** | Active/Passive HA pair using the Fortinet Fabric Connector for Azure |
| **Standard Load Balancer (SLB)** | Active/Passive HA pair fronted by an Azure Standard Load Balancer |

If your FortiGates run in HA, they need to be in one of the two HA patterns specifically. Other HA approaches won't be picked up correctly by the path analysis. Your network team owns the FortiGate-side configuration; see the <a href="https://docs.fortinet.com/document/fortigate/latest/administration-guide" target="_blank">FortiOS Administration Guide</a> for the FortiGate-side deployment details.

### Setup checklist

This usually means coordinating with the network team rather than configuring FortiCNAPP directly:

1. **Confirm deployment pattern** with the network team: single instance, Fabric Connector Failover (SDN), or SLB HA
2. **Confirm Config integration is healthy** (Step 1): the scanning AD application has Reader at the management group, and FortiCNAPP has enumerated subscriptions containing the FortiGates
3. **Verify discovery in the console**: navigate to **Resource Inventory**, filter by **Next-Gen Firewall** category (or search for FortiGate). The FortiGate-VMs should appear within an hour of the Config integration enumerating their subscription
4. **Check path analysis**: in the Explorer graph, look at a workload that sits behind a FortiGate. The path to the internet should colour blue. If it colours red despite the FortiGate being present, the deployment pattern isn't one of the three supported shapes

If the FortiGates don't appear in Resource Inventory at all, that points back at the Config integration (subscription not in scope, or AD app Reader role hasn't propagated). If they appear but path analysis still colours red, that's the deployment-pattern conversation with the network team.

Reference: <a href="https://docs.fortinet.com/document/forticnapp/26.2.0/administration-guide/639260/fortigate" target="_blank">FortiCNAPP Administration Guide: FortiGate Security Fabric integration</a>

---

## Step 4: Alert Channels

Alert channels forward FortiCNAPP-generated alerts to downstream tools. Alert rules bind channels to alert sources by severity threshold, integration, or resource group, so the same alert can fan out to multiple destinations (e.g. high-severity to PagerDuty + email + Splunk, everything else to Splunk only).

### Native channels

FortiCNAPP ships dedicated integrations for these destinations. No custom plumbing needed:

| Category | Channels |
|---|---|
| SIEM | Splunk (direct via HEC), Sumo Logic, Elastic / ELK Stack, IBM QRadar, FortiSIEM |
| Cloud-native eventing | Amazon EventBridge, Amazon Security Lake, AWS Security Hub, Google Cloud Pub/Sub, Google Eventarc |
| Chat | Slack, Microsoft Teams, Cisco Webex Teams |
| Incident / on-call | PagerDuty, Opsgenie, VictorOps (Splunk On-Call) |
| ITSM / ticketing | ServiceNow, Jira, Azure DevOps |
| Observability | Datadog, New Relic |
| SOAR | FortiSOAR |
| Generic | Email, Custom webhook |

**Notable for Azure shops**: there is no native Azure Event Hub channel. To land alerts in Event Hub, use the Custom Webhook pattern below.

### Setup

1. Navigate to **Settings > Notifications > Alert Channels**
2. Click **Add New** and choose the target channel type
3. Provide endpoint details (Splunk HEC URL + token, webhook URL, etc.)
4. Test the channel
5. Navigate to **Settings > Notifications > Alert Rules** and bind the channel to alert rules

### Pattern: Splunk direct via HEC

Cleanest path for Splunk forwarding. Create a Splunk HEC token, paste it into FortiCNAPP's Splunk alert channel along with the HEC URL. Done.

Reference: <a href="https://docs.fortinet.com/document/forticnapp/latest/administration-guide/440161/splunk-alert-channel" target="_blank">Splunk alert channel</a>

### Pattern: Custom Webhook to Azure Event Hub

If Event Hub is your standard ingest pattern (e.g. everything funnels through Event Hub on the way to Splunk, Sentinel, or a data lake), the recommended approach is to expose an HTTPS shim and use FortiCNAPP's Custom Webhook channel:

```
FortiCNAPP Custom Webhook  ─POST JSON─►  HTTPS shim  ─►  Azure Event Hub  ─►  downstream
```

The HTTPS shim is usually an Azure Function (HTTP-triggered) that validates the inbound POST (function key or shared secret in the header) and forwards the payload to Event Hub via a Managed Identity with the `Azure Event Hubs Data Sender` role. Logic Apps and APIM work too if either is already in the stack.

What the Azure side needs:

- Event Hub namespace + Event Hub (`azurerm_eventhub_namespace`, `azurerm_eventhub`)
- Shared access policy with `Send` permission, or a Managed Identity grant with `Azure Event Hubs Data Sender`
- HTTPS shim (Function App / Logic App / APIM) with the inbound URL and a shared secret
- Optional `azurerm_eventhub_namespace_network_rules` to lock the namespace down to known sources

Then in FortiCNAPP:

1. **Settings > Notifications > Alert Channels > Add New > Custom Webhook**
2. Paste the shim's HTTPS URL
3. Add the shared secret as a custom header (commonly `X-Webhook-Secret`)
4. Test

A turnkey implementation of this pattern (Terraform + Python Azure Function) is in the sibling repo: <a href="https://github.com/andrewbearsley/forticnapp-azure-eventhub-webhook-shim" target="_blank">forticnapp-azure-eventhub-webhook-shim</a>. Provisions the Event Hub Namespace, Hub, Storage Account, and Linux Function App with a System-Assigned Managed Identity granted `Azure Event Hubs Data Sender`, and ships the minimal Function code to validate the inbound POST and forward it to Event Hub.

Reference: <a href="https://docs.fortinet.com/document/forticnapp/latest/administration-guide/659277/datadog-alert-channel" target="_blank">FortiCNAPP Administration Guide: Alert Channels overview</a>

---

## Capability Coverage Matrix

| Capability | Source step | Notes |
|---|---|---|
| CSPM (continuous misconfig detection) | Step 1 (Config) | All subscriptions under the integration scope |
| CIEM (identity over-privilege) | Step 1 (Config) | Cloud-only Entra ID supported, PIM-gated roles respected |
| Compliance reporting | Step 1 (Config) | CIS, PCI, HIPAA, NIST, ISO 27001, SOC 2 out of the box. Custom frameworks supported. |
| DSPM | Step 1 (DSPM) | Storage Accounts + blob containers, deployed alongside Config + Activity Log |
| Secrets detection (blob storage) | Step 1 (DSPM) | Bundled into the Step 1 integration |
| Attack Path Analysis | Step 1 (Config) + Step 2 (Agentless) | Multi-hop combining misconfig + identity + CVE + network |
| VM CVE scanning | Step 2 (Agentless) | Includes stopped/offline VMs via disk snapshot |
| Secrets detection (disk) | Step 2 (Agentless) | Part of the agentless scanning job |
| FortiGate exposure context | Step 3 (FortiGate) | Network reachability enriches risk scores |
| SIEM forwarding | Step 4 (Alert channels) | Splunk, ServiceNow, Teams, email, webhooks |
| Unified risk console | All steps | Single portal consolidates findings from every source |

---

## IAM Permissions Summary

Provisioning the integration requires creating Azure AD applications, role assignments, and Storage Account / Event Hub resources for the Activity Log sink. The most common enterprise shape is Path A tenant-level covering Core + DSPM + Agentless, broken down below. Path B (Console wizard) is a different shape and covered separately.

### Path A tenant-level: PIM pattern (recommended)

Platform team grants the roles below as PIM-eligible. Apply principal activates for a 1 to 4 hour window, runs `terraform apply` (typically 10 to 20 minutes), activations auto-expire. Clean audit trail, no standing privilege.

| Role | Scope | Granted as |
|---|---|---|
| Owner (or UAA + Contributor) | Parent management group | PIM-eligible |
| Contributor + User Access Administrator | Scanning subscription | PIM-eligible |
| Application Administrator | Entra ID directory | PIM-eligible |

### Path A tenant-level: deployment-time permissions

What the apply principal needs at apply time, broken down by workload:

| Workload | Permission | Scope | Purpose |
|---|---|---|---|
| Core | User Access Administrator | Parent management group | Grant Reader to new AD app at MG |
| Core | Contributor | Deployment subscription | Create Storage Account + Event Hub for Activity Log sink |
| Core | `Microsoft.Insights/diagnosticSettings/write` | Management group | Create Activity Log diag setting on every child sub |
| Core | Application Administrator | Entra ID | Create AD application |
| DSPM | Contributor | Scanning subscription | Create Key Vault, Storage Account, Container App Job |
| DSPM | User Access Administrator | Parent management group | Grant Storage Blob Data Reader to DSPM SP across monitored subs |
| DSPM | User Access Administrator | Scanning subscription | Managed identity role assignment for Container App Job |
| DSPM | Application Administrator | Entra ID | Create DSPM AD application |
| Agentless | Contributor | Scanning subscription | Create VNet, NAT Gateway + Public IP, Storage, Key Vault, orchestrator Container App Job |
| Agentless | User Access Administrator | Parent management group | Grant Reader + disk snapshot action to agentless SP |
| Agentless | Application Administrator | Entra ID | Create agentless AD application |
| Agentless | Azure Policy exemption | Scanning subscription | Allow public IP on NAT Gateway, if Azure Policy denies public IPs tenant-wide |

Running Terraform as a service principal instead of a user: same RBAC at every scope, plus `Microsoft.Graph/Application.ReadWrite.OwnedBy` Graph API permission in Entra ID instead of Application Administrator.

Subscription-level deployments are a strict subset: replace Management group with the target subscription throughout, and drop the management-group-scoped diagnostic settings write (a per-subscription Contributor covers it).

### Path A tenant-level: granular alternative

If their platform team objects to Owner at the management group even via PIM:

| Role | Scope | Replaces |
|---|---|---|
| Reader + User Access Administrator + custom role with `Microsoft.Insights/diagnosticSettings/write` | Management group | Owner at MG |
| Contributor | Deployment subscription | (no change) |
| Contributor + User Access Administrator | Scanning subscription | (no change) |
| Application Administrator (or `Application.ReadWrite.OwnedBy` Graph API) | Entra ID | (no change) |

Same outcome, narrower verbs. Useful when their security team's instinct is "no Owner role assignments".

### Path B (Console wizard, Automated method): deployment-time

The wizard SP needs:

- **Owner** on the target subscription (resource creation + role assignment)
- **Application Administrator** + **Privileged Role Administrator** in Entra ID, assigned to the SP itself

The human assigning those directory roles must hold Privileged Role Administrator or Global Administrator in the deployment tenant. In corporate environments this is typically restricted to a small IT admin team. Coordinate ahead of time or use Path A.

### Runtime permissions

The created service principals are granted read-class access only. No write permissions on monitored resources.

| Workload | Permission | Scope |
|---|---|---|
| Core | Reader | Management group (cascades to all child subs) |
| Core | Reader | Activity Log Event Hub / Storage Account |
| DSPM | Storage Blob Data Reader | Management group (cascades to monitored subs) |
| DSPM | Key Vault Crypto User | Scanning sub Key Vault |
| Agentless | Reader | Management group |
| Agentless | `Microsoft.Compute/disks/beginGetAccess/action` | Monitored subscriptions |
| Agentless | Write to scanning storage | Scanning subscription |

For Azure Policy DENY environments (common in ALZ deployments, e.g. DENY on public IP creation), the only resource type that typically needs an exemption is the NAT Gateway public IP in the agentless scanning subscription. The exemption can be scoped to the scanning subscription only.

For agentless workload scanning specifically, see the sibling guide's <a href="https://github.com/andrewbearsley/forticnapp-azure-agentless-workload-scanning-guide#iam-permissions" target="_blank">IAM Permissions section</a>.

---

## How It Works

### Step 1 (Config): Process

1. An Azure AD application (service principal) is created with read-only permissions across monitored subscriptions
2. FortiCNAPP polls Azure ARM APIs continuously to enumerate resources and configurations
3. Resource state is evaluated against active compliance frameworks
4. Misconfigurations surface as policy violations under **Compliance > Resources** and **Reports**

### Step 1 (Activity Log): Process

1. A diagnostic setting is created on each monitored subscription, exporting Activity Log events to a customer-side Event Hub or Storage Account
2. FortiCNAPP pulls events at regular intervals
3. Events are normalised and used to build the **Polygraph** behavioural baseline, joined with Config posture data
4. Anomalous activity, known malicious threats, and resource-change events surface under **Events > Cloud Activity** and feed composite alerts

### Step 2 (Agentless): Process

See <a href="https://github.com/andrewbearsley/forticnapp-azure-agentless-workload-scanning-guide#how-it-works" target="_blank">sibling guide</a> for the full scanning lifecycle.

### Attack Path Analysis: Process

Once Step 1 + Step 2 data is present, FortiCNAPP automatically constructs attack-path graphs. No additional configuration is needed. Paths surface under **Attack Path Analysis** in the console and are factored into prioritised risk lists.

---

## Resources

- <a href="https://docs.fortinet.com/document/forticnapp/latest/administration-guide/729300/integrating-your-azure-environment" target="_blank">FortiCNAPP: Integrating your Azure environment</a>
- <a href="https://docs.fortinet.com/document/forticnapp/latest/administration-guide/991151/preparing-for-integration" target="_blank">FortiCNAPP: Preparing for integration</a>
- <a href="https://registry.terraform.io/modules/lacework/ad-application/azure/latest" target="_blank">Terraform Registry: lacework/ad-application/azure</a>
- <a href="https://registry.terraform.io/modules/lacework/config/azure/latest" target="_blank">Terraform Registry: lacework/config/azure</a>
- <a href="https://registry.terraform.io/modules/lacework/activity-log/azure/latest" target="_blank">Terraform Registry: lacework/activity-log/azure</a>
- <a href="https://registry.terraform.io/modules/lacework/dspm/azure/latest" target="_blank">Terraform Registry: lacework/dspm/azure</a>
- <a href="https://registry.terraform.io/modules/lacework/agentless-scanning/azure/latest" target="_blank">Terraform Registry: lacework/agentless-scanning/azure</a>
- <a href="https://github.com/andrewbearsley/forticnapp-azure-agentless-workload-scanning-guide" target="_blank">Sibling guide: Azure Agentless Workload Scanning</a>
