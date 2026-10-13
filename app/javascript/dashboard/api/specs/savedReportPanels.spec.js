import SavedReportPanelsAPI from '../savedReportPanels';

describe('saved report panels preview', () => {
  afterEach(() => vi.unstubAllGlobals());

  it('posts the draft configuration to the collection preview with request cancellation', async () => {
    const post = vi.fn().mockResolvedValue({ data: { panel_id: null } });
    vi.stubGlobal('axios', { post });
    const params = { saved_report_panel: { name: '', widgets: [] } };
    const signal = new AbortController().signal;

    const response = await SavedReportPanelsAPI.preview(params, { signal });

    expect(post).toHaveBeenCalledWith(
      `${SavedReportPanelsAPI.url}/preview`,
      params,
      { signal }
    );
    expect(response.data.panel_id).toBeNull();
  });
});
