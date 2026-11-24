import { FEATURE_FLAGS } from 'dashboard/featureFlags';
import { frontendURL } from 'dashboard/helper/URLHelper';
import SettingsWrapper from '../SettingsWrapper.vue';
import Index from './Index.vue';

export default {
  routes: [
    {
      path: frontendURL('accounts/:accountId/settings/citas'),
      component: SettingsWrapper,
      props: { keepAlive: false },
      children: [
        {
          path: '',
          name: 'settings_citas',
          component: Index,
          meta: {
            featureFlag: FEATURE_FLAGS.CALENDAR,
            permissions: ['administrator'],
          },
        },
      ],
    },
  ],
};
