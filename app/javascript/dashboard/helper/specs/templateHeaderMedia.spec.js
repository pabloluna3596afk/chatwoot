import {
  headerMediaAccept,
  headerMediaMaxMegabytes,
  validateHeaderMediaFile,
  withoutUploadedMedia,
} from '../templateHeaderMedia';

const file = (type, size) => ({ type, size });

describe('templateHeaderMedia', () => {
  it('knows what each header accepts', () => {
    expect(headerMediaAccept('IMAGE')).toBe('image/jpeg,image/png');
    expect(headerMediaAccept('document')).toBe('application/pdf');
    expect(headerMediaMaxMegabytes('IMAGE')).toBe(5);
    expect(headerMediaMaxMegabytes('VIDEO')).toBe(16);
    expect(headerMediaMaxMegabytes('DOCUMENT')).toBe(100);
  });

  it('validates type and size per format', () => {
    expect(
      validateHeaderMediaFile('IMAGE', file('image/png', 1000))
    ).toBeNull();
    expect(validateHeaderMediaFile('IMAGE', file('image/gif', 1000))).toBe(
      'INVALID_TYPE'
    );
    expect(
      validateHeaderMediaFile('IMAGE', file('image/png', 5 * 1024 * 1024 + 1))
    ).toBe('TOO_LARGE');
    expect(
      validateHeaderMediaFile('VIDEO', file('video/mp4', 16 * 1024 * 1024))
    ).toBeNull();
    expect(
      validateHeaderMediaFile('DOCUMENT', file('application/msword', 10))
    ).toBe('INVALID_TYPE');
    expect(validateHeaderMediaFile('IMAGE', file('image/png', 0))).toBe(
      'EMPTY'
    );
  });

  it('removes only the uploaded file keys', () => {
    expect(
      withoutUploadedMedia({
        media_id: '1',
        media_blob: 'b',
        media_uploaded_at: 't',
        media_phone_number_id: 'p',
        media_url: 'u',
        media_type: 'image',
      })
    ).toEqual({ media_url: 'u', media_type: 'image' });
  });
});
