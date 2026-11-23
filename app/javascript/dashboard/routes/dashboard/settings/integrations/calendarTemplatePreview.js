// Keep these preview-only examples aligned with Calendar::TemplateDefinitions.
const EXAMPLES = {
  es: {
    nombre: 'María',
    cita: 'Consulta',
    fecha: '23/08/2026',
    hora: '10:00',
  },
  en: {
    nombre: 'Maria',
    cita: 'Consultation',
    fecha: '08/23/2026',
    hora: '10:00',
  },
};

export const fillExamples = (body, language) =>
  body.replace(
    /{{\s*(nombre|cita|fecha|hora)\s*}}/g,
    (_, variable) => EXAMPLES[language][variable]
  );
