import { mount } from '@vue/test-utils';
import FlowPublishDialog from '../FlowPublishDialog.vue';

vi.mock('vue-i18n', () => ({
  useI18n: () => ({ t: key => key }),
}));

const DialogStub = {
  name: 'Dialog',
  props: ['title'],
  data: () => ({ isOpen: false }),
  methods: {
    open() {
      this.isOpen = true;
    },
    close() {
      this.isOpen = false;
    },
  },
  template:
    '<div v-if="isOpen" :data-title="title"><slot /><slot name="footer" /></div>',
};

const row = (state, extra = {}) => ({
  wabaId: '111',
  channelId: 7,
  phoneNumber: '+593990000001',
  state,
  errors: [],
  ...extra,
});

const mountDialog = (props = {}) => {
  const wrapper = mount(FlowPublishDialog, {
    props: { rows: [row('none')], busy: false, ...props },
    global: { mocks: { $t: key => key }, stubs: { Dialog: DialogStub } },
  });
  wrapper.vm.open();
  return wrapper;
};

describe('FlowPublishDialog', () => {
  it('asks first: every inbox, every Cloud account, versions, and the state per WABA', async () => {
    const wrapper = mountDialog();
    await wrapper.vm.$nextTick();

    const confirm = wrapper.get('[data-testid="flow-publish-confirm"]').text();
    expect(confirm).toContain('WHATSAPP_FLOWS.META.PUBLISH_POINT_INBOXES');
    expect(confirm).toContain('WHATSAPP_FLOWS.META.PUBLISH_POINT_META');
    expect(confirm).toContain('WHATSAPP_FLOWS.META.PUBLISH_POINT_VERSION');
    expect(wrapper.findAll('[data-testid="flow-meta-row"]')).toHaveLength(1);
    expect(wrapper.emitted('publish')).toBeUndefined();
  });

  it('publishes only when confirmed, then shows the progress', async () => {
    const wrapper = mountDialog();
    await wrapper.vm.$nextTick();

    await wrapper
      .get('[data-testid="flow-publish-confirm-button"]')
      .trigger('click');

    expect(wrapper.emitted('publish')).toHaveLength(1);
    expect(wrapper.find('[data-testid="flow-publish-confirm"]').exists()).toBe(
      false
    );
    expect(wrapper.find('[data-testid="flow-publish-progress"]').exists()).toBe(
      true
    );
    expect(
      wrapper.find('[data-testid="flow-publish-confirm-button"]').exists()
    ).toBe(false);
  });

  it("shows the result per WABA with Meta's errors and a retry once it stopped", async () => {
    const wrapper = mountDialog({
      rows: [
        row('published'),
        row('error', {
          wabaId: '222',
          errors: [{ path: 'screens[0]', message: 'bad value' }],
        }),
      ],
    });
    await wrapper.vm.$nextTick();
    await wrapper
      .get('[data-testid="flow-publish-confirm-button"]')
      .trigger('click');

    expect(wrapper.find('[data-testid="flow-publish-failed"]').exists()).toBe(
      true
    );
    expect(wrapper.get('[data-testid="flow-meta-errors"]').text()).toContain(
      'bad value'
    );
    await wrapper.get('[data-testid="flow-meta-retry"]').trigger('click');
    expect(wrapper.emitted('retry')).toEqual([['222']]);
  });

  it('says it is working while Meta is being asked, and offers no retry yet', async () => {
    const wrapper = mountDialog({ busy: true, rows: [row('error')] });
    await wrapper.vm.$nextTick();
    await wrapper
      .get('[data-testid="flow-publish-confirm-button"]')
      .trigger('click');

    expect(
      wrapper.get('[data-testid="flow-publish-progress"]').text()
    ).toContain('WHATSAPP_FLOWS.META.PUBLISH_WORKING');
    expect(wrapper.find('[data-testid="flow-meta-retry"]').exists()).toBe(
      false
    );
  });

  it('says it is done when every WABA is published', async () => {
    const wrapper = mountDialog({ rows: [row('published')] });
    await wrapper.vm.$nextTick();
    await wrapper
      .get('[data-testid="flow-publish-confirm-button"]')
      .trigger('click');

    expect(wrapper.find('[data-testid="flow-publish-done"]').exists()).toBe(
      true
    );
  });

  it('closes, and opens again at the question', async () => {
    const wrapper = mountDialog();
    await wrapper.vm.$nextTick();
    await wrapper
      .get('[data-testid="flow-publish-confirm-button"]')
      .trigger('click');

    await wrapper.get('[data-testid="flow-publish-close"]').trigger('click');
    expect(wrapper.find('[data-testid="flow-publish-progress"]').exists()).toBe(
      false
    );
    wrapper.vm.open();
    await wrapper.vm.$nextTick();
    expect(wrapper.find('[data-testid="flow-publish-confirm"]').exists()).toBe(
      true
    );
  });
});
