import { mount } from '@vue/test-utils';
import { describe, expect, it } from 'vitest';
import Button from 'dashboard/components-next/button/Button.vue';

describe('inbox settings button intents', () => {
  it('renders primary and secondary actions with their semantic classes', () => {
    const primary = mount(Button, {
      props: { label: 'Create policy', intent: 'primary' },
    });
    const secondary = mount(Button, {
      props: { label: 'Cancel', intent: 'secondary' },
    });

    expect(primary.classes()).toContain('bg-n-brand');
    expect(primary.classes()).toContain('text-white');
    expect(secondary.classes()).toContain('bg-n-slate-9/10');
    expect(secondary.classes()).toContain('text-n-slate-12');
  });
});
