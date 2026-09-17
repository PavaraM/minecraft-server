variable "project" {
  type    = string
  default = "minecraft-server-ism"
}

variable "region" {
  description = "OCI region"
  type        = string
  default     = "ap-mumbai-1"
}

variable "compartment_id" {
  description = "OCI compartment used by the Minecraft project"
  type        = string
}

variable "tenancy_ocid" {
  description = "OCI tenancy OCID"
  type        = string
  sensitive   = true
}

variable "user_ocid" {
  description = "OCI user OCID"
  type        = string
  sensitive   = true
}

variable "fingerprint" {
  description = "OCI API key fingerprint"
  type        = string
  sensitive   = true
}

variable "private_key_path" {
  description = "Path to Terraform OCI API private key"
  type        = string
  sensitive   = true
}

variable "availability_domain" {
  description = "OCI availability domain"
  type        = string
}

variable "instance_shape" {
  description = "OCI compute shape"
  type        = string
  default     = "VM.Standard.A1.Flex"
}

variable "ocpus" {
  description = "Number of OCPUs"
  type        = number
  default     = 4
}

variable "memory_in_gbs" {
  description = "Amount of memory in GB"
  type        = number
  default     = 24
}

variable "ssh_public_key" {
  description = "SSH public key for the Minecraft server"
  type        = string
  sensitive   = true
}
