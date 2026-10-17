import { validateAuthenticateRoutePermission } from 'dashboard/routes';
import store from 'dashboard/store';

vi.mock('dashboard/store', () => ({
  default: { getters: {}, dispatch: vi.fn() },
}));
vi.mock('dashboard/routes/dashboard/dashboard.routes', () => ({
  default: { routes: [] },
}));

describe('Assistant onboarding route guard', () => {
  let next;
  let membership;
  beforeEach(() => {
    next = vi.fn();
    membership = {
      id: 1,
      role: 'administrator',
      permissions: ['administrator'],
      status: 'active',
      onboarding_version: 2,
      onboarding_step: 'assistant',
    };
    store.getters.isLoggedIn = true;
    store.getters.getCurrentUser = { account_id: 1, accounts: [membership] };
  });

  it('resumes step 4 from the dashboard', async () => {
    await validateAuthenticateRoutePermission(
      { name: 'home', params: { accountId: 1 } },
      next
    );
    expect(next).toHaveBeenCalledWith('/app/accounts/1/onboarding/assistant');
  });

  it.each(['onboarding_assistant', 'onboarding_inbox_setup'])(
    'allows %s while the cursor stays at assistant',
    async name => {
      await validateAuthenticateRoutePermission(
        {
          name,
          params: { accountId: 1 },
          meta: { permissions: ['administrator'] },
        },
        next
      );
      expect(next).toHaveBeenCalledWith();
    }
  );

  it('does not enroll a legacy account in step 4', async () => {
    delete membership.onboarding_version;
    await validateAuthenticateRoutePermission(
      { name: 'onboarding_assistant', params: { accountId: 1 } },
      next
    );
    expect(next).toHaveBeenCalledWith('/app/accounts/1/dashboard');
  });

  it('keeps a completed account out of the wizard', async () => {
    delete membership.onboarding_step;
    await validateAuthenticateRoutePermission(
      { name: 'onboarding_assistant', params: { accountId: 1 } },
      next
    );
    expect(next).toHaveBeenCalledWith('/app/accounts/1/dashboard');
  });
});
