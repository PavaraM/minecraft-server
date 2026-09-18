# Minecraft Server (Fabric, v26.2) on Oracle Cloud

A self-hosted, modded Minecraft **Fabric** server (v26.2) running on Oracle Cloud
Infrastructure, built as an end-to-end DevOps project:

- **Terraform** provisions the cloud infrastructure (network + compute).
- **Ansible** configures the server (Docker, firewall, deploy + first-run world seed).
- **Docker Compose** runs the server container and applies mods.

- Live deployment: `ap-mumbai-1`, Ubuntu 24.04 (aarch64).

```
┌─────────────┐   terraform apply   ┌────────────────────────────────────────────┐
│ Terraform   │ ──────────────────► │ OCI (ap-mumbai-1)                          │
│ terraform/  │                     │  VCN 10.0.0.0/16                           │
└─────────────┘                     │  ├─ Internet Gateway                       │
                                    │  ├─ Route Table → 0.0.0.0/0 via IGW        │
┌─────────────┐   ansible-playbook  │  ├─ Security List                          │
│ Ansible     │ ──────────────────► │  │  25565/TCP Minecraft                    │
│ ansible/    │                     │  │  24454/UDP Simple Voice Chat            │
└─────────────┘                     │  │  22/TCP SSH                             │
                                    │  ├─ Public Subnet 10.0.1.0/24              │
┌─────────────┐   docker compose    │  └─ Instance VM.Standard.A1.Flex           │
│ Minecraft   │ ──────────────────► │      2 OCPU / 12 GB, Ubuntu 24.04          │
│ minecraft/  │                     │      itzg/minecraft-server (Fabric)        │
└─────────────┘                     └────────────────────────────────────────────┘
```

## Repository layout

| Path | Purpose |
| --- | --- |
| `terraform/` | OCI infrastructure as code (network, compute instance, outputs) |
| `ansible/` | Server provisioning: Docker, deploy Minecraft, firewall, world seed |
| `minecraft/` | Compose stack + CurseForge mod download script |
| `minecraft/compose.yaml` | Docker Compose definition for the server container |
| `minecraft/download_mods_curseforge.sh` | Downloads mods from CurseForge that Modrinth couldn't match |

## Components

### 1. Terraform (`terraform/`)

Provisions all cloud resources in a single module.

- **Network** — `VCN` (`10.0.0.0/16`), `Internet Gateway`, `Route Table`
  (default route via IGW), `Security List`, and a public `Subnet`
  (`10.0.1.0/24`, public IP allowed).
- **Security rules**
  - `25565/TCP` — Minecraft Java Edition (0.0.0.0/0)
  - `24454/UDP` — Simple Voice Chat (0.0.0.0/0)
  - `22/TCP` — SSH (0.0.0.0/0)
  - egress all traffic
- **Compute** — `VM.Standard.A1.Flex` (Ampere ARM, free-tier-friendly) with
  `2 OCPUs` and `12 GB`, Ubuntu 24.04 from the latest matching OCI image, and a
  public IP + SSH key from `terraform.tfvars`.
- **Data sources** — resolves the compartment name, latest Ubuntu 24.04 image
  for the chosen shape, and the availability domains.
- **Outputs** — compartment name, instance OCID, and the public IP
  (used as the Ansible inventory host).

Provider: `oracle/oci` (locked at `6.37.0` in `terraform/.terraform.lock.hcl`),
using the `terraform-lab` profile from your OCI CLI config.

| File | Contents |
| --- | --- |
| `terraform/main.tf` | All resources: VCN, gateway, route table, security list, subnet, instance |
| `terraform/data.tf` | Data sources: compartment, Ubuntu image, availability domains |
| `terraform/variables.tf` | Inputs with defaults (shape/OCPU/memory) |
| `terraform/outputs.tf` | Outputs |
| `terraform/provider.tf` | OCI provider + `config_file_profile` |
| `terraform/versions.tf` | Required provider declaration |
| `terraform/terraform.tfvars` | **Local only** (gitignored): compartment, availability domain, SSH key |

### 2. Ansible (`ansible/`)

A single playbook that configures the freshly provisioned server:

1. Updates apt and installs base tools (`ca-certificates`, `curl`, `git`, `rsync`).
2. Installs Docker from the official repository (arm64) plus the compose plugin,
   enables it, and adds the `ubuntu` user to the `docker` group.
3. Installs monitoring utilities (`htop`, `iotop`, `ncdu`).
4. Deploys the Minecraft stack to `/opt/minecraft`: copies `compose.yaml`,
   creates the `mods` dir, and copies `minecraft/mods/` contents.
5. **Seeds the world on first run only** — checks for
   `/opt/minecraft/world/level.dat`; if absent, rsyncs `minecraft/world/` to the
   server and fixes ownership. Subsequent runs leave the running world untouched.
6. Starts the stack via `docker compose up -d` as the `ubuntu` user.
7. Installs and configures **UFW** (`25565/tcp`, `24454/udp`).
8. Deploys a monitoring stack (see Known gaps) to `/opt/monitoring` and starts it.

Inventory: `ansible/inventory.ini` — host comes from the `MINECRAFT_HOST`
environment variable (keeps the live IP out of version control), user `ubuntu`.

### 3. Minecraft (`minecraft/`)

**`compose.yaml`** — runs `itzg/minecraft-server:latest`:

- `TYPE: FABRIC`, `VERSION: "26.2"`, `MEMORY: "10G"`
- `ONLINE_MODE: FALSE`, `WHITELIST: FALSE`
- Mods mounted read-only from `./mods → /mods`
- World mounted read-only from `./world → /world`
- Named volume `minecraft-data` mounted at `/data` persists server data (the
  world generated at `/world` is the seed; runtime state lives in the volume)
- Ports `25565/tcp` and `24454/udp`

**`download_mods_curseforge.sh`** — fallback downloader for mods that a
Modrinth-based script couldn't resolve. Requires `curl`, `jq`, and a
CurseForge API key:

```bash
export CURSEFORGE_API_KEY="your-key-here"
./minecraft/download_mods_curseforge.sh            # downloads into ./mods
./minecraft/download_mods_curseforge.sh /tmp/mods  # custom output dir
```

For each mod in `MOD_LIST` it searches CurseForge, matches the
Minecraft version (26.2) + Fabric loader, downloads the first compatible file,
and logs unmatched mods to `skipped_mods.log` (non-fatal). Search term
overrides live in `SEARCH_OVERRIDES`.

## Prerequisites

- Oracle Cloud account with a compartment to deploy into
- [OCI CLI](https://docs.oracle.com/iaas/Content/API/SDKDocs/cliinstall.htm)
  configured with a `terraform-lab` profile (see `terraform/provider.tf`)
- Terraform >= 1.15 (installed provider: `oracle/oci` 6.37.0)
- Ansible with the `ansible.posix` and `community.general` collections
- SSH key pair (public key goes in `terraform/terraform.tfvars`)
- `curl`, `jq`, and a [CurseForge API key](https://console.curseforge.com/)
  for downloading mods

## Deployment

### 1. Provision infrastructure

```bash
cd terraform
terraform init       # installs oracle/oci provider
terraform plan       # review changes
terraform apply      # creates network + instance, prints the public IP
```

`terraform/terraform.tfvars` is auto-loaded and must contain:

```hcl
compartment_id      = "ocid1.compartment.oc1..xxxxxxxxxxxxxxxx"
availability_domain = "ap-mumbai-1"
ssh_public_key      = "ssh-ed25519 AAAA... your@email"
```

Get the live IP any time with `terraform output minecraft_public_ip`.

### 2. Fetch mods

```bash
export CURSEFORGE_API_KEY="your-key-here"
./minecraft/download_mods_curseforge.sh
```

### 3. (First run only) Seed the world

Place the world in `minecraft/world/` (e.g. `level.dat` present). This is
rsynced to the server only when `/opt/minecraft/world/level.dat` is missing,
so subsequent deploys won't clobber the live world.

### 4. Configure the server

```bash
set -a && source .env && set +a   # exports MINECRAFT_HOST from local .env
ansible-playbook -i ansible/inventory.ini ansible/playbook.yml
```

Verify: `docker exec minecraft mc-send-to-console list` (or check `docker ps`)
on the server, and join at `<public-ip>:25565`.

## Tuning

| What | Where | Notes |
| --- | --- | --- |
| Instance shape / size | `terraform/terraform.tfvars` → `instance_shape`, `ocpus`, `memory_in_gbs` | Defaults in `variables.tf` |
| Minecraft version | `minecraft/compose.yaml` → `VERSION` | Keep in sync with `GAME_VERSION` in the download script |
| Memory / heap | `minecraft/compose.yaml` → `MEMORY` | 10G heap on the 12 GB instance — see Security notes |
| Online mode / whitelist | `minecraft/compose.yaml` → `ONLINE_MODE`, `WHITELIST` | |
| Open ports | `terraform/main.tf` security list + UFW tasks in the playbook | |

## Known gaps

These are intentional or unfinished — no code changes are made for them here:

- **Missing `monitoring/` directory.** The Ansible playbook deploys a monitoring
  stack (`monitoring/compose.yaml` + `monitoring/prometheus.yml`) to
  `/opt/monitoring` and starts it (`playbook.yml:177`). That directory does not
  exist yet, so the playbook will fail at the "Copy monitoring Compose file"
  task until it's added (or those tasks are removed).
- **"Modrinth script" is not in the repo.** The CurseForge downloader says it
  mirrors a Modrinth-based script, but no such script is tracked.
- **Unused variable.** `terraform/variables.tf` declares `availability_domain`,
  but the instance uses the `oci_identity_availability_domains` data source
  instead.
- **Gitignored runtime data.** `minecraft/world/`, `minecraft/mods/`,
  `terraform/terraform.tfvars`, and all `*.tfstate*` files are local-only by
  design (see `.gitignore`).

## Security & operational notes

- **SSH (22/TCP) is open to `0.0.0.0/0`.** Restrict the source CIDR in the
  Terraform security list to your IP if the server isn't intended to be
  publicly manageable.
- **`ONLINE_MODE: FALSE` + `WHITELIST: FALSE`** mean anyone can connect with any
  username and no authentication. Enable `ONLINE_MODE` and a whitelist for — or
  add authentication — before exposing the server publicly.
- **Memory headroom.** `MEMORY: 10G` heap on a 12 GB instance leaves ~2 GB for
  the OS, JVM overhead, and the container runtime — tight; expect swap or OOM
  pressure under heavy load. Consider a larger memory budget or a lower heap.
- **Provider profile is hardcoded** (`terraform-lab`) in `terraform/provider.tf`.
- `terraform.tfvars` and the state file contain live infrastructure details —
  keep them out of version control (already gitignored).