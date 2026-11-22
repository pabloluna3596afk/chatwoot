import { mount } from '@vue/test-utils';
import { createStore } from 'vuex';
import { ref } from 'vue';
import DropdownFloating from '../DropdownFloating.vue';

const mountMenu = provide => {
  const store = createStore({
    getters: { 'accounts/isRTL': () => () => false },
  });
  const host = document.createElement('div');
  host.id = 'host';
  document.body.appendChild(host);
  const trigger = document.createElement('button');
  document.body.appendChild(trigger);
  const wrapper = mount(DropdownFloating, {
    props: { trigger: () => trigger },
    slots: { default: '<span id="item">Option</span>' },
    global: { plugins: [store], provide },
    attachTo: document.body,
  });
  return { wrapper, host };
};

describe('DropdownFloating', () => {
  afterEach(() => {
    document.body.innerHTML = '';
  });

  it('renders inside the dialog target so a top-layer dialog cannot hide it', () => {
    const { wrapper, host } = mountMenu({});
    const dialogTarget = ref(host);
    wrapper.unmount();
    const { wrapper: inDialog } = mountMenu({
      dialogPortalTarget: dialogTarget,
    });
    expect(host.querySelector('[data-dropdown-menu] #item')).not.toBeNull();
    inDialog.unmount();
  });

  it('falls back to body outside a dialog', () => {
    const { wrapper } = mountMenu({});
    expect(
      document.body.querySelector('[data-dropdown-menu] #item')
    ).not.toBeNull();
    wrapper.unmount();
  });
});
