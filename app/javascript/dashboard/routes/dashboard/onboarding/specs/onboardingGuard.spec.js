import { validateAuthenticateRoutePermission } from 'dashboard/routes';
import store from 'dashboard/store';

vi.mock('dashboard/routes/dashboard/dashboard.routes', () => ({
  default: { routes: [] },
}));
vi.mock('dashboard/store', () => ({
  default: {
    getters: { isLoggedIn: true, getCurrentUser: {} },
    dispatch: vi.fn(),
  },
}));
vi.mock('dashboard/helper/AnalyticsHelper', () => ({
  default: { page: vi.fn() },
}));

describe('Onboarding route guard', () => {
  let next;
  let membership;

  beforeEach(() => {
    next = vi.fn();
    membership = {
      id: 1,
      role: 'administrator',
      permissions: ['administrator'],
      status: 'active',
      onboarding_step: 'inbox_setup',
    };
    store.getters.getCurrentUser = {
      id: 1,
      account_id: 1,
      accounts: [membership],
    };
  });

  it.each(['home', 'no_accounts', 'onboarding_account_details', undefined])(
    'resumes inbox_setup from %s',
    async name => {
      await validateAuthenticateRoutePermission(
        { name, params: { accountId: 1 } },
        next
      );
      expect(next).toHaveBeenCalledExactlyOnceWith(
        '/app/accounts/1/onboarding/inbox-setup'
      );
    }
  );

  it('allows reload of the stored inbox step', async () => {
    await validateAuthenticateRoutePermission(
      {
        name: 'onboarding_inbox_setup',
        params: { accountId: 1 },
        meta: { permissions: ['administrator'] },
      },
      next
    );
    expect(next).toHaveBeenCalledExactlyOnceWith();
  });

  it('does not allow jumping ahead before account_details', async () => {
    membership.onboarding_step = 'account_details';
    await validateAuthenticateRoutePermission(
      { name: 'onboarding_inbox_setup', params: { accountId: 1 } },
      next
    );
    expect(next).toHaveBeenCalledExactlyOnceWith('/app/accounts/1/onboarding');
  });

  it('returns completed accounts to the dashboard', async () => {
    delete membership.onboarding_step;
    await validateAuthenticateRoutePermission(
      { name: 'onboarding_inbox_setup', params: { accountId: 1 } },
      next
    );
    expect(next).toHaveBeenCalledExactlyOnceWith('/app/accounts/1/dashboard');
  });

  it.each([{ role: 'agent' }, { status: 'suspended' }])(
    'does not force onboarding for ineligible users: %o',
    async changes => {
      Object.assign(membership, changes);
      await validateAuthenticateRoutePermission(
        { name: 'home', params: { accountId: 1 } },
        next
      );
      expect(next).not.toHaveBeenCalledWith(
        '/app/accounts/1/onboarding/inbox-setup'
      );
    }
  );
});
