variable "project" {
  type    = string
  default = "minecraft-server-ism"
}

variable "compartment_id" {
  description = "OCI compartment used by the Minecraft project"
  type        = string
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
  default     = 2
}

variable "memory_in_gbs" {
  description = "Amount of memory in GB"
  type        = number
  default     = 12
}

variable "ssh_public_key" {
  description = "SSH public key for the Minecraft server"
  type        = string
  sensitive   = true
}
