import { mount } from '@vue/test-utils';
import { describe, expect, it } from 'vitest';
import Button from 'dashboard/components-next/button/Button.vue';

describe('integration action button intent', () => {
  it('renders primary actions with the solid blue classes', () => {
    const wrapper = mount(Button, {
      props: { label: 'Connect', intent: 'primary' },
    });

    expect(wrapper.classes()).toContain('bg-n-brand');
    expect(wrapper.classes()).toContain('text-white');
  });
});
