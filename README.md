# proxmox-tf

Terraform/OpenTofu project that bootstraps **Proxmox VE clusters** end-to-end:

1. **Node installation** — renders one `answer.toml` per node and builds a per-node
   automated-installation ISO with `proxmox-auto-install-assistant` running inside a
   container (image built from *proxmox_auto_install_assistant_container*).
2. **Cluster formation** — a first-boot hook embedded in each ISO creates the cluster on
   the bootstrap node (`pvecm create`) and joins the members non-interactively (PVE
   cluster-join API, the same flow the web UI "Join Cluster" dialog uses).
3. **Settings management** — once the nodes are up, datacenter options plus per-node
   DNS, `/etc/hosts` and timezone are managed through the [bpg/proxmox](https://registry.terraform.io/providers/bpg/proxmox/latest/docs) provider.
4. **Datacenter Manager registration** — a dedicated PVE user + API token for PDM is
   created and the cluster is registered as a remote in **Proxmox Datacenter Manager**
   through its **REST API** (`/api2/json/remotes/remote*`) — no SSH access to the PDM
   host needed.
5. **Secrets from HashiCorp Vault** — all credentials (node root password, PVE API
   credentials, PDM API credentials, subscription keys) are fetched from a Vault KV-v2
   secret; nothing sensitive lives in the configuration or `.tfvars` files.
6. **Node TLS certificates** — per-node certificates are issued from a Vault PKI
   secret backend and installed on the nodes, replacing the default self-signed
   `pveproxy` certificates.
7. **Node configuration through PDM** — applies APT database updates and node
   firewall options through PDM's proxied REST API
   (`/pve/remotes/{remote}/nodes/{node}/...`), with Makefile tasks for
   inspecting node status, network, storage, repositories, subscription and
   pending updates.
8. **Direct cluster configuration** — storage definitions (directory, LVM,
   thin LVM, ZFS, NFS, CIFS, PBS), node network interfaces (bridges, bonds,
   VLANs with staged-change applier), SDN (zones, VNets, subnets, apply) and
   Ceph pools are managed declaratively through the `bpg/proxmox` provider,
   applied with `make pve-storage`, `make pve-network`, `make pve-sdn` or
   `make pve-ceph`.

```
                       ┌────────────────────────────────────────────┐
 var.nodes ──────────► │  Phase 1 (offline)                         │
                       │  templates/answer.toml.tftpl               │
                       │  templates/first-boot-{leader,member}.tftpl│
                       │          │                                 │
                       │          ▼                                 │
                       │  scripts/build-iso.sh                      │
                       │  (assistant container, prepare-iso)        │
                       └───────────┬────────────────────────────────┘
                                   ▼
                     build/iso/<node>-auto.iso  ──►  write to USB/PXE/iKVM
                                   ▼
                     nodes install + auto-create/join cluster
                                   ▼
                       ┌────────────────────────────────────────────┐
   Vault KV-v2 ──────► │  Phase 2 (live cluster)                    │
   Vault PKI ────────► │  settings.tf  datacenter + node settings   │
                       │  tls: Vault-issued node certificates       │
                       │  pdm.tf       user/token + PDM REST API    │
                       └────────────────────────────────────────────┘
```

## Requirements

- Terraform >= 1.6 or OpenTofu >= 1.6 (`tofu`/`terraform` both work)
- A reachable HashiCorp Vault with:
  - a KV-v2 secret holding the cluster credentials (fields documented in `vault.tf`)
  - a PKI secret backend + role for the node certificates (when `node_tls_enabled`)
- For phase 2: API access to the cluster (root@pam or an API token from Vault)
- For phase 3: network access to the PDM REST API (default `https://<pdm>:8007`)

## Workflow

```bash
export VAULT_ADDR="https://vault.example.com:8200"
export VAULT_TOKEN="hvs...."          # or use agent / kubernetes auth

# seed the credentials (one-time; use e.g. `vault kv put` or CI automation):
vault kv put kv/proxmox-tf/cluster \
    root_password='...' pve_password='...' pdm_password='...'

cp examples/terraform.tfvars.example terraform.tfvars   # then edit
make init
make isos        # Phase 1: build/iso/<node>-auto.iso for every node
# write/boot the ISOs on the machines; installation + clustering is automatic
# verify: ssh root@10.0.0.11 'pvecm status'
# then enable phase 2/3 in terraform.tfvars:
#   manage_pve_resources = true
#   node_tls_enabled     = true
#   pdm_enabled          = true
make apply
```

`make isos` only targets the ISO-build resources, so it works before any cluster exists.
`make apply` with `manage_pve_resources = true` requires the cluster to be reachable at
`pve_endpoint`.

## How node installation works

Each node gets its own ISO, prepared with:

```bash
proxmox-auto-install-assistant prepare-iso <base.iso> \
    --fetch-from iso \
    --answer-file /work/answers/<node>/answer.toml \
    --on-first-boot /work/hooks/<node>/first-boot.sh \
    --output /work/iso/<node>-auto.iso
```

The answer files follow the official [Automated Installation](https://pve.proxmox.com/wiki/Automated_Installation)
schema (`[global]`, `[network]`, `[disk-setup]`, optional `[post-installation-webhook]` and
`[first-boot]` sections). Disk and NIC selection is done either by explicit lists
(`disk-list`) or by udev property filters (`filter.ID_SERIAL = "KIOXIA*"`, …). Use
`proxmox-auto-install-assistant device-info` / `device-match` on a target machine to find
matching properties.

### Cluster bootstrap hooks

- **Leader** (`bootstrap_node`, defaults to the alphabetically first node):
  `pvecm create <cluster_name> --link0 <management_ip>`.
- **Members**: wait for the leader's API, read its TLS certificate fingerprint with
  `openssl`, authenticate to the local PVE API with the root password and issue
  `POST /cluster/config/nodes {hostname, password, fingerprint, link0}` — the API-join
  flow (identical to `pvecm add` without `--use_ssh`). Both hooks retry and are
  idempotent (they no-op when a corosync config already exists).

> **Note on secrets**: all credentials are fetched from the Vault KV-v2 secret
> (`data.vault_kv_secret_v2`), so no secrets appear in the configuration or tfvars.
> The plaintext root password is embedded in the answer files and in member first-boot
> hooks (needed for the join API), therefore inside the ISOs, and secrets transit
> through the state file — treat `build/`, the ISOs and the state like credentials and
> use an encrypted/remote state backend. For standalone installs
> (`cluster_bootstrap_enabled = false`) the secret may provide
> `root_password_hashed` instead.

## Settings managed (phase 2)

| Resource | Purpose |
| --- | --- |
| `proxmox_cluster_options` | Datacenter options (GUI language, email, migration network/type, VMID range, …) via `var.cluster_options` |
| `proxmox_virtual_environment_time` | Timezone per node |
| `proxmox_virtual_environment_dns` | Search domain + resolvers per node |
| `proxmox_virtual_environment_hosts` | `/etc/hosts` entries for all cluster members on every node |

## PDM management via REST API (phase 3)

When `pdm_enabled = true` the project talks directly to the PDM REST API
(`pdm_api_url`, e.g. `https://pdm.example.com:8007`):

1. creates `pdm@pve` with an API token on the cluster and grants `Administrator` on `/`
   (skipped when the Vault secret provides `pdm_remote_token` / `pdm_remote_authid` for
   a pre-existing token),
2. authenticates to PDM (`POST /api2/json/access/ticket` with the Vault field
   `pdm_password`, or `pdm_api_token` via the `PVEAPITicket` header),
3. registers the remote idempotently — `POST /api2/json/remotes/remote` when missing,
   `PUT /api2/json/remotes/remote/{id}` when it exists (`scripts/register-pdm-remote.sh`),
4. optionally probes every node's TLS certificate
   (`POST /api2/json/remotes/remote/{id}/probe-certificate`, `pdm_verify_nodes`),
5. removes the remote again on `make destroy`
   (`DELETE /api2/json/remotes/remote/{id}?delete-token=...`, token deletion configurable),
6. applies per-node configuration (APT updates, firewall options) declared in
   `pdm_node_config` — see "Node configuration through PDM" below.

## Node TLS certificates (phase 2)

With `node_tls_enabled = true`, each node gets a certificate issued by the Vault PKI
secret backend (`vault_pki_backend` / `vault_pki_role`): `CN = <node>.<cluster_domain>`,
`IP SAN = <management IP>`, TTL `vault_pki_ttl`, installed via
`proxmox_virtual_environment_certificate` (replaces the default self-signed
`pveproxy` certificate). With `vault_pki_auto_renew = true` certificates renew
automatically before expiry and are reinstalled on the nodes.

Trust the issuing CA once on the PDM host (`/usr/local/share/ca-certificates/...crt`
+ `update-ca-certificates`): PDM then verifies the nodes through the system trust
store and no fingerprint pinning is needed. Pinning is not exposed by the PDM REST
API of current versions (privileged CLI only); the `probe-certificate` call in the
registration script verifies the effective TLS trust instead.

## Variables

See the commented `variables*.tf` files and `examples/terraform.tfvars.example` for the
full list. Key ones: `cluster_name`, `nodes`, `node_defaults`, `bootstrap_node`,
`pve_iso_url`, `auto_install_assistant_image`, `container_*`, `pve_*` (API access),
`manage_pve_resources`, `node_tls_enabled`, `vault_*` (KV mount/path, PKI backend/role),
`pdm_*` (REST API URL and remote options).

**Secrets**: none in configuration — see `vault.tf` for the expected Vault KV-v2
fields (`root_password`, `root_password_hashed`, `pve_password`, `pve_api_token`,
`subscription_key`, `post_installation_webhook_token`, `pdm_password`,
`pdm_api_token`, `pdm_remote_token`, `pdm_remote_authid`).

## Outputs

`node_isos`, `node_answer_files`, `node_first_boot_hooks`, `bootstrap_node`,
`installation_instructions`, `pve_nodes`, `node_certificates`, `secrets_source`,
`pdm_remote_id`, `pdm_authid`.

## Direct cluster configuration (phase 2)

Everything below is declared in `variables-storage.tf`, `variables-network.tf`,
`variables-sdn.tf` and `variables-ceph.tf`, managed through the `bpg/proxmox`
provider, and gated by `manage_pve_resources`. Apply everything (`make apply`)
or per area:

| Task | Contents |
| --- | --- |
| `make pve-storage` | Directory, LVM, thin-LVM, ZFS, NFS, CIFS and PBS storages (keyed by storage ID; optional backup retention blocks) |
| `make pve-network` | Per-node bridges, bonds and VLAN interfaces — staged by default (`reload = false`) and activated in one reload per node by `proxmox_network_applier` whenever any managed interface changes |
| `make pve-sdn` | SDN zones (`simple`/`vlan`/`vxlan`/`evpn`), VNets and subnets, activated by `proxmox_sdn_applier` when `sdn_apply = true` |
| `make pve-ceph` | Ceph pools (size/min_size, PG settings, CRUSH rule, erasure coding, `add_storages`) |

Referencing rules are validated: VNets must reference declared zones, subnets
must reference declared VNets, and per-node fields (`node_name`, bridge
ports, applier nodes) must match `var.nodes`. CIFS/PBS credentials come from
the Vault secret (fields `storage_<id>_password` and
`storage_<id>_encryption_key`, override with `password_vault_field` /
`encryption_key_vault_field`).

Notes:
- Ceph pools only: the provider does not deploy monitors/OSDs — initialize
  Ceph on a node first (e.g. `pveceph init`), then declare pools.
- The network/SDN appliers are experimental in the provider; pin the provider
  version (the lockfile does).

## Node configuration through PDM (phase 3)

PDM proxies a subset of the PVE node API under
`/api2/json/pve/remotes/{remote}/nodes/{node}/...`. Writable through PDM:

| Operation | Endpoint | Driven by |
| --- | --- | --- |
| Refresh APT package database | `POST .../apt/update` | `pdm_node_config.<node>.apt_update` on apply, or `make pdm-node-apt-update PDM_NODE=<name>` |
| Node firewall options | `PUT .../firewall/options` | `pdm_node_config.<node>.firewall_options` on apply, or `make pdm-node-apply` |

Read-only inspection tasks (connection settings via `PDM_API_URL`,
`PDM_API_USER`/`PDM_API_PASSWORD` or `PDM_API_TOKEN` env vars; `PDM_REMOTE_ID`
defaults to the `pdm_remote_id` output):

```bash
make pdm-node-status       PDM_NODE=node01   # node status
make pdm-node-config       PDM_NODE=node01   # node configuration
make pdm-node-network      PDM_NODE=node01   # network interfaces (read-only)
make pdm-node-updates      PDM_NODE=node01   # pending APT updates
make pdm-node-repositories PDM_NODE=node01   # APT repositories
make pdm-node-subscription PDM_NODE=node01   # subscription status
make pdm-node-storage      PDM_NODE=node01   # storage status
make pdm-updates-refresh                     # refresh PDM's cached update summary
make pdm-updates-summary                     # show PDM's update summary
```

Apply the declarative `pdm_node_config` for every node with `make apply`, or a
single node with `make pdm-node-apply PDM_NODE=node01`. The applied resource is
`terraform_data.pdm_node_config` (`pdm-nodes.tf`), which re-runs when the
configuration, credentials or remote change; changes are not reverted on
destroy (an APT update cannot be undone).

> **Note**: in PDM 1.x the proxied endpoints are read-only for network
> interfaces, subscription and power management, and storage/repositories are
> inspect-only. Manage those on PVE directly (e.g. via the `bpg/proxmox`
> provider's network/storage resources).

## Limitations / notes

- The Vault PKI role must allow the node FQDNs (`allowed_domains` incl. subdomains)
  and IP SANs (`allow_ip_sans = true`); the certificates carry `CN=<fqdn>` and
  `IP SAN=<management IP>` only.
- ISOs are built one per node (answer files are embedded per-ISO). For fleet
  installations, the HTTP answer-file source (DNS/DHCP option 250 or PDM "Prepared
  Answers") scales better; the answer templates here can be adapted for that.
- The base ISO must be new enough for automated installation (PVE 8.2-1+; kebab-case
  keys used here require 8.4-1+ / 9.x).
- Running on Apple Silicon? Set `container_platform = "linux/amd64"` (the assistant is
  x86_64-only) — the generated ISOs still run on amd64 machines.
- Destroying `terraform_data.node_iso` only deletes generated files; it does not touch
  installed machines.
- The PDM REST API paths follow PDM 1.x (`/api2/json/remotes/remote*`); if your PDM
  version differs, check the built-in API viewer (`https://<pdm>:8007/api-viewer/`) and
  adjust `scripts/register-pdm-remote.sh` accordingly.
- 3+ node clusters are recommended for HA quorum; a 2-node cluster needs a QDevice,
  which can be added manually afterwards (`pvecm qdevice setup`).

- A container engine (docker or podman) and an image containing
  `proxmox-auto-install-assistant` + `xorriso` — e.g. an image built from
  `proxmox_auto_install_assistant_container`
- A reachable HashiCorp Vault with:
  - a KV-v2 secret holding the cluster credentials (fields documented in `vault.tf`)
  - a PKI secret backend + role for the node certificates (when `node_tls_enabled`)
- For phase 2: API access to the cluster (root@pam or an API token from Vault)
- For phase 3: network access to the PDM REST API (default `https://<pdm>:8007`)
