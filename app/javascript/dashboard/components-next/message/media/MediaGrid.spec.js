import { mount } from '@vue/test-utils';
import { ref } from 'vue';
import { createI18n } from 'vue-i18n';
import settings from 'dashboard/i18n/locale/en/settings.json';
import conversation from 'dashboard/i18n/locale/en/conversation.json';
import MediaGrid from './MediaGrid.vue';
import MediaTile from './MediaTile.vue';

vi.mock('../provider', () => ({
  useMessageContext: () => ({
    filteredCurrentChatAttachments: ref([]),
    channelType: ref(''),
  }),
}));
const image = {
  id: 1,
  fileType: 'image',
  dataUrl: '/photo.png',
  thumbUrl: '/thumb.png',
  width: 800,
  height: 600,
};
const options = () => ({
  global: {
    plugins: [
      createI18n({
        legacy: false,
        locale: 'en',
        messages: { en: { ...settings, ...conversation } },
      }),
    ],
    stubs: { GalleryView: true },
  },
});

describe('attachment media grid', () => {
  it('reserves the single image aspect, keeps it whole and supplies accessible labels', () => {
    const wrapper = mount(MediaGrid, {
      ...options(),
      props: { items: [image], caption: 'Receipt' },
    });
    expect(wrapper.get('img').attributes('src')).toBe('/photo.png');
    expect(wrapper.get('img').classes()).toContain('object-contain');
    expect(wrapper.get('img').classes()).not.toContain('object-cover');
    expect(wrapper.get('img').attributes('alt')).toBe('Receipt');
    expect(wrapper.get('svg').attributes('viewBox')).toBe('0 0 800 600');
    expect(wrapper.get('button').attributes('aria-label')).toBe('Photo 1 of 1');
    expect(wrapper.html()).toContain('[@media(hover:none)]:opacity-100');
    expect(wrapper.html()).toContain('motion-reduce:animate-none');
  });

  it('marks a tall image and preserves the natural dimensions of a tiny one', () => {
    const tall = mount(MediaGrid, {
      ...options(),
      props: { items: [{ ...image, width: 1000, height: 4000 }] },
    });
    expect(tall.text()).toContain('View full');
    expect(tall.get('img').classes()).toContain('object-top');
    const tiny = mount(MediaGrid, {
      ...options(),
      props: { items: [{ ...image, width: 40, height: 40 }] },
    });
    expect(tiny.get('svg').attributes('width')).toBe('40');
    expect(tiny.get('svg').classes()).not.toContain('w-full');
    expect(tiny.get('figure').classes()).toContain('p-3');
  });

  it.each([2, 3, 4, 7])(
    'renders %s attachments using thumbnails and opens the selected attachment',
    async count => {
      const items = Array.from({ length: count }, (_, index) => ({
        ...image,
        id: index + 1,
      }));
      const wrapper = mount(MediaGrid, { ...options(), props: { items } });
      expect(wrapper.findAll('img')).toHaveLength(Math.min(count, 4));
      expect(wrapper.get('img').attributes('src')).toBe('/thumb.png');
      if (count === 3)
        expect(wrapper.get('figure').classes()).toContain('row-span-2');
      if (count === 7) expect(wrapper.text()).toContain('+3');
      await wrapper.findAll('figure')[1].get('button').trigger('click');
      expect(
        wrapper.getComponent({ name: 'GalleryView' }).props('attachment').id
      ).toBe(2);
    }
  );

  it('shows a retry and open link on load error, then clears the error after load', async () => {
    const wrapper = mount(MediaTile, {
      ...options(),
      props: { attachment: image, index: 0, total: 1 },
    });
    await wrapper.get('img').trigger('error');
    expect(wrapper.text()).toContain('Could not load');
    expect(wrapper.text()).toContain('Retry');
    expect(wrapper.get('a').attributes('href')).toBe('/photo.png');
  });

  it('labels unavailable Instagram media without retrying', async () => {
    const wrapper = mount(MediaTile, {
      ...options(),
      props: {
        attachment: image,
        channelType: 'Channel::Instagram',
        index: 0,
        total: 1,
      },
    });
    await wrapper.get('img').trigger('error');
    expect(wrapper.text()).toContain(
      'This file is no longer available on Instagram.'
    );
    expect(wrapper.text()).not.toContain('Retry');
  });
});
