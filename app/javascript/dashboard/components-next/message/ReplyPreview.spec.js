import { mount } from '@vue/test-utils';
import { ref } from 'vue';
import { createI18n } from 'vue-i18n';
import conversation from 'dashboard/i18n/locale/en/conversation.json';
import { emitter } from 'shared/helpers/mitt';
import { BUS_EVENTS } from 'shared/constants/busEvents';
import ReplyPreview from './ReplyPreview.vue';

const inReplyTo = ref({});
vi.mock('./provider', () => ({
  useMessageContext: () => ({
    inReplyTo,
    channelType: ref('Channel::Instagram'),
  }),
}));
const options = () => ({
  global: {
    plugins: [
      createI18n({
        legacy: false,
        locale: 'en',
        messages: { en: conversation },
      }),
    ],
    directives: {
      dompurifyHtml: (el, binding) => {
        el.innerHTML = binding.value;
      },
    },
  },
});

describe('reply attachment preview', () => {
  it('shows the image thumbnail, type, caption and scrolls to its message', async () => {
    const emit = vi.spyOn(emitter, 'emit');
    inReplyTo.value = {
      id: 14,
      content: 'Payment receipt',
      attachments: [
        {
          file_type: 'image',
          data_url: '/original.png',
          thumb_url: '/thumb.png',
        },
      ],
    };
    const wrapper = mount(ReplyPreview, options());
    expect(wrapper.get('img').attributes('src')).toBe('/thumb.png');
    expect(wrapper.text()).toContain('Photo');
    expect(wrapper.text()).toContain('Payment receipt');
    await wrapper.get('button').trigger('click');
    expect(emit).toHaveBeenCalledWith(BUS_EVENTS.SCROLL_TO_MESSAGE, {
      messageId: 14,
    });
    emit.mockRestore();
  });

  it('shows PDF type, filename and file icon', () => {
    inReplyTo.value = {
      id: 1,
      attachments: [
        { fileType: 'file', dataUrl: '/final.pdf', extension: 'pdf' },
      ],
    };
    const wrapper = mount(ReplyPreview, options());
    expect(wrapper.text()).toContain('PDF');
    expect(wrapper.text()).toContain('final.pdf');
    expect(wrapper.findComponent({ name: 'FileIcon' }).exists()).toBe(true);
    expect(wrapper.find('img').exists()).toBe(false);
  });

  it('shows the sender name and a plain-text excerpt without markup', () => {
    inReplyTo.value = {
      id: 1,
      content: '**Confirmed**',
      sender: { name: 'Ana' },
    };
    const wrapper = mount(ReplyPreview, options());
    expect(wrapper.text()).toContain('Ana');
    expect(wrapper.text()).toContain('Confirmed');
    expect(wrapper.find('strong').exists()).toBe(false);
  });

  it('flattens paragraphs and lists into one clamped excerpt', () => {
    inReplyTo.value = {
      id: 1,
      content: 'First paragraph\n\nSecond paragraph\n\n- one\n- two',
      sender: { name: 'Ana' },
    };
    const wrapper = mount(ReplyPreview, options());
    const excerpt = wrapper.get('[class*="line-clamp-1"][class*="leading-4"]');
    expect(excerpt.text()).toBe('First paragraph Second paragraph one two');
    expect(excerpt.classes()).toContain('sm:line-clamp-2');
    expect(wrapper.findAll('p, ul, li, br')).toHaveLength(0);
  });

  it('caps the excerpt length for a very long message', () => {
    const paragraph = 'Hello, I need to check my order number 24. ';
    inReplyTo.value = {
      id: 1,
      content: Array.from({ length: 40 }, () => paragraph).join('\n\n'),
      sender: { name: 'Ana' },
    };
    const wrapper = mount(ReplyPreview, options());
    const excerpt = wrapper.get('[class*="line-clamp-1"][class*="leading-4"]');
    expect(excerpt.text().length).toBeLessThanOrEqual(240);
    expect(excerpt.text()).not.toContain('\n');
  });

  it('keeps the missing-message text', () => {
    inReplyTo.value = { id: 1 };
    expect(mount(ReplyPreview, options()).text()).toContain(
      'Message not available'
    );
  });

  it('falls back to an icon and unavailable label when an external thumbnail fails', async () => {
    inReplyTo.value = {
      id: 1,
      attachments: [{ fileType: 'image', dataUrl: '/expired.png' }],
    };
    const wrapper = mount(ReplyPreview, options());
    await wrapper.get('img').trigger('error');
    expect(wrapper.find('img').exists()).toBe(false);
    expect(wrapper.text()).toContain('Photo unavailable');
  });
});
