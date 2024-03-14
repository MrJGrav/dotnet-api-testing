/*
az account set --subscription "SUBSCRIPTION"
az deployment  group create -c  --resource-group "rg-ctg-PROJECT-dev" --template-file  "./main.bicep" --parameters "./main-parameters-dev.json"
*/

param location string = resourceGroup().location

param appName string
param devsGroup string
param env string
param date string = utcNow()
param logAnalyticsId string
param allowedIPAddresses array = []
param allowedSubnets array = []
param aspName string
param aspRG string
param vnetIntegrationSubnetName string
param vnetResourceGroupName string
param vNetName string
param privateEndpointSubnetName string
param functionAppDNSZoneId string
param kvName string
param aiName string
@maxLength(15)
param shortAppName string
param dnsServer string
param appSettings object


//Variables


// existing resources

resource asp 'Microsoft.Web/serverfarms@2023-01-01' existing = {
  name: aspName
  scope: resourceGroup(aspRG)
}

resource vNet 'Microsoft.Network/virtualNetworks@2023-09-01' existing = {
  name: vNetName 
  scope: resourceGroup(vnetResourceGroupName)
}

resource aspSubnet 'Microsoft.Network/virtualNetworks/subnets@2023-09-01' existing = {
  name: vnetIntegrationSubnetName
  parent: vNet
}

resource PrivateEndpointSubnet 'Microsoft.Network/virtualNetworks/subnets@2023-09-01' existing = {
  name: privateEndpointSubnetName
  parent: vNet
}

// Modules to create resources

module appInsights 'br/CTGSharedBicepModulesRegistry:applicationinsight:v1.6' =  {
  name: 'deploy-app-insights'
  params: {
    env: toLower(env)
    location: location
    logAnalyticsWorkspaceId: logAnalyticsId
    project: appName
  }
}


module keyVault 'br/CTGSharedBicepModulesRegistry:keyvault:v1.7' = {
  name: 'deploy-amb-keyvault'
  params: {
    appName: appName
    appNameShort: shortAppName
    env: toLower(env)
    location: location
    logAnalyticsWorkspaceId: logAnalyticsId
    privateDnsZoneId: keyVaultDNSZoneId
    privateEndpointSubnetId: PrivateEndpointSubnet.id
  }
}

module functionApp 'module-functionapp.bicep' = {
  name: 'deploy-functionapp-${date}'
  params: {
    allowedIPAddresses: []
    allowedSubnets: []
    appInsightsInstrumentationKey: appInsights.properties.InstrumentationKey
    appName: appName
    appServicePlanId: asp.id
    appServiceSubnetId: aspSubnet.id
    dnsServer: dnsServer
    env: env
    functionAppDNSZoneId: functionAppDNSZoneId
    kvName: keyVault.name
    location: location
    logAnalyticsId: logAnalyticsId
    privateEndpointSubnetId: PrivateEndpointSubnet.id
    shortappName: shortAppName
  }
}


module functionAppSettings 'module-appsettings.bicep' = {
  name: 'deploy-appsettings-${date}'
  params: {
    appConfig: appSettings
    appName: functionApp.outputs.functionAppName
    appConfigCurrent:functionApp.outputs.appSettings
  }
  dependsOn: [
    functionApp
  ]
}


