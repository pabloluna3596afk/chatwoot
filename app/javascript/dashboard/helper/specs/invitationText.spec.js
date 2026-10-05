import {
  INVITATION_TOKENS,
  dayText,
  invitationValues,
  renderInvitation,
  sampleValues,
  unknownTokens,
} from '../invitationText';

describe('renderInvitation', () => {
  it('fills the variables in, with or without spaces inside the braces', () => {
    expect(
      renderInvitation('Hola {{nombre}} y {{ agente }}', {
        nombre: 'Ana',
        agente: 'Pablo',
      })
    ).toBe('Hola Ana y Pablo');
  });

  it('leaves what is not a known variable as it was typed', () => {
    expect(
      renderInvitation('Hola {{nobre}} {{nombre}}', { nombre: 'Ana' })
    ).toBe('Hola {{nobre}} Ana');
  });

  it('leaves out a line whose variables are all empty and keeps one with some value', () => {
    const template =
      'Fecha: {{fecha}}\nLugar: {{direccion}}\nVideollamada: {{enlace_meet}}\n{{fecha}} {{direccion}}';

    expect(
      renderInvitation(template, {
        fecha: 'jueves',
        direccion: '',
        enlace_meet: '',
      })
    ).toBe('Fecha: jueves\njueves');
  });

  it('does not leave more than one blank line', () => {
    expect(renderInvitation('Hola\n\n\n{{direccion}}\n\n\nAdiós\n', {})).toBe(
      'Hola\n\nAdiós'
    );
  });
});

describe('unknownTokens', () => {
  it('lists the variables that do not exist, once each', () => {
    expect(unknownTokens('{{nombre}} {{nobre}} {{nobre}} {{x}}')).toEqual([
      'nobre',
      'x',
    ]);
    expect(unknownTokens('')).toEqual([]);
  });

  it('knows the variables the server knows', () => {
    expect(INVITATION_TOKENS).toEqual([
      'nombre',
      'primer_nombre',
      'telefono',
      'correo',
      'agente',
      'empresa',
      'fecha',
      'hora',
      'motivo',
      'direccion',
      'enlace_meet',
      'conversacion',
    ]);
  });
});

describe('dayText', () => {
  it('writes the day the way the server does, in Spanish and in English', () => {
    expect(dayText('2030-01-17', 'es')).toBe('jueves 17 de enero');
    expect(dayText('2030-01-17', 'en')).toBe('Thursday, January 17');
    expect(dayText('', 'es')).toBe('');
  });
});

describe('invitationValues', () => {
  it('gives each variable its value from what the modal knows', () => {
    const values = invitationValues({
      contactName: 'ana pérez',
      contactEmail: 'ana@example.com',
      agentName: 'Pablo',
      accountName: 'Clínica Sol',
      date: '2030-01-15',
      time: '10:00',
      summary: 'Consulta',
      location: 'Av. Sol 1',
      conversationId: 42,
    });

    expect(values).toMatchObject({
      nombre: 'ana pérez',
      primer_nombre: 'Ana',
      correo: 'ana@example.com',
      agente: 'Pablo',
      empresa: 'Clínica Sol',
      fecha: 'martes 15 de enero',
      hora: '10:00',
      motivo: 'Consulta',
      direccion: 'Av. Sol 1',
      enlace_meet: '',
      conversacion: '#42',
    });
  });

  it('is all empty for an appointment that has nothing yet', () => {
    expect(
      Object.values(invitationValues({})).every(value => value === '')
    ).toBe(true);
  });

  it('makes up values for the settings preview', () => {
    const text = renderInvitation(
      '{{primer_nombre}} / {{agente}} / {{hora}} / {{direccion}}',
      sampleValues('es', 'Av. Sol 1')
    );

    expect(text).toBe('Ana / Aurora / 10:30 / Av. Sol 1');
  });
});
