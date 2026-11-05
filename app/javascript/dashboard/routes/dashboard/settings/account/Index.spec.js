import { readFileSync } from 'node:fs';

describe('General account settings page', () => {
  it('does not register the audio transcription setting', () => {
    const source = readFileSync(
      'app/javascript/dashboard/routes/dashboard/settings/account/Index.vue',
      'utf8'
    );

    expect(source).not.toContain('AudioTranscription');
  });
});
