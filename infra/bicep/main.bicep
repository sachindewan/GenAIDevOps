// Minimal Azure Bicep template for a Log Analytics Workspace
// Parameters
param location string = resourceGroup().location
@allowed([
  'dev'
  'test'
  'prod'
])
param environmentName string

@description('The container image name (e.g. myapp)')
param containerImageName string = 'myapp'

@description('The container image tag (e.g. latest)')
param containerImageTag string = 'latest'

// Tags
var basicTags = {
  environment: environmentName
  createdBy: 'bicep-template'
}

// Log Analytics Workspace
resource logAnalytics 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: 'log-${environmentName}-${uniqueString(resourceGroup().id)}'
  location: location
  tags: basicTags
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: 30
  }
}

// Azure Container Apps Environment
// This environment is required to host container apps. It is connected to the Log Analytics Workspace for monitoring.
resource containerAppsEnv 'Microsoft.App/managedEnvironments@2023-05-01' = {
  name: 'cae-${environmentName}-${substring(uniqueString(resourceGroup().id, deployment().name), 0, 8)}'
  location: location
  tags: basicTags
  properties: {
    appLogsConfiguration: {
      destination: 'log-analytics'
      logAnalyticsConfiguration: {
        customerId: logAnalytics.properties.customerId
        sharedKey: logAnalytics.listKeys().primarySharedKey
      }
    }
  }
}

// Azure Container Registry
resource acr 'Microsoft.ContainerRegistry/registries@2023-01-01-preview' = {
  name: 'acr${environmentName}${uniqueString(resourceGroup().id)}'
  location: location
  tags: basicTags
  sku: {
    name: 'Basic'
  }
  properties: {
    adminUserEnabled: false
  }
}

// Container App
resource containerApp 'Microsoft.App/containerApps@2023-05-01' = {
  name: 'app-${environmentName}-${uniqueString(resourceGroup().id)}'
  location: location
  tags: basicTags
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    managedEnvironmentId: containerAppsEnv.id
    configuration: {
      ingress: {
        external: true
        targetPort: 80
        transport: 'auto'
      }
    }
    template: {
      containers: [
        {
          name: 'main'
          image: 'mcr.microsoft.com/azuredocs/containerapps-helloworld:latest'
          resources: {
            cpu: json('0.25')
            memory: '0.5Gi'
          }
        }
      ]
    }
  }
}

// Assign AcrPull role to the Container App's system-assigned managed identity
resource acrPullRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(acr.id, containerApp.name, 'AcrPull', environmentName)
  scope: acr
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '7f951dda-4ed3-4680-a7ca-43fe172d538d')
    principalId: containerApp.identity.principalId
    principalType: 'ServicePrincipal'
  }
}
