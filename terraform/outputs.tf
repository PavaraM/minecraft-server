output "compartment_name" {
  description = "Name of the Minecraft project compartment"
  value       = data.oci_identity_compartment.project.name
}

output "minecraft_instance_id" {
  description = "Minecraft server instance OCID"
  value       = oci_core_instance.minecraft.id
}

output "minecraft_public_ip" {
  description = "Minecraft server public IP"
  value       = oci_core_instance.minecraft.public_ip
}
