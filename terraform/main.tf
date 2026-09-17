# Network
resource "oci_core_vcn" "vcn" {
  compartment_id = var.compartment_id
  display_name   = "${var.project}-vcn"
  cidr_block    = "10.0.0.0/16"
}

resource "oci_core_subnet" "public-subnet" {
  compartment_id = var.compartment_id
  vcn_id         = oci_core_vcn.vcn.id
  display_name   = "${var.project}-public-subnet"
  cidr_block    = "10.0.0.0/24"
  internet_gateway_id = oci_core_internet_gateway.internet-gateway.id
}

resource "oci_core_internet_gateway" "internet-gateway" {
  compartment_id = var.compartment_id
  vcn_id         = oci_core_vcn.vcn.id
  display_name   = "${var.project}-internet-gateway"
}

resource "oci_core_route_table" "route-table" {
  compartment_id = var.compartment_id
  vcn_id         = oci_core_vcn.vcn.id
  display_name   = "${var.project}-route-table"
  route_rules {
    destination_type = "CIDR_BLOCK"
    destination      = "0.0.0.0/0"
    network_entity_id = oci_core_internet_gateway.internet-gateway.id
  }
}

resource "oci_core_subnet" "private-subnet" {
  compartment_id = var.compartment_id
  vcn_id         = oci_core_vcn.vcn.id
  display_name   = "${var.project}-private-subnet"
  cidr_block    = "10.0.1.0/24"
  route_table_id = oci_core_route_table.route-table.id
}

resource "oci_core_security_list" "security-list" {
  compartment_id = var.compartment_id
  vcn_id         = oci_core_vcn.vcn.id
  display_name   = "${var.project}-security-list"
  ingress_security_rules {
    protocol        = "tcp"
    port            = 22
    source_type     = "CIDR_BLOCK"
    source          = "0.0.0.0/0"
  }

  ingress_security_rules {
    protocol        = "tcp"
    port            = 25565
    source_type     = "CIDR_BLOCK"
    source          = "0.0.0.0/0"
  }
  
  egress_security_rules {
    protocol        = "tcp"
    port            = 22
    source_type     = "CIDR_BLOCK"
    source          = "0.0.0.0/0"
  }

  egress_security_rules {
    protocol        = "tcp"
    port            = 25565
    source_type     = "CIDR_BLOCK"
    source          = "0.0.0.0/0"
  }
}
