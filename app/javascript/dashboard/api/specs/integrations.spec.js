import integrationAPI from '../integrations';
import ApiClient from '../ApiClient';

describe('#integrationAPI', () => {
  it('creates correct instance', () => {
    expect(integrationAPI).toBeInstanceOf(ApiClient);
    expect(integrationAPI).toHaveProperty('get');
    expect(integrationAPI).toHaveProperty('show');
    expect(integrationAPI).toHaveProperty('create');
    expect(integrationAPI).toHaveProperty('update');
    expect(integrationAPI).toHaveProperty('delete');
    expect(integrationAPI).toHaveProperty('connectSlack');
    expect(integrationAPI).toHaveProperty('updateSlack');
    expect(integrationAPI).toHaveProperty('updateSlack');
    expect(integrationAPI).toHaveProperty('listAllSlackChannels');
    expect(integrationAPI).toHaveProperty('deleteHook');
  });
  describe('API calls', () => {
    const originalAxios = window.axios;
    const axiosMock = {
      post: vi.fn(() => Promise.resolve()),
      get: vi.fn(() => Promise.resolve()),
      patch: vi.fn(() => Promise.resolve()),
      delete: vi.fn(() => Promise.resolve()),
    };

    beforeEach(() => {
      window.axios = axiosMock;
    });

    afterEach(() => {
      window.axios = originalAxios;
    });

    it('#connectSlack', () => {
      const code = 'SDNFJNSDFNDSJN';
      integrationAPI.connectSlack(code);
      expect(axiosMock.post).toHaveBeenCalledWith(
        '/api/v1/integrations/slack',
        {
          code,
        }
      );
    });

    it('#updateSlack', () => {
      const updateObj = { referenceId: 'SDFSDGSVE' };
      integrationAPI.updateSlack(updateObj);
      expect(axiosMock.patch).toHaveBeenCalledWith(
        '/api/v1/integrations/slack',
        {
          reference_id: updateObj.referenceId,
        }
      );
    });

    it('#listAllSlackChannels', () => {
      integrationAPI.listAllSlackChannels();
      expect(axiosMock.get).toHaveBeenCalledWith(
        '/api/v1/integrations/slack/list_all_channels'
      );
    });

    it('#delete', () => {
      integrationAPI.delete(2);
      expect(axiosMock.delete).toHaveBeenCalledWith('/api/v1/integrations/2');
    });

    it('#createHook', () => {
      const hookData = {
        app_id: 'fullcontact',
        settings: { api_key: 'SDFSDGSVE' },
      };
      integrationAPI.createHook(hookData);
      expect(axiosMock.post).toHaveBeenCalledWith(
        '/api/v1/integrations/hooks',
        hookData
      );
    });

    it('#deleteHook', () => {
      integrationAPI.deleteHook(2);
      expect(axiosMock.delete).toHaveBeenCalledWith(
        '/api/v1/integrations/hooks/2'
      );
    });

    it('#connectGoogleTranslate', () => {
      const credentials = { client_email: 'translator@example.com' };
      integrationAPI.connectGoogleTranslate({
        projectId: 'project-1',
        credentials,
      });

      expect(axiosMock.post).toHaveBeenCalledWith(
        '/api/v1/integrations/google_translate',
        { project_id: 'project-1', credentials }
      );
    });

    it('#disconnectGoogleTranslate', () => {
      integrationAPI.disconnectGoogleTranslate();

      expect(axiosMock.delete).toHaveBeenCalledWith(
        '/api/v1/integrations/google_translate'
      );
    });
  });
});
