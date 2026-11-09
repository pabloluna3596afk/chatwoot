import documentStore from './document';
import API from 'dashboard/api/captain/document';

vi.mock('dashboard/api/captain/document', () => ({
  default: { estimate: vi.fn(), resume: vi.fn() },
}));

it('returns the estimate API payload without calculating units on the client', async () => {
  const data = new FormData();
  data.append('external_link', 'https://example.com/help');
  API.estimate.mockResolvedValue({
    data: { units: 2, remaining: 7, sufficient: true },
  });
  expect(await documentStore.actions.estimate({}, data)).toEqual({
    units: 2,
    remaining: 7,
    sufficient: true,
  });
  expect(API.estimate).toHaveBeenCalledWith(data);
});

it('clears the pending warning only after the server accepts resume', async () => {
  const record = {
    id: 42,
    status: 'in_progress',
    quota_exceeded: true,
    last_sync_error_code: 'usage_quota_exceeded',
  };
  const commit = vi.fn();
  await documentStore.actions.resume(
    { commit, getters: { getRecords: [record] } },
    42
  );
  expect(API.resume).toHaveBeenCalledWith(42);
  expect(commit).toHaveBeenCalledWith(expect.any(String), [
    { ...record, quota_exceeded: false, last_sync_error_code: null },
  ]);
});

it('preserves the pending state and propagates the server error on resume failure', async () => {
  const commit = vi.fn();
  API.resume.mockRejectedValue({
    response: { data: { error: 'Not enough internal actions' } },
  });
  await expect(documentStore.actions.resume({ commit }, 42)).rejects.toThrow(
    'Not enough internal actions'
  );
  expect(commit).not.toHaveBeenCalled();
});
