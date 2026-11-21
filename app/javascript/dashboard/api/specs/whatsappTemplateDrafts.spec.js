/* global axios */
import DraftsAPI from '../whatsappTemplateDrafts';

describe('WhatsApp draft API contract', () => {
  const base = '/api/v1/accounts/1/whatsapp_template_drafts';
  beforeEach(() => {
    window.history.replaceState({}, '', '/app/accounts/1/settings/templates');
    global.axios = {
      get: vi.fn(),
      post: vi.fn(),
      patch: vi.fn(),
      delete: vi.fn(),
    };
  });

  it('loads account-scoped pages and detail', () => {
    const signal = new AbortController().signal;
    DraftsAPI.get({ page: '2', per_page: '100' }, { signal });
    expect(axios.get).toHaveBeenCalledWith(base, {
      params: { page: '2', per_page: '100' },
      signal,
    });
    DraftsAPI.show(31);
    expect(axios.get).toHaveBeenLastCalledWith(`${base}/31`);
  });

  it('wraps local create/update and preserves integer revisions', () => {
    DraftsAPI.create({ definition: {} });
    expect(axios.post).toHaveBeenCalledWith(base, {
      draft: { definition: {} },
    });
    DraftsAPI.update(31, { lock_version: 2, name: 'example' });
    expect(axios.patch).toHaveBeenCalledWith(`${base}/31`, {
      draft: { lock_version: 2, name: 'example' },
    });
    DraftsAPI.delete(31, 3);
    expect(axios.delete).toHaveBeenCalledWith(`${base}/31`, {
      data: { lock_version: 3 },
    });
  });

  it('uploads local media as multipart with a decimal string revision', () => {
    const file = new File(['image'], 'photo.png', { type: 'image/png' });
    DraftsAPI.uploadMedia(31, 2, file);
    const [url, body] = axios.post.mock.calls[0];
    expect(url).toBe(`${base}/31/media`);
    expect(body.get('file')).toBe(file);
    expect(body.get('lock_version')).toBe('2');
    DraftsAPI.downloadMedia(31);
    expect(axios.get).toHaveBeenCalledWith(`${base}/31/media`, {
      responseType: 'blob',
    });
    DraftsAPI.removeMedia(31, 3);
    expect(axios.delete).toHaveBeenCalledWith(`${base}/31/media`, {
      data: { lock_version: 3 },
    });
  });

  it('uses explicit submission, verification and server copy endpoints', () => {
    DraftsAPI.submit(31, 4);
    expect(axios.post).toHaveBeenCalledWith(`${base}/31/submit`, {
      lock_version: 4,
    });
    DraftsAPI.reconcile(31, 99);
    expect(axios.post).toHaveBeenCalledWith(
      `${base}/31/submissions/99/reconcile`
    );
    DraftsAPI.newVersion(70, 'meta-1');
    expect(axios.post).toHaveBeenCalledWith(`${base}/new_version`, {
      channel_id: 70,
      remote_id: 'meta-1',
    });
    DraftsAPI.duplicate(31, { preferred_channel_id: 80, waba_id: 'waba-b' });
    expect(axios.post).toHaveBeenCalledWith(`${base}/31/duplicate`, {
      destination: { preferred_channel_id: 80, waba_id: 'waba-b' },
    });
  });
});
