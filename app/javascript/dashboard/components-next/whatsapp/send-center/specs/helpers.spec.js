import {
  flowReason,
  templateReason,
  supportsFlows,
  sendCenterIcon,
  usesContentTemplates,
} from '../helpers';

describe('send center eligibility', () => {
  it.each(['PENDING', 'REJECTED', 'PAUSED', 'DISABLED'])(
    'keeps %s templates visible with a stable reason',
    status => expect(templateReason({ status })).toBe(`template_${status}`)
  );
  it('keeps Authentication, CSAT and unsupported approved templates blocked', () => {
    expect(
      templateReason({ status: 'APPROVED', category: 'AUTHENTICATION' })
    ).toBe('authentication');
    expect(
      templateReason({
        status: 'APPROVED',
        name: 'customer_satisfaction_survey_1',
      })
    ).toBe('csat');
    expect(
      templateReason({ status: 'APPROVED', components: [{ type: 'CATALOG' }] })
    ).toBe('unsupported');
    expect(
      templateReason({
        status: 'APPROVED',
        components: [{ type: 'BODY', text: 'Hello' }],
      })
    ).toBe('');
  });
  it.each([
    [{ status: 'none' }, true, 'no_publication'],
    [{ status: 'draft' }, true, 'flow_draft'],
    [{ status: 'published', unpublished_changes: true }, true, 'changes'],
    [{ status: 'published', can_send: false }, false, 'outside_window'],
    [{ status: 'published', can_send: true }, true, ''],
    [{ status: 'blocked' }, true, 'flow_blocked'],
    [{ status: 'deprecated' }, true, 'flow_deprecated'],
    [{ status: 'throttled' }, true, 'flow_throttled'],
  ])('explains Flow %j with window %s', (flow, canReply, reason) => {
    expect(flowReason(flow, canReply)).toBe(reason);
  });
  it('shows WhatsApp icons for Cloud/360dialog/Twilio and a template icon for API', () => {
    const cloud = {
      channel_type: 'Channel::Whatsapp',
      provider: 'whatsapp_cloud',
    };
    const dialog = { channel_type: 'Channel::Whatsapp', provider: 'default' };
    const twilio = { channel_type: 'Channel::TwilioSms', medium: 'whatsapp' };
    expect(supportsFlows(cloud)).toBe(true);
    expect(supportsFlows(dialog)).toBe(false);
    expect(supportsFlows(twilio)).toBe(false);
    expect(usesContentTemplates(twilio)).toBe(true);
    [cloud, dialog, twilio].forEach(inbox =>
      expect(sendCenterIcon(inbox)).toBe('i-ph-whatsapp-logo')
    );
    expect(sendCenterIcon({ channel_type: 'Channel::Api' })).toBe(
      'i-lucide-layout-template'
    );
  });
});
