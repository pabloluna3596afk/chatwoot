import { mount } from '@vue/test-utils';
import UserMessageBubble from './UserMessageBubble.vue';

describe('visitor list messages', () => {
  it.each(['1. First\n2. Second', '- First\n- Second'])(
    'renders list markup with shared list styling',
    message => {
      const wrapper = mount(UserMessageBubble, {
        props: { message, widgetColor: '#0066ff' },
        global: {
          directives: {
            dompurifyHtml: (el, binding) => {
              el.innerHTML = binding.value;
            },
          },
        },
      });
      expect(wrapper.classes()).toContain('message-content');
      expect(wrapper.findAll('li')).toHaveLength(2);
    }
  );
});
