import { mount, flushPromises } from '@vue/test-utils';
import { ref } from 'vue';
import { createI18n } from 'vue-i18n';
import { downloadFile } from '@chatwoot/utils';
import settingsEn from 'dashboard/i18n/locale/en/settings.json';
import settingsEs from 'dashboard/i18n/locale/es/settings.json';
import conversationEn from 'dashboard/i18n/locale/en/conversation.json';
import conversationEs from 'dashboard/i18n/locale/es/conversation.json';
import FileCard from './FileCard.vue';

vi.mock('dashboard/composables/store', () => ({ useMapGetter: () => ref([]) }));
vi.mock('@chatwoot/utils', async importOriginal => ({
  ...(await importOriginal()),
  downloadFile: vi.fn(),
}));
const pdf = {
  id: 2,
  fileType: 'file',
  contentType: 'application/pdf',
  dataUrl: '/quotation.pdf',
  extension: 'pdf',
  fileSize: 1258291,
};
const options = locale => ({
  global: {
    plugins: [
      createI18n({
        legacy: false,
        locale,
        messages: {
          en: { ...settingsEn, ...conversationEn },
          es: { ...settingsEs, ...conversationEs },
        },
      }),
    ],
    stubs: { GalleryView: true },
  },
});

describe('attachment file card', () => {
  it.each([
    ['es', 'PDF · 1,2 MB'],
    ['en', 'PDF · 1.2 MB'],
  ])('localizes the size in %s', (locale, label) => {
    const wrapper = mount(FileCard, {
      ...options(locale),
      props: { attachment: pdf },
    });
    expect(wrapper.text()).toContain(label);
  });

  it('preserves the extension and full title of long filenames', () => {
    const name = `${'Long quotation '.repeat(9)}final.pdf`;
    const wrapper = mount(FileCard, {
      ...options('en'),
      props: { attachment: { ...pdf, fileName: name } },
    });
    const label = wrapper.get('[title]');
    expect(label.attributes('title')).toBe(name);
    expect(label.text()).toHaveLength(48);
    expect(label.text()).toContain('…');
    expect(label.text()).toMatch(/final\.pdf$/);
    expect(wrapper.html()).not.toMatch(/#[0-9a-f]{6}/i);
  });

  it.each([
    ['pdf', 'application/pdf', 25 * 1024 * 1024, true],
    ['pdf', 'application/pdf', 30 * 1024 * 1024, false],
    ['pdf', 'text/html', 100, false],
    ['docx', 'application/octet-stream', 100, false],
    ['txt', 'text/plain', 100, false],
  ])(
    'limits preview for %s %s %s',
    (extension, contentType, fileSize, preview) => {
      const wrapper = mount(FileCard, {
        ...options('en'),
        props: { attachment: { ...pdf, extension, contentType, fileSize } },
      });
      expect(
        wrapper.findAll('button').some(button => button.text() === 'View')
      ).toBe(preview);
    }
  );

  it('opens the gallery for a PDF outside a selected conversation', async () => {
    const wrapper = mount(FileCard, {
      ...options('en'),
      props: { attachment: pdf },
    });
    await wrapper.get('button').trigger('click');
    expect(
      wrapper.getComponent({ name: 'GalleryView' }).props('allAttachments')
    ).toHaveLength(1);
  });

  it('downloads and opens the original in a new tab if downloading fails', async () => {
    const open = vi.spyOn(window, 'open').mockImplementation(() => null);
    downloadFile.mockRejectedValue(new Error('network'));
    const wrapper = mount(FileCard, {
      ...options('en'),
      props: { attachment: pdf },
    });
    await wrapper.get('button[aria-label="Download"]').trigger('click');
    await flushPromises();
    expect(downloadFile).toHaveBeenCalledWith({
      url: pdf.dataUrl,
      type: 'file',
      extension: 'pdf',
    });
    expect(open).toHaveBeenCalledWith(
      pdf.dataUrl,
      '_blank',
      'noopener,noreferrer'
    );
    open.mockRestore();
  });
});
