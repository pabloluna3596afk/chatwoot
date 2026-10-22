import { nextTick, ref } from 'vue';
import { shallowMount } from '@vue/test-utils';
import { beforeEach, describe, expect, it, vi } from 'vitest';
import { useMapGetter, useStore } from 'dashboard/composables/store';
import Button from 'dashboard/components-next/button/Button.vue';
import Banner from 'dashboard/components-next/banner/Banner.vue';
import RadioCard from 'dashboard/components-next/radioCard/RadioCard.vue';
import AudienceGroup from './audience/AudienceGroup.vue';
import { useAudienceFilterTypes } from './audience/useAudienceFilterTypes';
import AssistantAudienceForm from './AssistantAudienceForm.vue';

vi.mock('vue-i18n', () => ({
  useI18n: () => ({
    t: (key, params) => (params ? `${key}: ${JSON.stringify(params)}` : key),
  }),
}));
vi.mock('dashboard/composables/store', () => ({
  useMapGetter: vi.fn(),
  useStore: vi.fn(),
}));
vi.mock('./audience/useAudienceFilterTypes.js', () => ({
  useAudienceFilterTypes: vi.fn(),
}));

const connectedInboxes = ref([]);
const uiFlags = ref({ fetchingList: false });
const dispatch = vi.fn();
const phoneCondition = {
  attribute_key: 'phone_number',
  filter_operator: 'contains',
  values: ['+593'],
};
const mountComponent = (audience = null) =>
  shallowMount(AssistantAudienceForm, {
    props: { assistant: { id: 7, config: { audience } } },
    global: { stubs: { RadioCard: false, Banner: false } },
  });

beforeEach(() => {
  connectedInboxes.value = [];
  uiFlags.value = { fetchingList: false };
  useMapGetter.mockImplementation(key =>
    key === 'captainInboxes/getRecords' ? connectedInboxes : uiFlags
  );
  useStore.mockReturnValue({ dispatch });
  useAudienceFilterTypes.mockReturnValue({
    filterTypes: ref([
      {
        attributeKey: 'phone_number',
        label: 'Phone number',
        inputType: 'plainText',
      },
      { attributeKey: 'email', label: 'Email', inputType: 'plainText' },
    ]),
  });
});

describe('AssistantAudienceForm', () => {
  it('does not submit a specific audience without conditions', async () => {
    const wrapper = mountComponent();
    wrapper.findAllComponents(RadioCard)[1].vm.$emit('select', 'specific');
    await nextTick();
    wrapper.findComponent(Button).vm.$emit('click');
    await nextTick();
    expect(wrapper.emitted('submit')).toBeUndefined();
    expect(wrapper.text()).toContain(
      'CAPTAIN.ASSISTANTS.FORM.AUDIENCE.EMPTY_ERROR'
    );
  });

  it('loads the current assistant inboxes and reloads when the assistant changes', async () => {
    const wrapper = mountComponent();
    expect(dispatch).toHaveBeenCalledWith('captainInboxes/get', {
      assistantId: 7,
    });
    await wrapper.setProps({ assistant: { id: 8, config: {} } });
    expect(dispatch).toHaveBeenCalledWith('captainInboxes/get', {
      assistantId: 8,
    });
  });

  it.each(['Instagram', 'FacebookPage', 'WebWidget', 'Email'])(
    'warns about phone data for Channel::%s',
    channel => {
      connectedInboxes.value = [{ channel_type: `Channel::${channel}` }];
      const wrapper = mountComponent(phoneCondition);
      expect(wrapper.findComponent(Banner).props('color')).toBe('amber');
      expect(wrapper.text()).toContain('AUDIENCE.CHANNEL_WARNING');
      expect(wrapper.text()).toContain('Phone number');
    }
  );

  it.each(['Whatsapp', 'Sms', 'TwilioSms', 'Instagram', 'FacebookPage'])(
    'warns about email data for Channel::%s',
    channel => {
      connectedInboxes.value = [{ channel_type: `Channel::${channel}` }];
      const wrapper = mountComponent({
        ...phoneCondition,
        attribute_key: 'email',
      });
      expect(wrapper.text()).toContain('AUDIENCE.CHANNEL_WARNING');
      expect(wrapper.text()).toContain('Email');
    }
  );

  it('finds nested conditions and deduplicates channel names', () => {
    connectedInboxes.value = [
      { channel_type: 'Channel::Instagram' },
      { channel_type: 'Channel::Instagram' },
    ];
    const wrapper = mountComponent({
      operator: 'and',
      conditions: [
        { operator: 'or', conditions: [phoneCondition, phoneCondition] },
      ],
    });
    expect(wrapper.findAllComponents(Banner)).toHaveLength(1);
    expect(wrapper.text().match(/CHANNELS.INSTAGRAM/g)).toHaveLength(1);
  });

  it('does not warn when connected channels support the attribute', () => {
    connectedInboxes.value = [{ channel_type: 'Channel::Whatsapp' }];
    expect(mountComponent(phoneCondition).findComponent(Banner).exists()).toBe(
      false
    );
    connectedInboxes.value = [{ channel_type: 'Channel::Email' }];
    expect(
      mountComponent({ ...phoneCondition, attribute_key: 'email' })
        .findComponent(Banner)
        .exists()
    ).toBe(false);
  });

  it('handles Twilio WhatsApp as WhatsApp', () => {
    connectedInboxes.value = [
      { channel_type: 'Channel::TwilioSms', medium: 'whatsapp' },
    ];
    const wrapper = mountComponent({
      ...phoneCondition,
      attribute_key: 'email',
    });
    expect(wrapper.text()).toContain('CHANNELS.WHATSAPP');
    expect(wrapper.text()).not.toContain('CHANNELS.SMS');
  });

  it('does not show stale inbox warnings while fetching', () => {
    connectedInboxes.value = [{ channel_type: 'Channel::Instagram' }];
    uiFlags.value.fetchingList = true;
    expect(mountComponent(phoneCondition).findComponent(Banner).exists()).toBe(
      false
    );
  });

  it('does not warn for everyone or without connected inboxes', () => {
    expect(mountComponent(phoneCondition).findComponent(Banner).exists()).toBe(
      false
    );
    connectedInboxes.value = [{ channel_type: 'Channel::Instagram' }];
    expect(mountComponent().findComponent(Banner).exists()).toBe(false);
  });

  it('allows saving and reacts to edits without changing the audience', async () => {
    connectedInboxes.value = [{ channel_type: 'Channel::Instagram' }];
    const wrapper = mountComponent(phoneCondition);
    wrapper.findComponent(AudienceGroup).vm.validate = vi.fn(() => true);
    wrapper.findComponent(Button).vm.$emit('click');
    expect(wrapper.emitted('submit')[0][0].config.audience).toEqual({
      operator: 'and',
      conditions: [phoneCondition],
    });
    wrapper
      .findComponent(AudienceGroup)
      .vm.$emit('update:modelValue', { operator: 'and', conditions: [] });
    await nextTick();
    expect(wrapper.findComponent(Banner).exists()).toBe(false);
  });
});
