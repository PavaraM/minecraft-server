# network
resource "oci_core_vcn" "minecraft" {
  compartment_id = var.compartment_id

  display_name = "minecraft-vcn"
  cidr_blocks  = ["10.0.0.0/16"]

  dns_label = "minecraft"
}

resource "oci_core_internet_gateway" "minecraft" {
  compartment_id = var.compartment_id
  vcn_id         = oci_core_vcn.minecraft.id

  display_name = "minecraft-internet-gateway"
  enabled      = true
}

resource "oci_core_route_table" "minecraft" {
  compartment_id = var.compartment_id
  vcn_id         = oci_core_vcn.minecraft.id

  display_name = "minecraft-route-table"

  route_rules {
    destination       = "0.0.0.0/0"
    destination_type  = "CIDR_BLOCK"
    network_entity_id = oci_core_internet_gateway.minecraft.id
  }
}

resource "oci_core_security_list" "minecraft" {
  compartment_id = var.compartment_id
  vcn_id         = oci_core_vcn.minecraft.id

  display_name = "minecraft-security-list"

  ingress_security_rules {
    protocol = "6"
    source   = "0.0.0.0/0"

    tcp_options {
      min = 25565
      max = 25565
    }

    description = "Minecraft Java Edition"
  }

  ingress_security_rules {
    protocol = "6"
    source   = "0.0.0.0/0"

    tcp_options {
      min = 22
      max = 22
    }

    description = "SSH"
  }

  egress_security_rules {
    protocol    = "all"
    destination = "0.0.0.0/0"
  }

  ingress_security_rules {
    protocol = "17"

    source = "0.0.0.0/0"

    udp_options {
      min = 24454
      max = 24454
    }

    description = "Simple Voice Chat"
  }
}

resource "oci_core_subnet" "minecraft" {
  compartment_id = var.compartment_id
  vcn_id         = oci_core_vcn.minecraft.id

  display_name = "minecraft-public-subnet"

  cidr_block = "10.0.1.0/24"

  route_table_id = oci_core_route_table.minecraft.id

  security_list_ids = [
    oci_core_security_list.minecraft.id
  ]

  prohibit_public_ip_on_vnic = false

  dns_label = "public"
}

# compute

resource "oci_core_instance" "minecraft" {
  compartment_id      = var.compartment_id
  availability_domain = var.availability_domain

  display_name = "minecraft-server"

  shape = var.instance_shape

  shape_config {
    ocpus         = var.ocpus
    memory_in_gbs = var.memory_in_gbs
  }

  source_details {
    source_type = "image"
    source_id   = data.oci_core_images.ubuntu.images[0].id
  }

  create_vnic_details {
    subnet_id        = oci_core_subnet.minecraft.id
    assign_public_ip = true

    display_name = "minecraft-vnic"
  }

  metadata = {
    ssh_authorized_keys = var.ssh_public_key
  }
}