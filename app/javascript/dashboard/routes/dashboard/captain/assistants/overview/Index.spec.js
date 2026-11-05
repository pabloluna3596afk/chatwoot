import { shallowMount } from '@vue/test-utils';
import { beforeEach, describe, expect, it, vi } from 'vitest';
import Index from './Index.vue';

const mocks = vi.hoisted(() => ({
  isAdmin: true,
  overviewV2: false,
}));

vi.mock('vue-i18n', async importOriginal => ({
  ...(await importOriginal()),
  useI18n: () => ({ t: key => key }),
}));

vi.mock('vue-router', async importOriginal => ({
  ...(await importOriginal()),
  useRoute: () => ({ params: { assistantId: '1' } }),
}));

vi.mock('dashboard/composables/usePolicy', () => ({
  usePolicy: () => ({ checkPermissions: () => mocks.isAdmin }),
}));

vi.mock('dashboard/api/captain/assistant', () => ({
  default: {
    getMetrics: vi.fn().mockResolvedValue({ data: {} }),
    getFaqStats: vi.fn().mockResolvedValue({ data: {} }),
  },
}));

vi.mock('shared/helpers/localStorage', () => ({
  LocalStorage: { get: () => mocks.overviewV2 },
}));

const mountOverview = () =>
  shallowMount(Index, {
    global: {
      mocks: { $t: key => key },
      stubs: {
        PageLayout: { template: '<div><slot name="body" /></div>' },
      },
    },
  });

describe('Captain overview', () => {
  beforeEach(() => {
    mocks.isAdmin = true;
    mocks.overviewV2 = false;
  });

  it('shows the usage breakdown on the default overview for admins', () => {
    const wrapper = mountOverview();

    expect(wrapper.findComponent({ name: 'UsageBreakdownCard' }).exists()).toBe(
      true
    );
  });

  it('hides the usage breakdown from non-admins', () => {
    mocks.isAdmin = false;
    const wrapper = mountOverview();

    expect(wrapper.findComponent({ name: 'UsageBreakdownCard' }).exists()).toBe(
      false
    );
  });
});
