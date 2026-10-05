import {
  BLOCK_TYPES,
  PALETTE,
  STARTING_POINTS,
  conditionSources,
  defaultCondition,
  emptyDefinition,
  errorPlace,
  fieldsOf,
  groupErrors,
  isVisible,
  newBlock,
  newScreen,
  newOption,
  optionIdFor,
  slugify,
  startingDefinition,
  uniqueKey,
} from '../flowDefinition';

describe('naming', () => {
  it('turns what is typed into a name Meta accepts', () => {
    expect(slugify('Número de cédula')).toBe('numero_de_cedula');
    expect(slugify('  ¿Cuál otro?  ')).toBe('cual_otro');
    expect(slugify('1 dato')).toBe('dato');
    expect(slugify('')).toBe('');
    expect(slugify('a'.repeat(60))).toHaveLength(40);
  });

  it('finds the first name that is free', () => {
    expect(uniqueKey('Nombre', [])).toBe('nombre');
    expect(uniqueKey('Nombre', ['nombre'])).toBe('nombre_2');
    expect(uniqueKey('Nombre', ['nombre', 'nombre_2'])).toBe('nombre_3');
    expect(uniqueKey('', [])).toBe('campo');
  });

  it('gives an option its id from the title, apart from the ones the others have', () => {
    const block = {
      options: [
        { id: 'si', title: 'Sí' },
        { id: 'no', title: 'No' },
      ],
    };

    expect(optionIdFor('Quizás', block, 2)).toBe('quizas');
    expect(optionIdFor('Sí', block, 1)).toBe('si_2');
    expect(optionIdFor('Sí', block, 0)).toBe('si');
    expect(newOption(block).id).toBe('opcion');
  });
});

describe('new blocks', () => {
  it('creates a text block with no key and an answer with a free key', () => {
    expect(newBlock('heading')).toEqual({ type: 'heading', text: '' });

    const definition = {
      screens: [{ blocks: [{ type: 'short_text', key: 'short_text' }] }],
    };
    expect(newBlock('short_text', definition)).toMatchObject({
      type: 'short_text',
      key: 'short_text_2',
      input: 'text',
      required: false,
    });
  });

  it('starts choices with two options and files with one allowed', () => {
    expect(newBlock('radio').options).toHaveLength(2);
    expect(newBlock('photo').max_files).toBe(1);
    expect(newBlock('optin').key).toBe('acepto');
  });

  it('offers every kind of block the server knows', () => {
    expect(BLOCK_TYPES.map(item => item.type)).toEqual([
      'heading',
      'subheading',
      'text',
      'caption',
      'short_text',
      'long_text',
      'dropdown',
      'radio',
      'checkbox',
      'date',
      'optin',
      'photo',
      'document',
    ]);
  });
});

describe('conditions', () => {
  const definition = {
    screens: [
      {
        blocks: [
          {
            type: 'dropdown',
            key: 'tipo',
            options: [{ id: 'a', title: 'A' }],
          },
          { type: 'checkbox', key: 'temas', options: [] },
          { type: 'short_text', key: 'detalle' },
        ],
      },
      { blocks: [{ type: 'optin', key: 'acepto' }] },
    ],
  };

  it('lists the earlier single-value answers a block can look at', () => {
    expect(conditionSources(definition, 0, 2).map(field => field.key)).toEqual([
      'tipo',
    ]);
    expect(conditionSources(definition, 1, 0).map(field => field.key)).toEqual([
      'tipo',
      'detalle',
    ]);
  });

  it('starts a condition on the first option, or true for an opt-in', () => {
    const [tipo] = fieldsOf(definition);
    expect(defaultCondition(tipo)).toEqual({
      key: 'tipo',
      op: 'equals',
      value: 'a',
    });
    expect(defaultCondition(fieldsOf(definition)[3])).toEqual({
      key: 'acepto',
      op: 'equals',
      value: 'true',
    });
    expect(defaultCondition(null)).toBeNull();
  });

  it('shows a block unless its condition fails on the answers so far', () => {
    const block = {
      visible_when: { key: 'tipo', op: 'equals', value: 'otro' },
    };
    const negated = {
      visible_when: { key: 'tipo', op: 'not_equals', value: 'otro' },
    };

    expect(isVisible({}, {})).toBe(true);
    expect(isVisible(block, {})).toBe(false);
    expect(isVisible(block, { tipo: 'otro' })).toBe(true);
    expect(isVisible(negated, { tipo: 'otro' })).toBe(false);
    expect(isVisible(negated, {})).toBe(true);
    expect(
      isVisible(
        { visible_when: { key: 'acepto', op: 'equals', value: 'true' } },
        { acepto: true }
      )
    ).toBe(true);
  });
});

describe('starting points', () => {
  it('offers the five of Meta and falls back to a blank form', () => {
    expect(Object.keys(STARTING_POINTS)).toEqual([
      'blank',
      'interests',
      'feedback',
      'survey',
      'support',
    ]);
    expect(startingDefinition('nada').screens).toHaveLength(1);
    expect(startingDefinition('survey').screens).toHaveLength(2);
    expect(emptyDefinition()).toEqual({ schema_version: 1, screens: [] });
  });

  it('gives unique answer names and valid conditions in every starting point', () => {
    Object.keys(STARTING_POINTS).forEach(id => {
      const definition = startingDefinition(id);
      const keys = fieldsOf(definition).map(field => field.key);
      expect(new Set(keys).size).toBe(keys.length);
      definition.screens.forEach((screen, screenIndex) =>
        screen.blocks.forEach((block, blockIndex) => {
          if (!block.visible_when) return;
          expect(
            conditionSources(definition, screenIndex, blockIndex).map(
              field => field.key
            )
          ).toContain(block.visible_when.key);
        })
      );
    });
  });
});

describe('errors', () => {
  it('finds the screen and block of a path', () => {
    expect(errorPlace('screens.1.blocks.3.label')).toEqual({
      screen: 1,
      block: 3,
    });
    expect(errorPlace('screens.2.title')).toEqual({ screen: 2, block: null });
    expect(errorPlace('screens')).toEqual({ screen: null, block: null });
  });

  it('groups them by where they are', () => {
    const errors = [
      { code: 'screens_required', path: 'screens' },
      { code: 'screen_title_required', path: 'screens.0.title' },
      { code: 'label_required', path: 'screens.0.blocks.1.label' },
      { code: 'key_duplicate', path: 'screens.0.blocks.1.key' },
    ];

    const grouped = groupErrors(errors);

    expect(grouped.form).toHaveLength(1);
    expect(grouped.screen[0]).toHaveLength(1);
    expect(grouped.block['0.1']).toHaveLength(2);
  });

  describe('the builder palette', () => {
    const items = PALETTE.flatMap(group => group.items);

    it('groups the buttons as text, answers, options and files', () => {
      expect(PALETTE.map(group => group.group)).toEqual([
        'text',
        'answer',
        'options',
        'file',
      ]);
    });

    it('offers every block type of the definition', () => {
      const offered = new Set(items.map(item => item.type));
      BLOCK_TYPES.forEach(({ type }) => expect(offered.has(type)).toBe(true));
    });

    it('turns email, phone and number into a short text of that kind', () => {
      ['email', 'phone', 'number'].forEach(id => {
        const item = items.find(entry => entry.id === id);
        expect(item).toMatchObject({ type: 'short_text', input: id });
      });
    });
  });
});

describe('default screen titles', () => {
  it('names the blank start and new screens by position, never "Formulario"', () => {
    expect(STARTING_POINTS.blank().screens[0].title).toBe('Pantalla 1');
    expect(newScreen(3).title).toBe('Pantalla 3');
  });
});
