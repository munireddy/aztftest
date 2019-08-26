provider "azurerm" {
  # Whilst version is optional, we /strongly recommend/ using it to pin the version of the Provider being used
  version = "=1.28.0"

  subscription_id = "6a47561d-9fe1-414e-85b7-99cd2ce0ce46"
  tenant_id       = "59b2865a-7fb8-4ccb-ab68-72cbca88fc48"
}


resource "azurerm_resource_group" "vmss" {
 name     = "${var.resource_group_name}"
 location = "${var.location}"
 tags     = "${var.tags}"
}

resource "random_string" "fqdn" {
 length  = 6
 special = false
 upper   = false
 number  = false
}

resource "azurerm_virtual_network" "vmss" {
 name                = "vmss-vnet"
 address_space       = ["10.0.0.0/16"]
 location            = "${var.location}"
 resource_group_name = "${azurerm_resource_group.vmss.name}"
 tags                = "${var.tags}"
}

resource "azurerm_subnet" "vmss" {
 name                 = "vmss-subnet"
 resource_group_name  = "${azurerm_resource_group.vmss.name}"
 virtual_network_name = "${azurerm_virtual_network.vmss.name}"
 address_prefix       = "10.0.2.0/24"
}

resource "azurerm_public_ip" "vmss" {
 name                         = "vmss-public-ip"
 location                     = "${var.location}"
 resource_group_name          = "${azurerm_resource_group.vmss.name}"
 allocation_method = "Static"
 domain_name_label            = "${random_string.fqdn.result}"
 tags                         = "${var.tags}"
}

resource "azurerm_lb" "vmss" {
 name                = "vmss-lb"
 location            = "${var.location}"
 resource_group_name = "${azurerm_resource_group.vmss.name}"

 frontend_ip_configuration {
   name                 = "PublicIPAddress"
   public_ip_address_id = "${azurerm_public_ip.vmss.id}"
 }

 tags = "${var.tags}"
}

resource "azurerm_lb_backend_address_pool" "bpepool" {
 resource_group_name = "${azurerm_resource_group.vmss.name}"
 loadbalancer_id     = "${azurerm_lb.vmss.id}"
 name                = "BackEndAddressPool"
}

resource "azurerm_lb_probe" "vmss" {
 resource_group_name = "${azurerm_resource_group.vmss.name}"
 loadbalancer_id     = "${azurerm_lb.vmss.id}"
 name                = "ssh-running-probe"
 port                = "${var.application_port}"
}

resource "azurerm_lb_rule" "lbnatrule" {
   resource_group_name            = "${azurerm_resource_group.vmss.name}"
   loadbalancer_id                = "${azurerm_lb.vmss.id}"
   name                           = "ssh"
   protocol                       = "Tcp"
   frontend_port                  = "${var.application_port}"
   backend_port                   = "${var.application_port}"
   backend_address_pool_id        = "${azurerm_lb_backend_address_pool.bpepool.id}"
   frontend_ip_configuration_name = "PublicIPAddress"
   probe_id                       = "${azurerm_lb_probe.vmss.id}"
}

resource "azurerm_virtual_machine_scale_set" "vmss" {
 name                = "vmscaleset"
 location            = "${var.location}"
 resource_group_name = "${azurerm_resource_group.vmss.name}"
 upgrade_policy_mode = "Manual"

 sku {
   name     = "Standard_DS1_v2"
   tier     = "Standard"
   capacity = 2
 }

 storage_profile_image_reference {
   publisher = "Canonical"
   offer     = "UbuntuServer"
   sku       = "16.04-LTS"
   version   = "latest"
 }

 storage_profile_os_disk {
   name              = ""
   caching           = "ReadWrite"
   create_option     = "FromImage"
   managed_disk_type = "Standard_LRS"
 }

 storage_profile_data_disk {
   lun          = 0
   caching        = "ReadWrite"
   create_option  = "Empty"
   disk_size_gb   = 10
 }

 os_profile {
   computer_name_prefix = "vmlab"
   admin_username       = "${var.admin_user}"
   admin_password       = "${var.admin_password}"
   custom_data    = <<-EOF
      #!/bin/bash
      touch /tmp/file1.txt
      sudo snap install docker
      EOF
 }

 os_profile_linux_config {
   disable_password_authentication = false
 }

 network_profile {
   name    = "terraformnetworkprofile"
   primary = true

   ip_configuration {
     name                                   = "IPConfiguration"
     subnet_id                              = "${azurerm_subnet.vmss.id}"
     load_balancer_backend_address_pool_ids = ["${azurerm_lb_backend_address_pool.bpepool.id}"]
     primary = true
   }
 }

 tags = "${var.tags}"
}