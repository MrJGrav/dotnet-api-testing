param appName string
param appConfig object
param appConfigCurrent object

resource app 'Microsoft.Web/sites@2023-01-01' existing = {
  name: appName
}

// var appConfigCurrent = list('${app.id}/sites/config', '2021-02-01').properties

resource appSettings 'Microsoft.Web/sites/config@2023-01-01' = {
  name: 'appsettings'
  parent: app
  properties: union(appConfigCurrent, appConfig)