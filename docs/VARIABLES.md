# Variable reference

Every input variable of this project, grouped by phase. Types and defaults
match the `variables*.tf` definitions — the source of truth; those files also
carry per-field documentation for the complex map variables.

Conventions:

- **Required** variables have no default; everything else is optional.
- Sensitive values never appear in configuration — they come from a Vault
  KV-v2 secret (see [Secrets](#secrets) at the bottom).
- Apply order and phase gating are described in the
  [main README](../README.md); ready-to-copy configurations live in
  [`examples/`](../examples/README.md).

## Phase 1 — cluster topology (`variables.tf`)

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `cluster_name` | string | — (required) | Name of the PVE cluster. 1–15 characters (validated). |
| `cluster_domain` | string | `"lan"` | DNS search domain used for node FQDNs (`<node>.<domain>`). |
| `nodes` | map(object) | — (required) | Nodes to install; the key becomes the hostname. See [node fields](#nodes-fields). |
| `node_defaults` | object | `{}` | Defaults for every node (per-node values win). Fields mirror the node fields. |
| `bootstrap_node` | string | `""` | Node that creates the cluster on first boot. Defaults to the alphabetically first node key. |
| `cluster_bootstrap_enabled` | bool | `true` | Embed a first-boot hook in each ISO so nodes create/join the cluster automatically. Set `false` for standalone nodes. |

<a id="nodes-fields"></a>

### `nodes` / `node_defaults` fields

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `management_cidr` | string | — (required per node) | Management IP in CIDR notation (e.g. `"10.0.0.11/24"`). |
| `gateway` | string | `node_defaults` | Default gateway. |
| `dns_server` | string | `node_defaults` | DNS server used by installer and node. |
| `dhcp` | bool | `node_defaults` (`false`) | Let the installer use DHCP instead of the static CIDR. |
| `nic_filter` | map(string) | `node_defaults` | udev properties selecting the management NIC (e.g. `{"ID_NET_NAME" = "eno1"}`). |
| `disks` | list(string) | `node_defaults` (`[]`) | Disk list for `[disk-setup]` (e.g. `["sda", "sdb"]`). Must be `[]` when `disk_filter` is set. |
| `disk_filter` | map(string) | `node_defaults` (`{}`) | udev properties selecting disks instead of the list (e.g. `{"ID_SERIAL" = "KIOXIA*"}`). |
| `filter_match` | string | `node_defaults` (`"any"`) | `"any"` or `"all"` — how `disk_filter`/`nic_filter` terms combine. |
| `filesystem` | string | `node_defaults` (`"ext4"`) | `ext4`, `xfs`, `zfs` or `btrfs` (validated). |
| `zfs_raid` | string | `node_defaults` | ZFS level when `filesystem = "zfs"`: `raid0`, `raid1`, `raid10`, `raidz-1`, `raidz-2`, `raidz-3` (validated). |
| `zfs_ashift` | number | `node_defaults` | ZFS ashift (usually `12` for 4K sectors). |
| `zfs_arc_max` | number | `node_defaults` | ZFS ARC maximum in MiB. |
| `lvm_hdsize` | number | `node_defaults` | `hdsize` in GiB for ext4/xfs (space reserved at disk end). |
| `lvm_swapsize` | number | `node_defaults` | Swap size in GiB for ext4/xfs. |
| `timezone` | string | `node_defaults` (`"UTC"`) | tzdata timezone. |
| `bmc` | object | `null` | BMC connection for the Redfish flow — see below. |

### `nodes.<name>.bmc` fields

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `address` | string | — (required) | BMC endpoint (e.g. `"https://10.0.0.201"`). |
| `username` | string | `"root"` | BMC user. |
| `password_vault_field` | string | `"bmc_<node>_password"` | Vault KV field holding the BMC password. |
| `boot_target` | string | `"Cd"` | One-time boot source override target (vendor-specific spelling). |

## Phase 1 — installer and ISO generation (`variables-installer.tf`)

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `root_ssh_keys` | list(string) | `[]` | SSH public keys for root on every installed node. |
| `keyboard` | string | `"en-us"` | Keyboard layout (installer + console), e.g. `en-us`, `de`, `fi`. |
| `country` | string | `"us"` | Two-letter country code for nearby package mirror selection. |
| `mailto` | string | `null` | Default mail address for the root user. |
| `reboot_on_error` | bool | `false` | Reboot automatically on installer errors instead of dropping to a shell. |
| `post_installation_webhook` | object | `null` | `{ url, cert_fingerprint }` — endpoint the installer POSTs system info to after installation. |
| `container_engine` | string | `"docker"` | Container engine binary running the auto-install assistant (`docker` or `podman`). |
| `container_platform` | string | `""` | Optional `--platform`, e.g. `"linux/amd64"` when building on Apple Silicon. |
| `auto_install_assistant_image` | string | `"proxmox-auto-install-assistant:latest"` | Assistant container image (must contain the assistant + xorriso). |
| `pve_iso_url` | string | `null` | Base PVE ISO URL, auto-downloaded when missing. |
| `pve_iso_path` | string | `null` | Path of the prepared base ISO. Defaults to `<build_dir>/base/proxmox-ve.iso`. |
| `pve_iso_checksum` | string | `""` | Known base ISO checksum; ISOs rebuild automatically when it changes. |
| `iso_http_base_url` | string | `""` | Base URL serving `build/iso` over HTTP for Redfish virtual media (`make iso-serve`); must be reachable from the BMCs. |
| `build_dir` | string | `"./build"` | Output directory for answer files, hooks and ISOs. |

## Phase 1.5 — machine installation via Redfish (`variables-redfish.tf`)

The installation flow (`redfish.tf`) runs per node that has a `bmc` block and
whose PVE API does not answer at plan time: virtual media attach → one-time
boot override → power on. Dell/iDRAC-specific; virtual media and power speak
standard Redfish.

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `node_install_enabled` | bool | `false` | Enable the flow. `make node-install` forces this for its run. |
| `node_install_force` | bool | `false` | Re-install even when the node's PVE API already answers (dangerous). |
| `redfish_ssl_insecure` | bool | `true` | Skip TLS verification of BMC endpoints (self-signed certificates). |
| `node_install_reset_type` | string | `"ForceRestart"` | Reset applied after the boot override is armed (pre-17G iDRACs). One of `ForceRestart`, `GracefulRestart`, `PowerCycle` (validated); `PowerCycle` also powers off machines on. |
| `node_install_reset_timeout` | number | `600` | Seconds the provider waits for the reset. |
| `node_install_boot_job_timeout` | number | `1200` | Seconds the provider waits for the boot-override job. |
| `node_install_power_on` | bool | `true` | Additionally issue a `redfish_power` `ForceOn` afterwards (what actually boots 17G+ machines). |
| `node_install_power_wait` | number | `300` | Seconds the power resource waits for the desired power state. |

## Phase 2 — PVE connection and cluster options (`variables-management.tf`)

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `pve_endpoint` | string | `""` | Cluster API endpoint (e.g. `"https://10.0.0.11:8006/"`). Only contacted when `manage_pve_resources` is true. |
| `pve_username` | string | `"root@pam"` | PVE API user; its password/token comes from Vault (`pve_password`, `pve_api_token`). |
| `pve_insecure` | bool | `true` | Skip TLS verification of the PVE endpoint. |
| `manage_pve_resources` | bool | `false` | Phase 2 toggle — datacenter options, node TLS, storage/network/SDN/Ceph. |
| `cluster_options` | object | `{}` | Datacenter options: `language`, `keyboard`, `email_from`, `console`, `mac_prefix`, `max_workers`, `migration_cidr`, `migration_type`, `http_proxy`, `next_id_lower`, `next_id_upper`. |
| `cluster_dns_servers` | list(string) | `[]` | Extra DNS servers for `/etc/resolv.conf` on every node (per-node `dns_server` first). |

### Node TLS certificates (Vault PKI)

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `node_tls_enabled` | bool | `false` | Issue node certificates from Vault PKI and install them (cluster must be online). |
| `vault_pki_backend` | string | `"pki"` | Path of the PKI secret backend (e.g. `"pki_int"`). |
| `vault_pki_role` | string | `"proxmox-node"` | PKI role; must allow the node FQDNs in `allowed_domains`. |
| `vault_pki_ttl` | string | `"8760h"` | Certificate TTL (Vault duration). |
| `vault_pki_exclude_cn_from_sans` | bool | `true` | Exclude the CN from the certificate SANs (CN stays the subject). |
| `vault_pki_auto_renew` | bool | `true` | Renew node certificates shortly before expiry and reinstall them. |
| `vault_pki_min_seconds_remaining` | number | `604800` | Renew when less than this many seconds remain (default 7 days). |

## Vault connection (`variables-management.tf`)

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `vault_address` | string | `""` | Vault API address; empty uses the `VAULT_ADDR` environment variable. |
| `vault_kv_mount` | string | `"kv"` | KV-v2 mount holding the cluster secrets. |
| `vault_secrets_path` | string | `"proxmox-tf/cluster"` | Path of the KV-v2 secret (fields below). |

## Phase 3 — Proxmox Datacenter Manager (`variables-management.tf`)

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `pdm_enabled` | bool | `false` | Register/manage the cluster as a remote in PDM via its REST API. |
| `pdm_api_url` | string | `""` | Base URL of the PDM REST API (e.g. `"https://pdm.example.com:8007"`). |
| `pdm_api_user` | string | `"root@pam"` | PDM API user for ticket auth (its password/token comes from Vault). |
| `pdm_api_insecure` | bool | `true` | Skip TLS verification of the PDM endpoint. |
| `pdm_api_ca_file` | string | `""` | CA bundle verifying the PDM endpoint instead of skipping verification. |
| `pdm_remote_id` | string | `""` | Remote ID in PDM; defaults to `cluster_name`. |
| `pdm_remote_authid` | string | `null` | Authid PDM uses against the cluster. Defaults to the user/token created by this project, or the Vault field `pdm_remote_authid`. |
| `pdm_user_id` | string | `"pdm@pve"` | PVE user created for PDM when no pre-existing token is supplied. |
| `pdm_token_name` | string | `"pdm"` | Name of the PVE API token created for that user. |
| `pdm_acl_role` | string | `"Administrator"` | Role granted to the user/token on `/`. PDM needs broad read access. |
| `pdm_web_url` | string | `null` | Web UI URL stored on the PDM remote. |
| `pdm_verify_nodes` | bool | `true` | Probe every node's TLS certificate through PDM after registration. |
| `pdm_delete_token_on_destroy` | bool | `true` | Delete the remote's API token when the PDM remote is removed. |

### `pdm_node_config` (`variables-pdm.tf`)

Map of node name -> configuration applied through the PDM REST API (`make
pdm-node-apply`, or `make apply`). Keys must be node names from `var.nodes`
(validated). PDM 1.x only exposes writes for APT database updates and node
firewall options - everything else is read-only through PDM.

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `apt_update` | bool | `false` | Run the proxied APT database update (`POST .../apt/update`). |
| `firewall_options` | object | `null` | Body of `PUT .../firewall/options`; unset fields are omitted. |

`firewall_options` fields: `enable`, `log_level_in` / `log_level_out` /
`log_level_forward` (`emerg`..`nolog`), `log_nf_conntrack`, `ndp`, `nosmurfs`,
`nftables`, `protection_synflood`, `protection_synflood_rate`,
`protection_synflood_burst`, `nf_conntrack_max`,
`nf_conntrack_tcp_timeout_established`,
`nf_conntrack_tcp_timeout_syn_recv`, `tcpflags`.

## Phase 2 - storage (`variables-storage.tf`)

All maps are keyed by the storage ID. Common optional fields per entry:
`content` (list), `nodes` (list, empty = all nodes), `disable`, `backups`
(retention object: `keep_last`/`keep_hourly`/`keep_daily`/`keep_weekly`/
`keep_monthly`/`keep_yearly`/`keep_all`, `max_protected_backups`).

| Variable | Required fields | Type-specific fields |
|----------|-----------------|----------------------|
| `storage_directories` | `path` | `shared`, `create_base_path`, `create_subdirs`, `preallocation` (`metadata\|off\|full\|fallocated`), default content `["images", "iso"]`. |
| `storage_lvm` | `volume_group` | `wipe_removed_volumes`, `shared`, default content `["images", "rootdir"]`. |
| `storage_lvmthin` | `volume_group`, `thin_pool` | default content `["images", "rootdir"]`. |
| `storage_zfspool` | `zfs_pool` (e.g. `"rpool/data"`) | `thin_provision`, `blocksize` (e.g. `"64k"`), default content `["images", "rootdir"]`. |
| `storage_nfs` | `server`, `export` | `options` (e.g. `"vers=4.2"`), `preallocation`, `snapshot_as_volume_chain`. |
| `storage_cifs` | `server`, `share`, `username` | `domain`, `subdirectory`, `options`, `preallocation`, `snapshot_as_volume_chain`; SMB password from Vault `storage_<id>_password` (override: `password_vault_field`). |
| `storage_pbs` | `server`, `datastore`, `username` | `fingerprint`, `namespace`, `generate_encryption_key`; password from `storage_<id>_password`, optional key from `storage_<id>_encryption_key` (both overridable via `password_vault_field` / `encryption_key_vault_field`); default content `["backup"]`. |

## Phase 2 - node network interfaces (`variables-network.tf`)

Interfaces are staged (`reload = false` default) and activated per node by
the network applier whenever any interface changes, so a batch of related
changes takes effect together. Set `reload = true` to reload immediately
instead. Common fields: `node_name` (required), `name` (required),
`address` (CIDR), `gateway`, `mtu`, `autostart` (`true`), `comment`,
`reload`.

| Variable | Required fields | Type-specific fields |
|----------|-----------------|----------------------|
| `network_bridges` | - | `ports` (list, e.g. `["eno1"]` or `["bond0"]`), `vlan_aware`, `vids` (`"2-4094"`). |
| `network_bonds` | `slaves` | `bond_mode` (`balance-rr`, `active-backup`, `balance-xor`, `broadcast`, `802.3ad`, `balance-tlb`, `balance-alb` - validated), `bond_primary`, `bond_xmit_hash_policy` (`layer2`, `layer2+3`, `layer3+4` - validated). |
| `network_vlans` | - | `interface` + `vlan` (or `name = "eno1.99"` shorthand), i.e. VLAN subinterfaces. |

## Phase 2 - SDN (`variables-sdn.tf`)

Zones -> VNets -> subnets; staged changes are activated by the SDN applier
(`sdn_apply`, default `true`). Zone `type` is validated to
`simple | vlan | vxlan | evpn`.

| Variable | Required fields | Type-specific fields |
|----------|-----------------|----------------------|
| `sdn_zones` | `type` | Common: `nodes`, `mtu`, `dns`, `dns_zone`, `ipam`, `reverse_dns`, `dhcp` (dnsmasq). `vlan`: `bridge`. `vxlan`: `peers` (node IPs). `evpn`: `controller`, `vrf_vxlan`, `advertise_subnets`, `disable_arp_nd_suppression`, `exit_nodes`, `exit_nodes_local_routing`, `primary_exit_node`, `rt_import`. |
| `sdn_vnets` | `zone` (a `sdn_zones` key) | `tag`, `alias`, `isolate_ports`, `vlan_aware`. |
| `sdn_subnets` | `vnet` (a `sdn_vnets` key), `cidr` | `gateway`, `snat`, `dhcp_dns_server`, `dns_zone_prefix`. (DHCP ranges are not declarable - bpg/proxmox limitation, see variables-sdn.tf.) |
| `sdn_apply` | - | bool - create the applier that activates staged changes (`PUT /cluster/sdn`). |

## Phase 2 - Ceph (`variables-ceph.tf`)

| Variable | Required fields | Fields |
|----------|-----------------|--------|
| `ceph_pools` | - (keyed by pool name) | `node_name` (defaults to the bootstrap node), `size`, `min_size`, `pg_num`, `pg_num_min`, `pg_autoscale_mode` (`on\|off\|warn` - validated), `application` (`rbd\|cephfs\|rgw` - validated), `crush_rule`, `erasure_coding` (`"k=4,m=2"`), `target_size`, `target_size_ratio`, `add_storages`. |

The provider manages pools only - bootstrap monitors/OSDs manually first
(e.g. `pveceph init` + OSD creation via the UI).

<a id="secrets"></a>

## Secrets

No credentials live in configuration. Everything is read at plan time from
one Vault KV-v2 secret (mount `vault_kv_mount`, path `vault_secrets_path`);
the Vault provider authenticates via the `VAULT_ADDR` / `VAULT_TOKEN`
environment variables (or an `auth_login_*` block in `providers.tf`).

Seed once, e.g.:

```bash
vault kv put kv/proxmox-tf/cluster \
  root_password=...            root_password_hashed=... \
  pve_password=...             pve_api_token=... \
  subscription_key=...         post_installation_webhook_token=... \
  pdm_password=...             pdm_api_token=... \
  pdm_remote_token=...         pdm_remote_authid=... \
  bmc_node01_password=...      bmc_node02_password=... \
  bmc_node03_password=...      storage_backup_password=...
```

| Vault field | Used by | Notes |
|-------------|---------|-------|
| `root_password` | installer answer files | Root password on every installed node (also the `pve_password` fallback). |
| `root_password_hashed` | installer answer files | Pre-hashed alternative (crypt(6) SHA-512); takes precedence in the answer file. |
| `pve_password` / `pve_api_token` | PVE API provider (phase 2) | Token wins when present. |
| `subscription_key` | installer answer files | Optional PVE subscription key. |
| `post_installation_webhook_token` | installer first-boot hook | Bearer token for `post_installation_webhook`. |
| `bmc_<node>_password` | Redfish flow | Per-node BMC password; rename via `nodes.<node>.bmc.password_vault_field`. |
| `pdm_password` / `pdm_api_token` | PDM REST API | Token wins when present. |
| `pdm_remote_token` / `pdm_remote_authid` | PDM remote registration | Optional pre-existing cluster token; when absent the project creates `pdm_user_id`/`pdm_token_name`. |
| `storage_<id>_password` | CIFS/PBS storages | SMB or PBS password. |
| `storage_<id>_encryption_key` | PBS storages | Optional existing encryption key. |

> **State note:** credentials consumed by resources (BMC passwords, PDM API
> credentials) are written to the state file — always use an encrypted remote
> backend for this project.

## See also

- [`examples/`](../examples/README.md) — ready-to-copy configurations
- [`vault.tf`](../vault.tf) — the Vault data source and expected fields
- [`variables*.tf`](..) — definitions with per-field docs (source of truth)