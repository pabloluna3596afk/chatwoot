import { createRouter, createWebHistory } from 'vue-router';

import { frontendURL } from '../helper/URLHelper';
import dashboard from './dashboard/dashboard.routes';
import store from 'dashboard/store';
import { validateLoggedInRoutes } from '../helper/routeHelpers';
import { isOnOnboardingView } from 'v3/helpers/RouteHelper';
import AnalyticsHelper from '../helper/AnalyticsHelper';

const ONBOARDING_STEPS = ['account_details', 'enrichment', 'inbox_setup'];
const ONBOARDING_ROUTES = {
  inbox_setup: ['onboarding/inbox-setup', 'onboarding_inbox_setup'],
  assistant: ['onboarding/assistant', 'onboarding_assistant'],
};
const routes = [...dashboard.routes];

const onboardingPath = step => ONBOARDING_ROUTES[step]?.[0] || 'onboarding';

export const router = createRouter({ history: createWebHistory(), routes });

export const validateAuthenticateRoutePermission = async (to, next) => {
  const { isLoggedIn, getCurrentUser: user } = store.getters;

  if (!isLoggedIn) {
    window.location.assign('/app/login');
    return '';
  }

  const { accounts = [], account_id: accountId } = user;

  if (!accounts.length) {
    if (to.name === 'no_accounts') {
      return next();
    }
    return next(frontendURL('no-accounts'));
  }

  const routeAccountId = Number(to.params?.accountId || accountId);
  const userAccount = accounts.find(a => a.id === routeAccountId);
  const isAdmin = userAccount?.role === 'administrator';
  const isActive = userAccount?.status === 'active';
  const isAssistantStep =
    userAccount?.onboarding_version === 2 &&
    userAccount?.onboarding_step === 'assistant';
  const needsOnboarding =
    (ONBOARDING_STEPS.includes(userAccount?.onboarding_step) ||
      isAssistantStep) &&
    isAdmin &&
    isActive;

  if (to.name === 'no_accounts' || !to.name) {
    const target = needsOnboarding
      ? onboardingPath(userAccount?.onboarding_step)
      : 'dashboard';
    return next(frontendURL(`accounts/${routeAccountId}/${target}`));
  }

  const expectedOnboardingRoute =
    ONBOARDING_ROUTES[userAccount?.onboarding_step]?.[1] ||
    'onboarding_account_details';
  const returningToWhatsapp =
    isAssistantStep && to.name === 'onboarding_inbox_setup';
  const reviewingBusiness =
    userAccount?.onboarding_version === 2 &&
    ['inbox_setup', 'assistant'].includes(userAccount?.onboarding_step) &&
    to.name === 'onboarding_account_details';
  const viewingPlans = isAssistantStep && to.name === 'billing_settings_index';
  if (
    needsOnboarding &&
    to.name !== expectedOnboardingRoute &&
    !returningToWhatsapp &&
    !reviewingBusiness &&
    !viewingPlans
  ) {
    return next(
      frontendURL(
        `accounts/${routeAccountId}/${onboardingPath(userAccount?.onboarding_step)}`
      )
    );
  }
  if (!needsOnboarding && isOnOnboardingView(to)) {
    return next(frontendURL(`accounts/${routeAccountId}/dashboard`));
  }

  const nextRoute = validateLoggedInRoutes(to, store.getters.getCurrentUser);
  return nextRoute ? next(frontendURL(nextRoute)) : next();
};

export const initalizeRouter = () => {
  const userAuthentication = store.dispatch('setUser');

  router.beforeEach(async (to, _from, next) => {
    AnalyticsHelper.page(to.name || '', {
      path: to.path,
      name: to.name,
    });

    await userAuthentication;
    await validateAuthenticateRoutePermission(to, next, store);
  });
};

export default router;
