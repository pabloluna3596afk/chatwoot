import { permissionErrorMessage } from './permissionErrorMessage';

describe('permissionErrorMessage', () => {
  const t = key => key;

  it.each([401, 403])(
    'uses the translated permission message for %s',
    status => {
      expect(
        permissionErrorMessage(
          { response: { status } },
          t('CAPTAIN.ASSISTANTS.EDIT.NO_PERMISSION'),
          t('fallback')
        )
      ).toBe('CAPTAIN.ASSISTANTS.EDIT.NO_PERMISSION');
    }
  );

  it('keeps the existing server message for other errors', () => {
    expect(
      permissionErrorMessage(
        { response: { status: 422 }, message: 'Invalid setting' },
        t('CAPTAIN.ASSISTANTS.EDIT.NO_PERMISSION'),
        t('fallback')
      )
    ).toBe('Invalid setting');
  });

  it('uses the current fallback when a network error has no message', () => {
    expect(
      permissionErrorMessage(
        {},
        t('CAPTAIN.ASSISTANTS.EDIT.NO_PERMISSION'),
        t('fallback')
      )
    ).toBe('fallback');
  });
});
