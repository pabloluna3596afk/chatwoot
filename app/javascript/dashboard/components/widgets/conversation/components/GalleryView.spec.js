import { mount } from '@vue/test-utils';
import { ref, nextTick } from 'vue';
import { createI18n } from 'vue-i18n';
import settings from 'dashboard/i18n/locale/en/settings.json';
import conversation from 'dashboard/i18n/locale/en/conversation.json';
import GalleryView from './GalleryView.vue';

vi.mock('dashboard/composables/store', () => ({
  useStoreGetters: () => ({ getCurrentUser: ref({ id: 1 }) }),
}));
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));
vi.mock('dashboard/composables/useKeyboardEvents', () => ({
  useKeyboardEvents: vi.fn(),
}));
const pdf = {
  id: 1,
  message_id: 10,
  file_type: 'file',
  content_type: 'application/pdf',
  extension: 'pdf',
  file_size: 1024,
  data_url: '/document.pdf',
};
const options = () => ({
  global: {
    plugins: [
      createI18n({
        legacy: false,
        locale: 'en',
        messages: { en: { ...conversation, ...settings } },
      }),
    ],
    stubs: { TeleportWithDirection: { template: '<div><slot /></div>' } },
    directives: {
      dompurifyHtml: (el, binding) => {
        el.textContent = binding.value;
      },
    },
  },
});

describe('gallery PDF preview', () => {
  it('allows retrying a failed video without treating it as an image', async () => {
    const video = { ...pdf, file_type: 'video', data_url: '/clip.mp4' };
    const wrapper = mount(GalleryView, {
      ...options(),
      props: { attachment: video, allAttachments: [video], show: true },
    });
    await nextTick();
    await wrapper.get('video').trigger('error');
    expect(wrapper.get('[role="status"]').text()).toContain('Could not load');
    await wrapper.get('[role="status"] button').trigger('click');
    expect(wrapper.get('video').attributes('src')).toBe('/clip.mp4');
    await wrapper.get('video').trigger('loadeddata');
    expect(wrapper.find('[role="status"]').exists()).toBe(false);
  });

  it('embeds only a small application/pdf without sandbox and links to the original', async () => {
    const wrapper = mount(GalleryView, {
      ...options(),
      props: { attachment: pdf, allAttachments: [pdf], show: true },
    });
    await nextTick();
    const iframe = wrapper.get('iframe');
    expect(iframe.attributes('src')).toBe(pdf.data_url);
    expect(iframe.attributes('title')).toBe('document.pdf');
    expect(iframe.attributes('sandbox')).toBeUndefined();
    expect(iframe.attributes('referrerpolicy')).toBe('no-referrer');
    expect(wrapper.text()).toContain('1 of 1');
    const link = wrapper.get('a');
    expect(link.text()).toBe('Open original');
    expect(link.attributes()).toMatchObject({
      href: pdf.data_url,
      target: '_blank',
      rel: 'noopener noreferrer',
    });
    expect(wrapper.find('[icon="i-lucide-zoom-in"]').exists()).toBe(false);
  });

  it('shows the download explanation for a 30 MB PDF', async () => {
    const wrapper = mount(GalleryView, {
      ...options(),
      props: {
        attachment: { ...pdf, file_size: 30 * 1024 * 1024 },
        allAttachments: [pdf],
        show: true,
      },
    });
    await nextTick();
    expect(wrapper.find('iframe').exists()).toBe(false);
    expect(wrapper.text()).toContain(
      'This PDF is large. Download it to view it.'
    );
  });

  it.each([
    ['html', 'text/html'],
    ['svg', 'image/svg+xml'],
    ['txt', 'text/plain'],
    ['pdf', 'text/html'],
  ])('never embeds %s with MIME %s', async (extension, content_type) => {
    const wrapper = mount(GalleryView, {
      ...options(),
      props: {
        attachment: { ...pdf, extension, content_type },
        allAttachments: [pdf],
        show: true,
      },
    });
    await nextTick();
    expect(wrapper.find('iframe').exists()).toBe(false);
  });

  it('selects by attachment id when several photos share a message, and returns focus on close', async () => {
    const trigger = document.createElement('button');
    document.body.appendChild(trigger);
    trigger.focus();
    const second = { ...pdf, id: 2, data_url: '/second.pdf' };
    const wrapper = mount(GalleryView, {
      ...options(),
      props: { attachment: second, allAttachments: [pdf, second], show: true },
    });
    await nextTick();
    expect(wrapper.text()).toContain('2 of 2');
    expect(wrapper.get('iframe').attributes('src')).toBe('/second.pdf');
    await wrapper.get('[icon="i-lucide-x"]').trigger('click');
    expect(wrapper.emitted('close')).toHaveLength(1);
    expect(document.activeElement).toBe(trigger);
    trigger.remove();
  });
});
