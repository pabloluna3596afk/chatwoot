import {
  flowReason,
  templateReason,
  supportsFlows,
  sendCenterIcon,
  usesContentTemplates,
  bodySegments,
  templateFieldLabel,
} from '../helpers';

describe('body presentation', () => {
  it('keeps text, whitespace, repeats and named variables in reading order', () => {
    expect(bodySegments('Hola {{ nombre }}\n{{1}} / {{nombre}}')).toEqual([
      { text: 'Hola ' },
      { key: 'nombre' },
      { text: '\n' },
      { key: '1' },
      { text: ' / ' },
      { key: 'nombre' },
      { text: '' },
    ]);
  });
  it('uses catalog labels for names and saved numeric bindings', () => {
    const bindings = [
      { name: 'nombre', key: 'contact.name', label: 'Nombre del cliente' },
    ];
    expect(templateFieldLabel('nombre', 0, bindings, {}, vi.fn())).toBe(
      'Nombre del cliente'
    );
    expect(
      templateFieldLabel('1', 0, bindings, { 1: 'contact.name' }, vi.fn())
    ).toBe('Nombre del cliente');
    const translate = vi.fn(() => 'Dato 2');
    expect(templateFieldLabel('2', 1, [], {}, translate)).toBe('Dato 2');
    expect(translate).toHaveBeenCalledWith(
      'WHATSAPP_TEMPLATES.SEND_CENTER.DATA',
      { index: 2 }
    );
    expect(templateFieldLabel('fecha_cita', 0, [], {}, translate)).toBe(
      'fecha cita'
    );
  });
});

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
      expect(sendCenterIcon(inbox)).toBe('i-woot-whatsapp')
    );
    expect(sendCenterIcon({ channel_type: 'Channel::Api' })).toBe(
      'i-lucide-layout-template'
    );
  });
});
