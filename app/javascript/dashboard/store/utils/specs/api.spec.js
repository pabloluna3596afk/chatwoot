import {
  getLoadingStatus,
  parseAPIErrorResponse,
  setLoadingStatus,
  throwErrorMessage,
  parseLinearAPIErrorResponse,
} from '../api';

describe('#getLoadingStatus', () => {
  it('returns correct status', () => {
    expect(getLoadingStatus({ fetchAPIloadingStatus: true })).toBe(true);
  });
});

describe('#setLoadingStatus', () => {
  it('set correct status', () => {
    const state = { fetchAPIloadingStatus: true };
    setLoadingStatus(state, false);
    expect(state.fetchAPIloadingStatus).toBe(false);
  });
});

describe('#parseAPIErrorResponse', () => {
  it('returns correct values', () => {
    expect(
      parseAPIErrorResponse({
        response: { data: { message: 'Error Message [message]' } },
      })
    ).toBe('Error Message [message]');

    expect(
      parseAPIErrorResponse({
        response: { data: { error: 'Error Message [error]' } },
      })
    ).toBe('Error Message [error]');

    expect(
      parseAPIErrorResponse({
        response: { data: { errors: ['First error', 'Second error'] } },
      })
    ).toBe('First error');
  });

  it.each([
    undefined,
    null,
    'Error: 422 Failed',
    new Error('Network Error'),
    { response: { status: 500 } },
    { response: { data: '<html>Internal Server Error</html>' } },
    { response: { data: { message: {}, error: {}, errors: [] } } },
    { response: { data: { errors: { email: ['is invalid'] } } } },
    { response: { data: { message: ' ', errors: [{}] } } },
  ])('returns an empty message for the translated UI fallback: %j', error => {
    expect(parseAPIErrorResponse(error)).toBe('');
  });

  it('preserves a server captcha error for the UI to translate', () => {
    expect(
      parseAPIErrorResponse({
        response: { data: { error: 'Invalid Captcha' } },
      })
    ).toBe('Invalid Captcha');
  });
});

describe('#throwErrorMessage', () => {
  it('does not stringify transport errors or objects', () => {
    expect.assertions(2);
    try {
      throwErrorMessage(new Error('Request failed with status code 500'));
    } catch (error) {
      expect(error).toBeInstanceOf(Error);
      expect(error.message).toBe('');
    }
  });

  it('keeps the HTTP response so callers can detect a missing record', () => {
    expect.assertions(1);
    try {
      throwErrorMessage({ response: { status: 404, data: {} } });
    } catch (error) {
      expect(error.response.status).toBe(404);
    }
  });

  it('throws correct error', () => {
    const errorFn = function throwErrorMessageFn() {
      throwErrorMessage({
        response: { data: { message: 'Error Message [message]' } },
      });
    };
    expect(errorFn).toThrow('Error Message [message]');
  });
});

describe('#parseLinearAPIErrorResponse', () => {
  it('returns correct values', () => {
    expect(
      parseLinearAPIErrorResponse(
        {
          response: {
            data: {
              error: {
                errors: [
                  {
                    message: 'Error Message [message]',
                  },
                ],
              },
            },
          },
        },
        'Default Message'
      )
    ).toBe('Error Message [message]');
  });
});
