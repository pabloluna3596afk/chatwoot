import { mount } from '@vue/test-utils';
import { createStore } from 'vuex';
import backgroundTasks from 'dashboard/store/modules/backgroundTasks';
import DraftsAPI from 'dashboard/api/whatsappTemplateDrafts';
import { useTemplateDraft } from '../useTemplateDraft';

vi.mock('dashboard/api/whatsappTemplateDrafts', () => ({
  default: { show: vi.fn(), submit: vi.fn() },
}));

describe('template background tasks', () => {
  let store;
  let session;
  let wrapper;
  const submission = {
    id: 42,
    name: 'welcome',
    status: 'submitting',
    revision: 0,
  };
  const draft = { id: 7, lock_version: 0, submissions: [] };
  beforeEach(() => {
    store = createStore({
      modules: { backgroundTasks },
      getters: { getCurrentAccountId: () => 1 },
    });
    wrapper = mount(
      {
        setup() {
          session = useTemplateDraft();
          return {};
        },
        template: '<div />',
      },
      { global: { plugins: [store] } }
    );
  });
  afterEach(() => {
    wrapper.unmount();
    store.dispatch('backgroundTasks/reset');
  });

  it('registers the returned submission id before the following reload finishes', async () => {
    DraftsAPI.show.mockResolvedValueOnce({ data: draft });
    await session.load(7);
    DraftsAPI.submit.mockResolvedValue({ data: submission });
    let finish;
    DraftsAPI.show.mockImplementationOnce(
      () =>
        new Promise(resolve => {
          finish = resolve;
        })
    );
    const pending = session.submit();
    await Promise.resolve();
    expect(
      store.state.backgroundTasks.tasks['whatsapp_template_submission:42']
    ).toMatchObject({ status: 'running', title: 'welcome' });
    finish({ data: { ...draft, submissions: [submission] } });
    await pending;
    expect(store.getters['backgroundTasks/ordered']).toHaveLength(1);
    expect(DraftsAPI.submit).toHaveBeenCalledWith(7, 0);
  });

  it('restores pending submissions on reload, excluding final or failed attempts', async () => {
    DraftsAPI.show.mockResolvedValue({
      data: {
        ...draft,
        submissions: [
          { ...submission, status: 'submitted', remote_status: 'PENDING' },
          {
            ...submission,
            id: 43,
            status: 'submitted',
            remote_status: 'APPROVED',
          },
          { ...submission, id: 44, status: 'failed' },
          {
            ...submission,
            id: 45,
            status: 'submitted',
            remote_status: 'REJECTED',
          },
        ],
      },
    });
    await session.load(7);
    expect(store.getters['backgroundTasks/ordered']).toHaveLength(1);
    expect(store.getters['backgroundTasks/ordered'][0].detail).toBe(
      'BACKGROUND_TASKS.REVIEW'
    );
  });

  it('does not register a task when the submit request is denied', async () => {
    DraftsAPI.show.mockResolvedValue({ data: draft });
    await session.load(7);
    DraftsAPI.submit.mockRejectedValue({ response: { status: 403 } });
    await expect(session.submit()).rejects.toMatchObject({
      response: { status: 403 },
    });
    expect(store.getters['backgroundTasks/ordered']).toEqual([]);
  });
});
