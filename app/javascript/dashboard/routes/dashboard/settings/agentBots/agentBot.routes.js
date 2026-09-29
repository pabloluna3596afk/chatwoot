import { FEATURE_FLAGS } from '../../../../featureFlags';
import Bot from './Index.vue';
import { frontendURL } from '../../../../helper/URLHelper';
import SettingsWrapper from '../SettingsWrapper.vue';
import store from 'dashboard/store';

export default {
  routes: [
    {
      path: frontendURL('accounts/:accountId/settings/agent-bots'),
      meta: {
        permissions: ['administrator'],
      },
      component: SettingsWrapper,
      children: [
        {
          path: '',
          name: 'agent_bots',
          component: Bot,
          meta: {
            featureFlag: FEATURE_FLAGS.AGENT_BOTS,
            permissions: ['administrator'],
          },
          // The sidebar already hides this link when the account's
          // agent_bots feature is off (see usePolicy#shouldShow) — this
          // guard closes the gap for a bookmarked/typed URL, since
          // meta.featureFlag by itself is only honored by the sidebar,
          // never enforced by the router (routeHelpers#routeIsAccessibleFor
          // only checks meta.permissions).
          beforeEnter: (to, from, next) => {
            const { accountId } = to.params;
            const isEnabled = store.getters[
              'accounts/isFeatureEnabledonAccount'
            ](accountId, FEATURE_FLAGS.AGENT_BOTS);
            if (!isEnabled) {
              next(frontendURL(`accounts/${accountId}/dashboard`));
            } else {
              next();
            }
          },
        },
      ],
    },
  ],
};
