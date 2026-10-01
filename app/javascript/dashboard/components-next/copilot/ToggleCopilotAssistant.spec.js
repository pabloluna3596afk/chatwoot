import { shallowMount } from '@vue/test-utils';
import ToggleCopilotAssistant from './ToggleCopilotAssistant.vue';

vi.mock('vue-i18n', () => ({
  useI18n: () => ({ t: key => key }),
}));

const assistants = [
  { id: 1, name: 'Acme', description: 'A', avatar_url: 'https://x.test/a.png' },
  { id: 2, name: 'Beta', description: 'B', avatar_url: 'https://x.test/b.png' },
];

describe('ToggleCopilotAssistant', () => {
  it('renders the active assistant avatar in the trigger and every option', () => {
    const wrapper = shallowMount(ToggleCopilotAssistant, {
      props: { assistants, activeAssistant: assistants[0] },
      global: {
        stubs: {
          DropdownContainer: {
            template:
              '<div><slot name="trigger" :toggle="() => {}" :is-open="false" /><slot /></div>',
          },
          DropdownBody: { template: '<div><slot /></div>' },
          DropdownSection: { template: '<div><slot /></div>' },
          DropdownItem: {
            template: '<div><slot name="label" /></div>',
          },
          Button: { template: '<button><slot /></button>' },
        },
      },
    });
    const srcs = wrapper
      .findAllComponents({ name: 'Avatar' })
      .map(avatar => avatar.props('src'));

    expect(srcs).toEqual([
      'https://x.test/a.png',
      'https://x.test/a.png',
      'https://x.test/b.png',
    ]);
  });
});
