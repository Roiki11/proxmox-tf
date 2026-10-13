# Examples

Ready-to-adapt configurations for this project. Each `*.tfvars.example` is
copied to `terraform.tfvars` (gitignored) in the repository root:

```bash
cp examples/terraform.tfvars.example terraform.tfvars
$EDITOR terraform.tfvars
```

Every example reads its credentials from a HashiCorp Vault KV-v2 secret — no
secrets belong in the tfvars files. Seed the secret first (`make help` shows
the workflow; the expected fields are documented in `vault.tf` and in
[docs/VARIABLES.md](../docs/VARIABLES.md)).

| Example | Scope |
|---------|-------|
| [`terraform.tfvars.example`](terraform.tfvars.example) | **Start here.** Complete 3-node HA cluster walkthrough across all phases: installer defaults, one BMC per node (Redfish machine installation), live cluster management, storage/network/SDN, PDM registration. |
| [`minimal.tfvars.example`](minimal.tfvars.example) | Smallest viable setup: one standalone node (no cluster hook, no BMC flow). Good for a first pipeline test — build the ISO, boot a machine, done. |
| [`three-node-ha.tfvars.example`](three-node-ha.tfvars.example) | Production-shaped HA stack: LACP bonds + VLAN-aware bridges, VLAN/VXLAN SDN zones with VNets/subnets, Ceph pools, PBS backup target, Vault PKI node certificates, PDM with per-node firewall/APT config. |

## Workflow (3-node example)

```bash
make init                # tofu init (providers + lockfile)

# one-time: seed the Vault KV secret (fields in vault.tf / docs/VARIABLES.md)
vault kv put kv/proxmox-tf/cluster root_password=... root_password_hashed=...

make isos                # phase 1: build/iso/<node>-auto.iso per node
make iso-serve           # serve the ISOs over HTTP (reachable from the BMCs)
make node-install        # phase 1.5: install every unprovisioned BMC node
make node-wait-all       # block until all PVE APIs answer

# enable phase 2/3 in terraform.tfvars (manage_pve_resources / pdm_enabled),
# then:
make apply               # cluster options, TLS certs, storage, SDN, PDM
make pve-storage         # ... or apply each area selectively
make pve-network         #   (bridges/bonds/vlans)
make pve-sdn             #   (zones/vnets/subnets)
make pve-ceph            #   (pools)
```

## Phase notes

- **Phase 1** (ISO + installation) only needs Vault and the container engine —
  no live cluster.
- **Phase 1.5** (Redfish installation) needs one BMC block per node and
  `node_install_enabled = true` (the `node-install` make target forces it).
  Boot-override is Dell/iDRAC-specific; `redfish_virtual_media` and
  `redfish_power` speak standard Redfish.
- **Phase 2/3** need the cluster online at `pve_endpoint` (and PDM reachable
  for phase 3).

All variables (types, defaults, field-level docs): [docs/VARIABLES.md](../docs/VARIABLES.md).
