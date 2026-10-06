import { flushPromises, mount } from '@vue/test-utils';
import { defineComponent, h } from 'vue';
import {
  POLL_INTERVAL,
  buildRow,
  errorLines,
  useFlowPublications,
} from '../useFlowPublications';

const waba = { waba_id: '111', channel_id: 7, phone_number: '+593990000001' };
const status = (publications, wabas = [waba]) => ({
  data: { flow_id: 1, wabas, publications },
});

// The composable needs a component around it (it stops polling when that unmounts).
const setup = api => {
  let state;
  const wrapper = mount(
    defineComponent({
      setup() {
        state = useFlowPublications(api, () => 1);
        return () => h('div');
      },
    })
  );
  return { state, wrapper };
};

describe('buildRow', () => {
  it('is "none" for a WABA the flow never went to', () => {
    expect(buildRow(waba, undefined)).toMatchObject({
      wabaId: '111',
      channelId: 7,
      phoneNumber: '+593990000001',
      state: 'none',
      errors: [],
    });
  });

  it('takes the Meta status as the state', () => {
    expect(buildRow(waba, { status: 'published' }).state).toBe('published');
    expect(buildRow(waba, { status: 'draft' }).state).toBe('draft');
    expect(buildRow(waba, { status: 'throttled' }).state).toBe('throttled');
  });

  it('is an error when Meta gave errors, with the place and the message', () => {
    const row = buildRow(waba, {
      status: 'draft',
      validation_errors: [
        {
          error: 'INVALID_PROPERTY',
          message: 'bad value',
          pointers: [{ path: 'screens[0]' }],
        },
      ],
    });

    expect(row.state).toBe('error');
    expect(row.errors).toEqual([{ path: 'screens[0]', message: 'bad value' }]);
  });
});

describe('errorLines', () => {
  it('reads our own errors (path + code) and Meta messages alike', () => {
    expect(
      errorLines([
        { error: 'screen_title_required', path: 'screens.0.title' },
        { error: 'meta_error', message: 'Service unavailable' },
      ])
    ).toEqual([
      { path: 'screens.0.title', message: 'screen_title_required' },
      { path: '', message: 'Service unavailable' },
    ]);
  });
});

describe('useFlowPublications', () => {
  beforeEach(() => vi.useFakeTimers());
  afterEach(() => vi.useRealTimers());

  it('loads the WABAs and what Meta said about them', async () => {
    const api = {
      publicationStatus: vi
        .fn()
        .mockResolvedValue(
          status([{ waba_id: '111', status: 'published', meta_flow_id: 'm1' }])
        ),
    };
    const { state } = setup(api);

    await state.load();

    expect(state.hasCloud.value).toBe(true);
    expect(state.rows.value).toHaveLength(1);
    expect(state.rows.value[0]).toMatchObject({
      state: 'published',
      metaFlowId: 'm1',
    });
  });

  it('has nothing to show without a Cloud WABA', async () => {
    const { state } = setup({
      publicationStatus: vi.fn().mockResolvedValue(status([], [])),
    });

    await state.load();

    expect(state.hasCloud.value).toBe(false);
  });

  it('polls every 2 s after publishing until every WABA has its answer', async () => {
    const api = {
      publish: vi.fn().mockResolvedValue({}),
      publicationStatus: vi
        .fn()
        .mockResolvedValueOnce(status([]))
        .mockResolvedValueOnce(
          status([{ waba_id: '111', status: 'draft', validation_errors: [] }])
        )
        .mockResolvedValue(
          status([{ waba_id: '111', status: 'published', meta_flow_id: 'm1' }])
        ),
    };
    const { state } = setup(api);
    await state.load();
    api.publicationStatus.mockClear();

    await state.publish();
    expect(api.publish).toHaveBeenCalledWith(1);
    expect(state.isPublishing.value).toBe(true);

    await vi.advanceTimersByTimeAsync(POLL_INTERVAL);
    expect(state.isPublishing.value).toBe(true);
    await vi.advanceTimersByTimeAsync(POLL_INTERVAL);
    expect(state.rows.value[0].state).toBe('published');
    expect(state.isPublishing.value).toBe(false);

    await vi.advanceTimersByTimeAsync(POLL_INTERVAL * 3);
    expect(api.publicationStatus).toHaveBeenCalledTimes(2);
  });

  it('shows the errors Meta gave and stops', async () => {
    const errors = [{ error: 'X', message: 'bad value' }];
    const api = {
      publish: vi.fn().mockResolvedValue({}),
      publicationStatus: vi
        .fn()
        .mockResolvedValue(
          status([
            { waba_id: '111', status: 'draft', validation_errors: errors },
          ])
        ),
    };
    const { state } = setup(api);

    await state.publish();
    await vi.advanceTimersByTimeAsync(POLL_INTERVAL);

    expect(state.rows.value[0]).toMatchObject({ state: 'error' });
    expect(state.rows.value[0].errors[0].message).toBe('bad value');
    expect(state.isPublishing.value).toBe(false);
  });

  it('does not stop on the old published row while a new version is on its way', async () => {
    const old = {
      waba_id: '111',
      status: 'published',
      meta_flow_id: 'm1',
      published_at: 'before',
    };
    const api = {
      publish: vi.fn().mockResolvedValue({}),
      publicationStatus: vi
        .fn()
        .mockResolvedValueOnce(status([old]))
        .mockResolvedValueOnce(status([old]))
        .mockResolvedValue(
          status([{ ...old, meta_flow_id: 'm2', published_at: 'after' }])
        ),
    };
    const { state } = setup(api);
    await state.load();

    await state.publish();
    await vi.advanceTimersByTimeAsync(POLL_INTERVAL);
    expect(state.isPublishing.value).toBe(true);
    await vi.advanceTimersByTimeAsync(POLL_INTERVAL);

    expect(state.rows.value[0].metaFlowId).toBe('m2');
    expect(state.isPublishing.value).toBe(false);
  });

  it('accepts an unchanged published flow as the answer after a few polls', async () => {
    const same = { waba_id: '111', status: 'published', published_at: 'x' };
    const api = {
      publish: vi.fn().mockResolvedValue({}),
      publicationStatus: vi.fn().mockResolvedValue(status([same])),
    };
    const { state } = setup(api);
    await state.load();

    await state.publish();
    await vi.advanceTimersByTimeAsync(POLL_INTERVAL * 5);

    expect(state.isPublishing.value).toBe(false);
  });

  it('retries one WABA and follows it', async () => {
    const api = {
      retryPublication: vi.fn().mockResolvedValue({}),
      publicationStatus: vi.fn().mockResolvedValue(status([])),
    };
    const { state } = setup(api);

    await state.retry('111');

    expect(api.retryPublication).toHaveBeenCalledWith(1, '111');
    expect(state.isPublishing.value).toBe(true);
  });

  it('lets the caller see a refused publish and does not follow it', async () => {
    const api = {
      publish: vi.fn().mockRejectedValue(new Error('no')),
      publicationStatus: vi.fn(),
    };
    const { state } = setup(api);

    await expect(state.publish()).rejects.toThrow('no');
    expect(state.isPublishing.value).toBe(false);
  });

  it('stops polling when its component goes away', async () => {
    const api = {
      publish: vi.fn().mockResolvedValue({}),
      publicationStatus: vi.fn().mockResolvedValue(status([])),
    };
    const { state, wrapper } = setup(api);
    await state.publish();

    wrapper.unmount();
    await flushPromises();
    await vi.advanceTimersByTimeAsync(POLL_INTERVAL * 3);

    expect(api.publicationStatus).not.toHaveBeenCalled();
  });

  it('marks a failed load', async () => {
    const { state } = setup({
      publicationStatus: vi.fn().mockRejectedValue(new Error('x')),
    });

    expect(await state.load()).toBe(false);
    expect(state.loadFailed.value).toBe(true);
  });
});
