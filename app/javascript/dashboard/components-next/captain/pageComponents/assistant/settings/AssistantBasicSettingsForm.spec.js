import { flushPromises, shallowMount } from '@vue/test-utils';
import { describe, expect, it, vi } from 'vitest';
import Avatar from 'dashboard/components-next/avatar/Avatar.vue';
import TextArea from 'dashboard/components-next/textarea/TextArea.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import AssistantBasicSettingsForm from './AssistantBasicSettingsForm.vue';

vi.mock('vue-i18n', () => ({
  useI18n: () => ({ t: key => key }),
}));

const assistant = {
  name: 'Sofia',
  description: 'Support assistant',
  avatar_url: 'https://cdn.example.com/sofia.png',
  config: { product_name: 'ChatHub' },
};

const mountComponent = () =>
  shallowMount(AssistantBasicSettingsForm, { props: { assistant } });

describe('AssistantBasicSettingsForm avatar', () => {
  it('gives feature checkboxes a 44 px touch target below md', () => {
    const labels = mountComponent()
      .findAll('label')
      .filter(label => label.classes().includes('max-md:min-h-11'));

    expect(labels).toHaveLength(4);
  });

  it('shows the assistant photo with the upload control enabled', () => {
    const avatar = mountComponent().findComponent(Avatar);

    expect(avatar.props('src')).toBe('https://cdn.example.com/sofia.png');
    expect(avatar.props('name')).toBe('Sofia');
    expect(avatar.props('allowUpload')).toBe(true);
  });

  it('emits the selected file when a photo is uploaded', () => {
    const wrapper = mountComponent();
    const payload = { file: new File(['x'], 'sofia.png'), url: 'blob:x' };

    wrapper.findComponent(Avatar).vm.$emit('upload', payload);

    expect(wrapper.emitted('uploadAvatar')[0]).toEqual([payload]);
  });

  it('emits deleteAvatar when the photo is removed', () => {
    const wrapper = mountComponent();

    wrapper.findComponent(Avatar).vm.$emit('delete');

    expect(wrapper.emitted('deleteAvatar')).toHaveLength(1);
  });
});

describe('AssistantBasicSettingsForm business facts', () => {
  const facts = {
    hours: 'Monday to Friday',
    address: 'Main street',
    payment_methods: 'Cash',
    delivery: 'Nationwide',
    booking: 'Message us',
  };

  it('shows the saved business facts', () => {
    const wrapper = shallowMount(AssistantBasicSettingsForm, {
      props: {
        assistant: {
          ...assistant,
          config: { ...assistant.config, business_facts: facts },
        },
      },
    });

    const fields = wrapper.findAllComponents(TextArea);
    expect(fields.map(field => field.props('modelValue'))).toEqual(
      Object.values(facts)
    );
    fields.forEach(field => {
      expect(field.props('maxLength')).toBe(300);
      expect(field.props('showCharacterCount')).toBe(true);
    });
  });

  it('saves the five facts', async () => {
    const wrapper = mountComponent();
    const fields = wrapper.findAllComponents(TextArea);
    Object.values(facts).forEach((value, index) => {
      fields[index].vm.$emit('update:modelValue', value);
    });
    await wrapper.findComponent(Button).trigger('click');
    await flushPromises();

    expect(wrapper.emitted('submit')[0][0]).toMatchObject({
      name: assistant.name,
      description: assistant.description,
      config: { product_name: 'ChatHub', business_facts: facts },
    });
  });

  it('sends an empty fact so it is cleared', async () => {
    const wrapper = shallowMount(AssistantBasicSettingsForm, {
      props: {
        assistant: {
          ...assistant,
          config: { ...assistant.config, business_facts: facts },
        },
      },
    });
    wrapper.findAllComponents(TextArea)[0].vm.$emit('update:modelValue', '');
    await wrapper.findComponent(Button).trigger('click');
    await flushPromises();

    expect(wrapper.emitted('submit')[0][0].config.business_facts).toEqual({
      ...facts,
      hours: '',
    });
  });

  it('blocks a fact over 300 characters', async () => {
    const wrapper = mountComponent();
    const field = wrapper.findComponent(TextArea);
    field.vm.$emit('update:modelValue', 'x'.repeat(301));
    await wrapper.findComponent(Button).trigger('click');
    await flushPromises();

    expect(wrapper.emitted('submit')).toBeUndefined();
    expect(field.props('message')).toBe(
      'CAPTAIN.ASSISTANTS.BUSINESS_FACTS.TOO_LONG'
    );

    field.vm.$emit('update:modelValue', 'x'.repeat(300));
    await wrapper.findComponent(Button).trigger('click');
    await flushPromises();
    expect(wrapper.emitted('submit')).toHaveLength(1);
  });
});
