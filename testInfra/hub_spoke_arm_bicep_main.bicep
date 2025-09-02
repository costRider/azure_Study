// Hub & Spoke reference based on your diagram
// - vnet-01 (hub): Bastion + VPN Gateway + Private DNS link
// - vnet-02 (spoke-a): VM test-vm02 (with PIP+NSG)
// - vnet-03 (spoke-b): VM test-vm03 (with PIP+NSG)
// - Peering: vnet-01 <-> vnet-02, vnet-01 <-> vnet-03
// - Traffic Manager: endpoints = PIPs of vm02/vm03 (priority)
// NOTE: This is a clean, re-deployable Bicep (ARM) template. Extend as needed.

@description('Azure region for all regional resources')
param location string = resourceGroup().location

@description('Name prefix applied to most resources')
param namePrefix string = 'test'

// Address spaces
@description('Hub address space')
param hubAddress string = '10.0.0.0/16'
@description('Spoke-A address space')
param spokeAAddress string = '10.1.0.0/16'
@description('Spoke-B address space')
param spokeBAddress string = '10.2.0.0/16'

// Subnets
param hubSubnets object = {
  bastion: '10.0.0.0/26'
  gateway: '10.0.0.64/26'   // must be named GatewaySubnet below
  workloads: '10.0.1.0/24'
}
param spokeASubnet string = '10.1.1.0/24'
param spokeBSubnet string = '10.2.1.0/24'

// VM settings
@description('Windows Admin username')
param adminUsername string
@secure()
@description('Windows Admin password (use Key Vault ref in real runs)')
param adminPassword string

@description('VM size for spokes')
param vmSize string = 'Standard_B2s'

@allowed([ 'Priority' 'Performance' 'Weighted' ])
@description('Traffic Manager routing method')
param tmRouting string = 'Priority'

var vnet01Name = '${namePrefix}-vnet-01'
var vnet02Name = '${namePrefix}-vnet-02'
var vnet03Name = '${namePrefix}-vnet-03'
var bastionPipName = '${namePrefix}-pip-bastion'
var bastionName = '${namePrefix}-bastion'
var vgwPipName = '${namePrefix}-pip-vgw'
var vgwName = '${namePrefix}-vgw'
var tmName = 'traf-${namePrefix}'
var privDnsZoneName = 'privatedns.local'

// ------------------ Hub VNet ------------------
resource vnet01 'Microsoft.Network/virtualNetworks@2023-09-01' = {
  name: vnet01Name
  location: location
  properties: {
    addressSpace: { addressPrefixes: [ hubAddress ] }
  }
}

resource vnet01_workloads 'Microsoft.Network/virtualNetworks/subnets@2023-09-01' = {
  name: '${vnet01.name}/subnet-workloads'
  properties: {
    addressPrefix: hubSubnets.workloads
  }
}

resource vnet01_gw 'Microsoft.Network/virtualNetworks/subnets@2023-09-01' = {
  name: '${vnet01.name}/GatewaySubnet'
  properties: {
    addressPrefix: hubSubnets.gateway
  }
}

resource vnet01_bas 'Microsoft.Network/virtualNetworks/subnets@2023-09-01' = {
  name: '${vnet01.name}/AzureBastionSubnet'
  properties: {
    addressPrefix: hubSubnets.bastion
  }
}

// Bastion
resource bastionPip 'Microsoft.Network/publicIPAddresses@2023-09-01' = {
  name: bastionPipName
  location: location
  sku: { name: 'Standard' }
  properties: {
    publicIPAddressVersion: 'IPv4'
    publicIPAllocationMethod: 'Static'
    dnsSettings: {
      domainNameLabel: '${namePrefix}-bas-${uniqueString(resourceGroup().id)}'
    }
  }
}

resource bastion 'Microsoft.Network/bastionHosts@2023-09-01' = {
  name: bastionName
  location: location
  properties: {
    ipConfigurations: [
      {
        name: 'bastion-ipcfg'
        properties: {
          subnet: { id: vnet01_bas.id }
          publicIPAddress: { id: bastionPip.id }
        }
      }
    ]
  }
}

// VPN Gateway (Route-based)
resource vgwPip 'Microsoft.Network/publicIPAddresses@2023-09-01' = {
  name: vgwPipName
  location: location
  sku: { name: 'Standard' }
  properties: {
    publicIPAddressVersion: 'IPv4'
    publicIPAllocationMethod: 'Static'
  }
}

resource vgw 'Microsoft.Network/virtualNetworkGateways@2023-09-01' = {
  name: vgwName
  location: location
  properties: {
    ipConfigurations: [
      {
        name: 'gw-ipcfg'
        properties: {
          publicIPAddress: { id: vgwPip.id }
          subnet: { id: vnet01_gw.id }
        }
      }
    ]
    sku: { name: 'VpnGw1' tier: 'VpnGw1' }
    gatewayType: 'Vpn'
    vpnType: 'RouteBased'
    enableBgp: false
  }
}

// ------------------ Spoke A (vnet-02) ------------------
resource vnet02 'Microsoft.Network/virtualNetworks@2023-09-01' = {
  name: vnet02Name
  location: location
  properties: {
    addressSpace: { addressPrefixes: [ spokeAAddress ] }
  }
}
resource vnet02_sub 'Microsoft.Network/virtualNetworks/subnets@2023-09-01' = {
  name: '${vnet02.name}/subnet-app'
  properties: { addressPrefix: spokeASubnet }
}
resource nsg02 'Microsoft.Network/networkSecurityGroups@2023-09-01' = {
  name: '${namePrefix}-vm02-nsg'
  location: location
  properties: {
    securityRules: [
      {
        name: 'allow-rdp'
        properties: {
          direction: 'Inbound'
          priority: 3000
          access: 'Allow'
          protocol: 'Tcp'
          sourceAddressPrefix: '*'
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '3389'
        }
      }
      {
        name: 'allow-http'
        properties: {
          direction: 'Inbound'
          priority: 3010
          access: 'Allow'
          protocol: 'Tcp'
          sourceAddressPrefix: '*'
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '80'
        }
      }
    ]
  }
}
resource vnet02_sub_nsg 'Microsoft.Network/virtualNetworks/subnets@2023-09-01' existing = {
  name: '${vnet02.name}/subnet-app'
}
resource vnet02_sub_nsgAssoc 'Microsoft.Network/virtualNetworks/subnets/networkSecurityGroups@2023-09-01' = {
  name: '${vnet02_sub_nsg.name}/nsg'
  properties: { id: nsg02.id }
}
resource pip02 'Microsoft.Network/publicIPAddresses@2023-09-01' = {
  name: '${namePrefix}-pip-vm02'
  location: location
  sku: { name: 'Standard' }
  properties: {
    publicIPAllocationMethod: 'Static'
    dnsSettings: { domainNameLabel: '${namePrefix}-vm02-${uniqueString(resourceGroup().id)}' }
  }
}
resource nic02 'Microsoft.Network/networkInterfaces@2023-09-01' = {
  name: '${namePrefix}-nic-vm02'
  location: location
  properties: {
    ipConfigurations: [
      {
        name: 'ipcfg1'
        properties: {
          privateIPAllocationMethod: 'Dynamic'
          subnet: { id: vnet02_sub.id }
          publicIPAddress: { id: pip02.id }
        }
      }
    ]
    networkSecurityGroup: { id: nsg02.id }
  }
}
resource vm02 'Microsoft.Compute/virtualMachines@2023-09-01' = {
  name: '${namePrefix}-vm02'
  location: location
  properties: {
    hardwareProfile: { vmSize: vmSize }
    osProfile: {
      computerName: '${namePrefix}-vm02'
      adminUsername: adminUsername
      adminPassword: adminPassword
      windowsConfiguration: { provisionVMAgent: true }
    }
    storageProfile: {
      imageReference: { publisher: 'MicrosoftWindowsServer' offer: 'WindowsServer' sku: '2022-datacenter' version: 'latest' }
      osDisk: {
        createOption: 'FromImage'
        caching: 'ReadWrite'
        managedDisk: { storageAccountType: 'Premium_LRS' }
        diskSizeGB: 127
      }
    }
    networkProfile: { networkInterfaces: [ { id: nic02.id } ] }
  }
}

// ------------------ Spoke B (vnet-03) ------------------
resource vnet03 'Microsoft.Network/virtualNetworks@2023-09-01' = {
  name: vnet03Name
  location: location
  properties: { addressSpace: { addressPrefixes: [ spokeBAddress ] } }
}
resource vnet03_sub 'Microsoft.Network/virtualNetworks/subnets@2023-09-01' = {
  name: '${vnet03.name}/subnet-app'
  properties: { addressPrefix: spokeBSubnet }
}
resource nsg03 'Microsoft.Network/networkSecurityGroups@2023-09-01' = {
  name: '${namePrefix}-vm03-nsg'
  location: location
}
resource pip03 'Microsoft.Network/publicIPAddresses@2023-09-01' = {
  name: '${namePrefix}-pip-vm03'
  location: location
  sku: { name: 'Standard' }
  properties: {
    publicIPAllocationMethod: 'Static'
    dnsSettings: { domainNameLabel: '${namePrefix}-vm03-${uniqueString(resourceGroup().id)}' }
  }
}
resource nic03 'Microsoft.Network/networkInterfaces@2023-09-01' = {
  name: '${namePrefix}-nic-vm03'
  location: location
  properties: {
    ipConfigurations: [ {
      name: 'ipcfg1'
      properties: {
        privateIPAllocationMethod: 'Dynamic'
        subnet: { id: vnet03_sub.id }
        publicIPAddress: { id: pip03.id }
      }
    } ]
    networkSecurityGroup: { id: nsg03.id }
  }
}
resource vm03 'Microsoft.Compute/virtualMachines@2023-09-01' = {
  name: '${namePrefix}-vm03'
  location: location
  properties: {
    hardwareProfile: { vmSize: vmSize }
    osProfile: {
      computerName: '${namePrefix}-vm03'
      adminUsername: adminUsername
      adminPassword: adminPassword
      windowsConfiguration: { provisionVMAgent: true }
    }
    storageProfile: {
      imageReference: { publisher: 'MicrosoftWindowsServer' offer: 'WindowsServer' sku: '2022-datacenter' version: 'latest' }
      osDisk: {
        createOption: 'FromImage'
        caching: 'ReadWrite'
        managedDisk: { storageAccountType: 'Premium_LRS' }
        diskSizeGB: 127
      }
    }
    networkProfile: { networkInterfaces: [ { id: nic03.id } ] }
  }
}

// ------------------ Peering ------------------
resource peer01to02 'Microsoft.Network/virtualNetworks/virtualNetworkPeerings@2023-09-01' = {
  name: '${vnet01.name}/peer-to-${vnet02.name}'
  properties: {
    allowVirtualNetworkAccess: true
    allowForwardedTraffic: true
    remoteVirtualNetwork: { id: vnet02.id }
  }
}
resource peer02to01 'Microsoft.Network/virtualNetworks/virtualNetworkPeerings@2023-09-01' = {
  name: '${vnet02.name}/peer-to-${vnet01.name}'
  properties: {
    allowVirtualNetworkAccess: true
    allowForwardedTraffic: true
    remoteVirtualNetwork: { id: vnet01.id }
  }
}
resource peer01to03 'Microsoft.Network/virtualNetworks/virtualNetworkPeerings@2023-09-01' = {
  name: '${vnet01.name}/peer-to-${vnet03.name}'
  properties: {
    allowVirtualNetworkAccess: true
    allowForwardedTraffic: true
    remoteVirtualNetwork: { id: vnet03.id }
  }
}
resource peer03to01 'Microsoft.Network/virtualNetworks/virtualNetworkPeerings@2023-09-01' = {
  name: '${vnet03.name}/peer-to-${vnet01.name}'
  properties: {
    allowVirtualNetworkAccess: true
    allowForwardedTraffic: true
    remoteVirtualNetwork: { id: vnet01.id }
  }
}

// ------------------ Private DNS Zone ------------------
resource pdns 'Microsoft.Network/privateDnsZones@2020-06-01' = {
  name: privDnsZoneName
  location: 'global'
}
resource pdnsLinkHub 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = {
  name: '${pdns.name}/${namePrefix}-hub-link'
  properties: {
    registrationEnabled: false
    virtualNetwork: { id: vnet01.id }
  }
}

// ------------------ Traffic Manager ------------------
resource tm 'Microsoft.Network/trafficManagerProfiles@2022-04-01' = {
  name: tmName
  location: 'global'
  properties: {
    profileStatus: 'Enabled'
    trafficRoutingMethod: tmRouting
    dnsConfig: {
      relativeName: 'tm-${namePrefix}-${uniqueString(resourceGroup().id)}'
      ttl: 30
    }
    monitorConfig: {
      protocol: 'HTTP'
      port: 80
      path: '/'
    }
    endpoints: [
      {
        name: 'vm02-endpoint'
        type: 'Microsoft.Network/trafficManagerProfiles/azureEndpoints'
        properties: {
          endpointStatus: 'Enabled'
          priority: 1
          targetResourceId: pip02.id
          weight: 1
        }
      }
      {
        name: 'vm03-endpoint'
        type: 'Microsoft.Network/trafficManagerProfiles/azureEndpoints'
        properties: {
          endpointStatus: 'Enabled'
          priority: 2
          targetResourceId: pip03.id
          weight: 1
        }
      }
    ]
  }
}

// ------------------ Outputs ------------------
output bastionUrl string = 'https://portal.azure.com/#resource${bastion.id}/connect'
output tmFqdn string = reference(tm.id).dnsConfig.fqdn
output vm02PublicFqdn string = reference(pip02.id).dnsSettings.fqdn
output vm03PublicFqdn string = reference(pip03.id).dnsSettings.fqdn
