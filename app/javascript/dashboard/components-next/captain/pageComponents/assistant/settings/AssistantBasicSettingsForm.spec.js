import { shallowMount } from '@vue/test-utils';
import { describe, expect, it, vi } from 'vitest';
import Avatar from 'dashboard/components-next/avatar/Avatar.vue';
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
