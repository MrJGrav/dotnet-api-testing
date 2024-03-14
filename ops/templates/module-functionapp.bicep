// Template for deployment of a standard Azure function with .Net8 on Function runtime 4.
// Parameters
@description('Location for all resources ')
param location string 
@description('The environment the resources are being deployed to.')
@allowed([
  'DEV'
  'UAT'
  'SIT'
  'PROD'
])
param env string 

@description('The name of the function app that you wish to create.')
param appName string 

@description('The descriptor for the storage account name that you wish to create.')
@maxLength(15)
param shortappName string 
param appServicePlanId string
param appServiceSubnetId string
param functionAppDNSZoneId string
param logAnalyticsId string
param appInsightsInstrumentationKey string
param allowedIPAddresses array
param privateEndpointSubnetId string
param allowedSubnets array
param kvName string
param dnsServer string


// Variables 
var functionRuntime = 'dotnet-isolated'
var functionVersion = '~4'
var netFrameworkVersion = 'v8.0'

var storageAccountName = toLower('ctgsa${shortappName}${env}' )
var functionAppName = toLower('ctg-azf-${appName}-adapter-${env}')
var privateEndpointName = replace(functionAppName, 'ctg-azf', 'ctg-pe-azf')
var privateLinkConnectionName = 'privateLink${uniqueString(resourceGroup().name)}'
var blobContainers = ['azure-webjobs-hosts', 'azure-webjobs-secrets']



var keyVaultSecretsUserRole = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '4633458b-17de-408a-b874-0445c86b69e6')

var ipAddresses  = [for ip in allowedIPAddresses : {
      action: 'Allow' 
      ipAddress: ip.ipAddress
      name: ip.name
      description: ip.description
      priority: ip.priority
  }]
var networkAddresses = [ for subnet in allowedSubnets: {
      action: 'Allow' 
      vnetSubnetResourceId: subnet.vnetSubnetResourceId
      name: subnet.name
      description: subnet.description
      priority: subnet.priority
}]


var iprestrictions =  union(ipAddresses, networkAddresses) 

@allowed([
  'Production'
  'NonProduction'
])
param environmentType string = toLower(env) == 'prod' ? 'Production' : 'NonProduction'

// Define configuration map 
var environmentConfigurationMap = {
  Production: {    
    storageAccount: {
      sku: {
        name: 'Standard_ZRS'
      }
    }
  }
  NonProduction: {    
    storageAccount: {
      sku: {
        name: 'Standard_LRS'
      }
    }
  }

}

resource keyVault 'Microsoft.KeyVault/vaults@2022-07-01' existing = {
  name: kvName
}

//Resources
resource storageAccount 'Microsoft.Storage/storageAccounts@2023-01-01' = {
  name: storageAccountName
  location: location
  
  sku: {
    name: environmentConfigurationMap[environmentType].storageAccount.sku.name
  }
  kind: 'StorageV2'
  
  properties: {
    allowBlobPublicAccess: false
    minimumTlsVersion: 'TLS1_2'
    networkAcls: {
      defaultAction: 'Deny'
      virtualNetworkRules: [
        {
          action: 'Allow'
          id: appServiceSubnetId
        }
      ]
    }
  }
}

resource blobService 'Microsoft.Storage/storageAccounts/blobServices@2023-01-01' = {
  name: 'default'
  parent: storageAccount
  properties: {
    cors: {
      corsRules: []
    }
  }
}

resource stdblobContainers 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-01-01' = [for container in blobContainers : {
  name: container
  parent: blobService
  properties: {
    publicAccess: 'None'
  }
}]

resource function 'Microsoft.Web/sites@2023-01-01' = {
  name: functionAppName
  location: location
  kind: 'functionapp,linux'
  identity: {
    type: 'SystemAssigned'
  }
  
  properties: {
    serverFarmId: appServicePlanId
    httpsOnly: true
    clientAffinityEnabled: false
    reserved: true
   
    siteConfig: {
      netFrameworkVersion: netFrameworkVersion
      alwaysOn: true
      linuxFxVersion: 'DOTNET-ISOLATED|8.0'
      ftpsState: 'Disabled'
      minTlsVersion: '1.2'
      scmMinTlsVersion: '1.2'
      http20Enabled: true
      use32BitWorkerProcess: false
      vnetRouteAllEnabled: true  
      publicNetworkAccess:  'Enabled' 
      ipSecurityRestrictions: iprestrictions
      scmIpSecurityRestrictionsUseMain: true 
      appSettings: [
          {
            name: 'APPINSIGHTS_INSTRUMENTATIONKEY'
            value: appInsightsInstrumentationKey
          }
          {
            name: 'APPLICATIONINSIGHTS_CONNECTION_STRING'
            value: 'InstrumentationKey=${appInsightsInstrumentationKey}'
          }
          {
            name: 'AzureWebJobsStorage'
            value: 'DefaultEndpointsProtocol=https;AccountName=${storageAccount.name};AccountKey=${storageAccount.listKeys().keys[0].value};EndpointSuffix=core.windows.net'
          }
          {
            name: 'FUNCTIONS_EXTENSION_VERSION'
            value: functionVersion
          }
          {
            name: 'FUNCTIONS_WORKER_RUNTIME'
            value: functionRuntime
          } 
          {
            name: 'WEBSITE_DNS_SERVER'
            value: dnsServer
          }
          {
            name: 'WEBSITE_CONTENTOVERVNET'
            value: '1'
          }
                        
                         
        ]
      }      
      virtualNetworkSubnetId: appServiceSubnetId
     }
     dependsOn: [ blobService, stdblobContainers]
   }

 
resource kvFunctionAppPermissions 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(kvName, function.name, keyVaultSecretsUserRole)
  scope: keyVault
  properties: {
  principalId: function.identity.principalId
  principalType: 'ServicePrincipal'
  roleDefinitionId: keyVaultSecretsUserRole
  }
}


resource functionDiags 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: '${function.name}-logs'
  scope:function
  properties: {
    logAnalyticsDestinationType: 'AzureDiagnostics' 
    metrics: [
      {
        category: 'AllMetrics'
        enabled: true
      }
    ]
    logs: [ 
      {
        category: 'FunctionAppLogs'
        enabled: true
      } ]
  workspaceId: logAnalyticsId
   }
  }



  resource functionAppPrivateEndpoint 'Microsoft.Network/privateEndpoints@2023-09-01' =  {
    name: privateEndpointName
    location: location
    properties: {
      subnet: {
        id: privateEndpointSubnetId
      }
      privateLinkServiceConnections: [
        {
          name: privateLinkConnectionName
          properties: {
            privateLinkServiceId: function.id
            groupIds: [
              'sites'
            ]
          }
        }
      ]
    }
  }
  
   
  resource functionAppPrivateEndpointDnsZoneGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2023-09-01' =  {
    parent: functionAppPrivateEndpoint
    name: 'default'
    properties: {
      privateDnsZoneConfigs: [
        {
          name: 'privateLinkfunctionApp${uniqueString(resourceGroup().name)}'
          properties: {
            privateDnsZoneId: functionAppDNSZoneId
          }
        }
      ]
    }
  }


  // resource storageBlobPrivateEndpoint 'Microsoft.Network/privateEndpoints@2020-06-01' =  {
  //   name: saBlobPrivateEndpointName
  //   location: location
  //   properties: {
  //     subnet: {
  //       id: privateEndpointSubnetId
  //     }
  //     privateLinkServiceConnections: [
  //       {
  //         name: saBlobPrivateLinkConnectionName
  //         properties: {
  //           privateLinkServiceId: storageAccount.id
  //           groupIds: [
  //             'blob'
  //           ]
  //         }
  //       }
  //     ]
  //   }
  // }
  
   
  // resource storageBlobPrivateEndpointDnsZoneGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2020-11-01' =  {
  //   parent: storageBlobPrivateEndpoint
  //   name: 'default'
  //   properties: {
  //     privateDnsZoneConfigs: [
  //       {
  //         name: 'privateLinksablob${uniqueString(resourceGroup().name)}'
  //         properties: {
  //           privateDnsZoneId: saBlobDNSZoneId
  //         }
  //       }
  //     ]
  //   }
  // }


  resource appSettingsCurrent 'Microsoft.Web/sites/config@2022-09-01' existing = {
    name: 'appsettings'
    parent: function
  }

// output managedIdentityId string= function.identity.principalId
output functionAppManagedIdentity string = function.identity.principalId
output functionAppName string = function.name
output functionAppId string = function.id
output appSettings object = appSettingsCurrent.list().properties