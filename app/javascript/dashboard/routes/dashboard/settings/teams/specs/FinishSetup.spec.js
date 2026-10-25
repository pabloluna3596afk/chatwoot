import { mount } from '@vue/test-utils';
import { describe, expect, it } from 'vitest';
import FinishSetup from '../FinishSetup.vue';
import Button from 'dashboard/components-next/button/Button.vue';

describe('team FinishSetup', () => {
  it('renders its final action with primary button classes', () => {
    const wrapper = mount(FinishSetup, {
      global: {
        mocks: { $t: key => key },
        stubs: {
          EmptyState: { template: '<div><slot /></div>' },
          RouterLink: { template: '<div><slot /></div>' },
          NextButton: Button,
        },
      },
    });
    const button = wrapper.get('button');

    expect(button.classes()).toContain('bg-n-brand');
    expect(button.classes()).toContain('text-white');
  });
});
