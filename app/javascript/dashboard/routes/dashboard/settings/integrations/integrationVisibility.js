export const isIntegrationVisible = integration =>
  integration.id !== 'dialogflow' || Boolean(integration.hooks?.length);
