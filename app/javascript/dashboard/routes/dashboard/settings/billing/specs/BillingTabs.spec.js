import { flushPromises, mount } from '@vue/test-utils';
import { createMemoryHistory, createRouter } from 'vue-router';
import BillingTabs from '../components/BillingTabs.vue';

const mountTabs = async initialPath => {
  const router = createRouter({
    history: createMemoryHistory(),
    routes: [{ path: '/billing', component: { template: '<div />' } }],
  });
  await router.push(initialPath);
  await router.isReady();
  const wrapper = mount(BillingTabs, {
    global: { plugins: [router], mocks: { $t: key => key } },
  });
  return { router, wrapper };
};

describe('Billing tabs', () => {
  it('opens Usage by default and stores the selection in the URL', async () => {
    const { router, wrapper } = await mountTabs('/billing');

    expect(wrapper.find('[role="tablist"]').exists()).toBe(true);
    expect(wrapper.find('#billing-tab-uso').attributes('aria-selected')).toBe(
      'true'
    );
    await wrapper.find('#billing-tab-facturacion').trigger('click');
    await flushPromises();
    expect(router.currentRoute.value.query.tab).toBe('facturacion');
    wrapper.unmount();
  });

  it('restores the selected tab from the URL and supports arrow keys', async () => {
    const { router, wrapper } = await mountTabs('/billing?tab=facturacion');

    expect(
      wrapper.find('#billing-tab-facturacion').attributes('aria-selected')
    ).toBe('true');
    await wrapper.find('#billing-tab-facturacion').trigger('keydown', {
      key: 'ArrowLeft',
    });
    await flushPromises();
    expect(router.currentRoute.value.query.tab).toBe('uso');
    wrapper.unmount();
  });
});
