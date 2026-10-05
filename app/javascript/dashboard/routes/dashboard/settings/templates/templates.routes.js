import { frontendURL } from '../../../../helper/URLHelper';

import SettingsWrapper from '../SettingsWrapper.vue';
import Index from './Index.vue';
import FlowPage from './flows/FlowPage.vue';

const flowRoute = (path, name) => ({
  path: frontendURL(`accounts/:accountId/settings/templates/flows/${path}`),
  name,
  component: FlowPage,
  meta: {
    permissions: ['administrator'],
  },
});

export default {
  routes: [
    {
      path: frontendURL('accounts/:accountId/settings/templates'),
      component: SettingsWrapper,
      children: [
        {
          path: '',
          name: 'settings_templates',
          component: Index,
          meta: {
            permissions: ['administrator'],
          },
        },
      ],
    },
    // The flow builder is a full page (wider than the settings column), so it is not inside SettingsWrapper.
    flowRoute('new', 'settings_flow_new'),
    flowRoute('draft', 'settings_flow_draft'),
    flowRoute(':flowId', 'settings_flow_edit'),
  ],
};
