import { shallowMount, flushPromises, config } from '@vue/test-utils';
import { nextTick } from 'vue';
import messages from 'dashboard/i18n/locale/en/integrations.json';
import spanish from 'dashboard/i18n/locale/es/integrations.json';
import { useStore } from 'dashboard/composables/store';
import CaptainInboxes from 'dashboard/api/captain/inboxes';
import Button from 'dashboard/components-next/button/Button.vue';
import TextArea from 'dashboard/components-next/textarea/TextArea.vue';
import FilterSelect from 'dashboard/components-next/filter/inputs/FilterSelect.vue';
import AudienceGroup from './AudienceGroup.vue';
import InboxAudienceCard from './InboxAudienceCard.vue';
import { cleanLines, listError } from './inboxAudience';

vi.mock('dashboard/composables/store', () => ({ useStore: vi.fn() }));
const dispatch = vi.fn();
const i18n = config.global.plugins[0];
i18n.global.setLocaleMessage('en', messages);
i18n.global.setLocaleMessage('es', spanish);
const inbox = {
  id: 3,
  name: 'Support',
  channel_type: 'Channel::Instagram',
  audience_mode: 'custom',
  audience_rules: {
    channel_ids: { mode: 'deny', list: ['@client', '@spam'] },
    contact_scope: 'new',
  },
};
const mountCard = (overrides = {}, canEdit = true, locale = 'en') => {
  i18n.global.locale.value = locale;
  return shallowMount(InboxAudienceCard, {
    props: {
      inbox: { ...inbox, ...overrides },
      assistantId: 7,
      canEdit,
      filterTypes: [],
    },
    global: {
      stubs: { Banner: false },
    },
  });
};
const open = wrapper => wrapper.get('button').trigger('click');
const action = (wrapper, label) =>
  wrapper
    .findAllComponents(Button)
    .find(button => button.props('label') === label);

beforeEach(() => {
  useStore.mockReturnValue({ dispatch });
  dispatch.mockResolvedValue({});
});

describe('inbox audience', () => {
  it.each([
    ['inherit', 'Uses the base rule'],
    ['everyone', 'Responds to everyone'],
    ['custom', 'Custom rules · Blocks 2 users · New customers only'],
  ])('summarizes %s', (audienceMode, expected) => {
    expect(mountCard({ audience_mode: audienceMode }).text()).toContain(
      expected
    );
  });

  it.each([
    ['Whatsapp', 'Phone numbers', 'phones'],
    ['Sms', 'Phone numbers', 'phones'],
    ['TwilioSms', 'Phone numbers', 'phones'],
    ['Instagram', 'Instagram usernames or IDs', 'channel_ids'],
    ['FacebookPage', 'Messenger usernames or IDs', 'channel_ids'],
    ['WebWidget', 'Emails or domains (@company.com)', 'emails'],
    ['Email', 'Emails or domains (@company.com)', 'emails'],
  ])('shows and saves the list for %s', async (channel, label, listKey) => {
    const wrapper = mountCard({
      channel_type: `Channel::${channel}`,
      audience_rules: { [listKey]: { mode: 'allow', list: ['one'] } },
    });
    await open(wrapper);
    expect(wrapper.findAllComponents(TextArea)).toHaveLength(1);
    expect(wrapper.findComponent(TextArea).attributes('aria-label')).toBe(
      label
    );
    await action(wrapper, 'Save').vm.$emit('click');
    await flushPromises();
    expect(dispatch).toHaveBeenCalledWith(
      'captainInboxes/setAudience',
      expect.objectContaining({
        audienceRules: {
          [listKey]: { mode: 'allow', list: ['one'] },
          contact_scope: 'all',
        },
      })
    );
  });

  it.each([
    ['allow', 'Captain does not respond'],
    ['deny', 'Captain responds'],
  ])('explains missing data for %s', async (mode, expected) => {
    const wrapper = mountCard({
      audience_rules: { channel_ids: { mode, list: ['a', 'b'] } },
    });
    await open(wrapper);
    expect(wrapper.text()).toContain(
      `2 users · If the contact has no username, ${expected}`
    );
  });

  it('removes blank lines and exact duplicates before saving', async () => {
    const wrapper = mountCard();
    await open(wrapper);
    wrapper
      .findComponent(TextArea)
      .vm.$emit('update:modelValue', ' @client \r\n\n@spam\n@client\n');
    await nextTick();
    action(wrapper, 'Save').vm.$emit('click');
    await flushPromises();
    expect(dispatch).toHaveBeenCalledWith('captainInboxes/setAudience', {
      assistantId: 7,
      inboxId: 3,
      audienceMode: 'custom',
      audienceRules: {
        channel_ids: { mode: 'deny', list: ['@client', '@spam'] },
        contact_scope: 'new',
      },
    });
    expect(wrapper.get('button').attributes('aria-expanded')).toBe('false');
    expect(wrapper.get('[role="status"]').text()).toBe('Saved');
  });

  it('hides the textarea and removes the list with no list selected', async () => {
    const wrapper = mountCard();
    await open(wrapper);
    wrapper.findComponent(FilterSelect).vm.$emit('update:modelValue', 'none');
    await nextTick();
    expect(wrapper.findComponent(TextArea).exists()).toBe(false);
    action(wrapper, 'Save').vm.$emit('click');
    await flushPromises();
    expect(dispatch.mock.calls[0][1].audienceRules).toEqual({
      contact_scope: 'new',
    });
  });

  it.each([
    Array.from({ length: 1001 }, (_, i) => String(i)).join('\n'),
    'x'.repeat(121),
  ])('blocks invalid lists', async value => {
    const wrapper = mountCard();
    await open(wrapper);
    wrapper.findComponent(TextArea).vm.$emit('update:modelValue', value);
    await nextTick();
    expect(wrapper.find('[role="alert"]').exists()).toBe(true);
    expect(action(wrapper, 'Save').attributes('disabled')).toBeDefined();
    action(wrapper, 'Save').vm.$emit('click');
    expect(dispatch).not.toHaveBeenCalled();
  });

  it('discards changes on cancel', async () => {
    const wrapper = mountCard();
    await open(wrapper);
    wrapper.findComponent(TextArea).vm.$emit('update:modelValue', 'changed');
    action(wrapper, 'Cancel').vm.$emit('click');
    await nextTick();
    await open(wrapper);
    expect(wrapper.findComponent(TextArea).props('modelValue')).toBe(
      '@client\n@spam'
    );
    expect(dispatch).not.toHaveBeenCalled();
  });

  it('shows API errors inside the open card', async () => {
    dispatch.mockRejectedValue({
      response: { data: { message: 'Invalid audience' } },
    });
    const wrapper = mountCard();
    await open(wrapper);
    action(wrapper, 'Save').vm.$emit('click');
    await flushPromises();
    expect(wrapper.get('[role="alert"]').text()).toBe('Invalid audience');
    expect(wrapper.get('button').attributes('aria-expanded')).toBe('true');
  });

  it.each(['inherit', 'everyone'])(
    'saves %s without discarding stored custom rules',
    async audienceMode => {
      const wrapper = mountCard({ audience_mode: audienceMode });
      await open(wrapper);
      action(wrapper, 'Save').vm.$emit('click');
      await flushPromises();
      expect(dispatch.mock.calls[0][1]).toMatchObject({
        audienceMode,
        audienceRules: inbox.audience_rules,
      });
    }
  );

  it('validates and serializes the advanced tree without UI-only keys', async () => {
    const leaf = {
      attribute_key: 'email',
      filter_operator: 'contains',
      values: ['@company.com'],
    };
    const wrapper = mountCard({
      audience_rules: { tree: { operator: 'and', conditions: [leaf] } },
    });
    await open(wrapper);
    action(wrapper, 'Advanced conditions').vm.$emit('click');
    await nextTick();
    const group = wrapper.findComponent(AudienceGroup);
    group.vm.validate = vi.fn(() => false);
    action(wrapper, 'Save').vm.$emit('click');
    await flushPromises();
    expect(dispatch).not.toHaveBeenCalled();
    group.vm.validate = vi.fn(() => true);
    action(wrapper, 'Save').vm.$emit('click');
    await flushPromises();
    expect(dispatch.mock.calls[0][1].audienceRules.tree).toEqual({
      operator: 'and',
      conditions: [leaf],
    });
  });

  it('blocks a second save while the first request is pending', async () => {
    let finish;
    dispatch.mockImplementation(
      () =>
        new Promise(resolve => {
          finish = resolve;
        })
    );
    const wrapper = mountCard();
    await open(wrapper);
    const save = action(wrapper, 'Save');
    save.vm.$emit('click');
    await nextTick();
    save.vm.$emit('click');
    expect(dispatch).toHaveBeenCalledTimes(1);
    expect(save.attributes('disabled')).toBeDefined();
    finish();
    await flushPromises();
  });

  it('shows inheritance warnings only for inherit', async () => {
    const wrapper = mountCard({ audience_mode: 'inherit' });
    await wrapper.setProps({ warnings: ['Missing phone'] });
    expect(wrapper.find('[aria-label]').exists()).toBe(true);
    await open(wrapper);
    expect(wrapper.text()).toContain('Missing phone');
    await wrapper
      .get('[data-testid="inbox-audience-mode-everyone"]')
      .trigger('click');
    await nextTick();
    expect(wrapper.text()).not.toContain('Missing phone');
  });

  it('renders a compact segmented control for editable inboxes', async () => {
    const wrapper = mountCard();
    await open(wrapper);
    const control = wrapper.get('[data-testid="inbox-audience-mode"]');
    expect(control.classes()).toContain('h-8');
    expect(control.classes()).toContain('max-sm:h-11');
    expect(control.classes()).toContain('grid-cols-3');
    expect(control.findAll('[role="radio"]')).toHaveLength(3);
    expect(
      wrapper.get('[data-testid="inbox-audience-mode-inherit"]').text()
    ).toBe('Base rule');
    expect(
      wrapper
        .get('[data-testid="inbox-audience-mode-custom"]')
        .attributes('aria-checked')
    ).toBe('true');
    await wrapper
      .get('[data-testid="inbox-audience-mode-everyone"]')
      .trigger('click');
    expect(
      wrapper
        .get('[data-testid="inbox-audience-mode-everyone"]')
        .attributes('aria-checked')
    ).toBe('true');
  });

  it('lets non-admins inspect lists and advanced rules without editing', async () => {
    const wrapper = mountCard({}, false);
    await open(wrapper);
    expect(wrapper.find('[data-testid="inbox-audience-mode"]').exists()).toBe(
      false
    );
    expect(wrapper.findComponent(FilterSelect).exists()).toBe(false);
    expect(wrapper.findComponent(TextArea).props('disabled')).toBe(true);
    expect(action(wrapper, 'Save')).toBeUndefined();
    action(wrapper, 'Advanced conditions').vm.$emit('click');
    await nextTick();
    expect(wrapper.findComponent(AudienceGroup).exists()).toBe(true);
    expect(
      wrapper.findComponent(AudienceGroup).element.closest('fieldset').disabled
    ).toBe(true);
    expect(dispatch).not.toHaveBeenCalled();
  });

  it('uses the Spanish copy and has matching translation keys', async () => {
    const wrapper = mountCard({}, true, 'es');
    await open(wrapper);
    expect(wrapper.text()).toContain(
      '2 usuarios · Si el contacto no tiene usuario, Captain lo atiende'
    );
    expect(
      Object.keys(messages.CAPTAIN.ASSISTANTS.FORM.AUDIENCE.INBOX).sort()
    ).toEqual(
      Object.keys(spanish.CAPTAIN.ASSISTANTS.FORM.AUDIENCE.INBOX).sort()
    );
  });

  it('sends the documented HTTP payload', async () => {
    global.axios = { patch: vi.fn() };
    await CaptainInboxes.updateAudience({
      assistantId: 7,
      inboxId: 3,
      audienceMode: 'everyone',
      audienceRules: {},
    });
    expect(global.axios.patch).toHaveBeenCalledWith(
      expect.stringContaining('/7/inboxes/3'),
      { inbox: { audience_mode: 'everyone', audience_rules: {} } }
    );
  });

  it('accepts exact limits and counts Unicode characters like the server', () => {
    expect(cleanLines(' a \r\n\n a\nb ')).toEqual(['a', 'b']);
    expect(listError(Array.from({ length: 1000 }, (_, i) => String(i)))).toBe(
      ''
    );
    expect(listError(['x'.repeat(120)])).toBe('');
    expect(listError(['😀'.repeat(120)])).toBe('');
  });
});
