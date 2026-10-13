require 'rails_helper'

# These scenarios build a whole account (agents, inboxes, contacts, events) and check many numbers of one run, so they
# keep many memoized helpers and expectations per example.
# rubocop:disable RSpec/MultipleExpectations, RSpec/MultipleMemoizedHelpers, Performance/CollectionLiteralInLoop

RSpec.describe Reports::PanelRunnerService do
  let(:account) { create(:account, reporting_timezone: 'UTC') }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:inbox) { create(:inbox, account: account) }
  let(:since_time) { Time.utc(2026, 10, 5) }
  let(:until_time) { Time.utc(2026, 10, 11, 23, 59, 59) }
  let(:panel) { build(:saved_report_panel, account: account, created_by: admin, widgets: widgets, filters: filters) }
  let(:filters) { [] }
  let(:runner) do
    described_class.new(panel: panel, account: account, user: admin, date_overrides: { since: since_time.to_i, until: until_time.to_i })
  end
  let(:result) { runner.perform[:widgets].first.with_indifferent_access }

  describe 'date boundaries' do
    let(:widgets) { [{ id: 'count', type: 'metric', metric: 'conversations_count' }] }

    it 'counts the first and final second of a seven-day preset, excluding the previous day' do
      account.update!(reporting_timezone: 'America/Guayaquil')
      times = [Time.utc(2026, 10, 5, 4, 59, 59), Time.utc(2026, 10, 5, 5),
               Time.utc(2026, 10, 12, 4, 59, 59), Time.utc(2026, 10, 12, 4, 59, 59) + 0.5]
      times.each do |created_at|
        create(:conversation, account: account, inbox: inbox, created_at: created_at)
      end
      travel_to Time.utc(2026, 10, 12, 2) do
        report = described_class.new(panel: panel, account: account, user: admin).perform
        expect(report[:since]).to eq(Time.utc(2026, 10, 5, 5).to_i)
        expect(report[:until]).to eq(Time.utc(2026, 10, 12, 4, 59, 59).to_i)
        expect(report[:widgets].first[:value]).to eq(3)
        panel.filters = [{ attribute_key: 'inbox_id', filter_operator: 'equal_to', values: [inbox.id] }]
        filtered_report = described_class.new(panel: panel, account: account, user: admin).perform
        expect(filtered_report[:widgets].first[:value]).to eq(3)
      end
    end

    it 'rejects a partial override before executing widgets' do
      service = described_class.new(panel: panel, account: account, user: admin, date_overrides: { since: since_time.to_i })
      expect { service.perform }.to(raise_error { |error| expect(error.class.name).to eq('CustomExceptions::InvalidReportDateRange') })
    end

    it 'rejects explicit null overrides rather than using the saved preset' do
      service = described_class.new(panel: panel, account: account, user: admin, date_overrides: { since: nil, until: nil })
      expect { service.perform }.to(raise_error { |error| expect(error.class.name).to eq('CustomExceptions::InvalidReportDateRange') })
    end
  end

  describe 'contact pivot measures (D5)' do
    let(:measures) { %w[contact_ca:amount__sum contact_ca:amount__avg contact_ca:status__count contact_ca:score__sum] }
    let(:widgets) do
      [{ id: 'pivot', type: 'table', table_kind: 'pivot', columns: ['name'] + measures,
         pivot: { row_attribute: 'inbox', column_attribute: 'ca:segment', column_values: %w[A B] } }]
    end

    it 'deduplicates each measure independently within each bucket' do
      create(:custom_attribute_definition, account: account, attribute_key: 'segment', attribute_model: :conversation_attribute)
      contact = create(:contact, account: account, custom_attributes: { amount: 100, status: 'active', score: 7 })
      %w[A A B].each do |segment|
        create(:conversation, account: account, inbox: inbox, contact: contact, created_at: since_time,
                              custom_attributes: { segment: segment })
      end

      expect(result[:error]).to be_nil
      row = result[:rows].find { |item| item[:id] == inbox.id }
      %w[A B].each do |segment|
        expect(row["contact_ca:amount__sum__pv__#{segment}"]).to eq(100)
        expect(row["contact_ca:amount__avg__pv__#{segment}"]).to eq(100)
        expect(row["contact_ca:status__count__pv__#{segment}"]).to eq(1)
        expect(row["contact_ca:score__sum__pv__#{segment}"]).to eq(7)
      end
    end
  end

  describe 'pivot totals (D6)' do
    let(:other_inbox) { create(:inbox, account: account) }
    let(:widgets) do
      [{ id: 'pivot', type: 'table', table_kind: 'pivot', columns: %w[name ca:amount__avg ca:amount__min ca:amount__max],
         pivot: { row_attribute: 'inbox', column_attribute: 'ca:segment', column_values: %w[A B Empty] } }]
    end

    before do
      create(:custom_attribute_definition, account: account, attribute_key: 'segment', attribute_model: :conversation_attribute)
      [[inbox, 'A', 10], [inbox, 'A', 10], [inbox, 'A', 10], [inbox, 'B', 100], [other_inbox, 'A', 50]].each do |box, segment, amount|
        create(:conversation, account: account, inbox: box, created_at: since_time, custom_attributes: { segment: segment, amount: amount })
      end
    end

    it 'combines raw values for row, column and grand averages and ignores empty cells' do
      expect(result[:error]).to be_nil
      row = result[:rows].find { |item| item[:id] == inbox.id }
      expect(row['ca:amount__avg__pv__A']).to eq(10)
      expect(row['ca:amount__avg__pv__B']).to eq(100)
      expect(row['ca:amount__avg']).to eq(32.5)
      expect(row['ca:amount__min']).to eq(10)
      expect(row['ca:amount__max']).to eq(100)
      expect(result[:totals][:columns]['ca:amount__avg__pv__A']).to eq(20)
      expect(result[:totals][:columns]['ca:amount__avg__pv__B']).to eq(100)
      expect(result[:totals][:columns]['ca:amount__avg']).to eq(36)
      expect(result[:totals][:columns]['ca:amount__min']).to eq(10)
      expect(result[:totals][:columns]['ca:amount__max']).to eq(100)
      %w[avg min max].each do |op|
        expect(row["ca:amount__#{op}__pv__Empty"]).to be_nil
        expect(result[:totals][:columns]["ca:amount__#{op}__pv__Empty"]).to be_nil
      end
    end
  end

  describe 'distinct resolution conversations (D7)' do
    let(:agent) { create(:user, account: account, role: :agent) }
    let(:team) { create(:team, account: account) }
    let(:label) { create(:label, account: account, title: 'sales') }
    let(:old_conversation) do
      create(:conversation, account: account, inbox: inbox, team: team, assignee: agent, created_at: since_time - 30.days,
                            custom_attributes: { segment: 'A' })
    end
    let(:current_conversation) do
      create(:conversation, account: account, inbox: inbox, team: team, assignee: agent, created_at: since_time,
                            custom_attributes: { segment: 'A' })
    end

    before do
      create(:team_member, team: team, user: agent)
      create(:custom_attribute_definition, account: account, attribute_key: 'segment', attribute_model: :conversation_attribute)
      [old_conversation, current_conversation].each do |conversation|
        conversation.add_labels([label.title])
        2.times do
          create(:reporting_event, account: account, inbox: inbox, conversation: conversation, user: agent,
                                   name: 'conversation_resolved', created_at: since_time + 1.hour)
        end
      end
      no_event = create(:conversation, account: account, inbox: inbox, team: team, assignee: agent,
                                       status: :resolved, created_at: since_time, custom_attributes: { segment: 'A' })
      no_event.add_labels([label.title])
      create(:reporting_event, account: account, inbox: inbox, conversation: no_event, user: agent,
                               name: 'conversation_resolved', created_at: since_time - 1.second)
      create(:reporting_event, account: account, inbox: inbox, conversation: no_event, user: agent,
                               name: 'conversation_resolved', created_at: until_time + 1.second)
    end

    context 'when two agents resolve the same conversation' do
      let(:widgets) do
        [{ id: 'agents', type: 'table', table_kind: 'pivot', columns: %w[name resolved_conversations_count],
           pivot: { row_attribute: 'agent', column_attribute: 'ca:segment', column_values: ['A'] } }]
      end

      it 'counts the conversation once in the pivot footer while crediting both actors in their rows' do
        other_actor = create(:user, account: account, role: :agent)
        create(:reporting_event, account: account, inbox: inbox, conversation: old_conversation, user: other_actor,
                                 name: 'conversation_resolved', created_at: since_time + 2.hours)

        expect(result[:error]).to be_nil
        expect(result[:rows].sum { |row| row['resolved_conversations_count'] }).to eq(3)
        expect(result[:totals][:columns]['resolved_conversations_count']).to eq(2)
        expect(result[:totals][:columns]['resolved_conversations_count__pv__A']).to eq(2)
      end
    end

    [false, true].each do |filtered|
      context "with #{filtered ? 'an inbox filter' : 'no filters'}" do
        let(:filters) do
          filtered ? [{ attribute_key: 'inbox_id', filter_operator: 'equal_to', values: [inbox.id], query_operator: nil }] : []
        end

        context 'with a resolution KPI and chart' do
          let(:widgets) do
            [{ id: 'kpi', type: 'metric', metric: 'resolutions_count' },
             { id: 'chart', type: 'chart', metric: 'resolutions_count', group_by: 'day' }]
          end
          let(:normal_report_params) do
            {
              type: :account, metric: 'resolutions_count', group_by: 'day', timezone_offset: 0,
              since: since_time.to_i.to_s, until: (until_time.to_i + 1).to_s,
              business_hours: false
            }
          end

          it 'counts two conversations rather than four events, including the old reopened conversation' do
            expect(V2::ReportBuilder).not_to receive(:new)
            report = runner.perform
            expect(report[:widgets].map { |widget| widget[:error] }).to eq([nil, nil])
            expect(report[:widgets][0][:value]).to eq(2)
            expect(report[:widgets][1][:points].sum { |point| point[:value] }).to eq(2)
          end

          it 'keeps normal reports counting four resolution events while panels count two conversations' do
            normal_report = V2::ReportBuilder.new(account, normal_report_params)

            expect(normal_report.summary[:resolutions_count]).to eq(4)
            expect(normal_report.build.sum { |point| point[:value] }).to eq(4)
            expect(result[:value]).to eq(2)
          end
        end

        %w[agent inbox team label].each do |dimension|
          [false, true].each do |pivot|
            context "with #{dimension} #{pivot ? 'crossed' : 'uncrossed'} rows" do
              let(:widgets) do
                widget = { id: 'table', type: 'table', table_kind: 'pivot', pivot: { row_attribute: dimension },
                           columns: %w[name conversations_count resolved_conversations_count] }
                widget[:pivot] = { row_attribute: dimension, column_attribute: 'ca:segment', column_values: ['A'] } if pivot
                [widget]
              end

              it 'reports two distinct event-period conversations regardless of their current status' do
                expect(result[:error]).to be_nil
                expect(result[:rows].sum { |row| row['resolved_conversations_count'] }).to eq(2)
                expect(result[:rows].sum { |row| row['resolved_conversations_count__pv__A'] }).to eq(2) if pivot
              end
            end
          end
        end
      end
    end

    %w[account agent inbox team label].each do |scope_type|
      context "with unfiltered #{scope_type} resolution widgets" do
        let(:scope_ids) { { 'agent' => agent.id, 'inbox' => inbox.id, 'team' => team.id, 'label' => label.id } }
        let(:widgets) do
          [{ id: 'kpi', type: 'metric', metric: 'resolutions_count', scope_type: scope_type, scope_id: scope_ids[scope_type] },
           { id: 'chart', type: 'chart', metric: 'resolutions_count', scope_type: scope_type, scope_id: scope_ids[scope_type] }]
        end

        it 'preserves the selected scope while counting distinct conversations in the period' do
          other_actor = create(:user, account: account, role: :agent)
          other_inbox = create(:inbox, account: account)
          other_conversation = create(:conversation, account: account, inbox: other_inbox, assignee: other_actor, created_at: since_time - 30.days)
          create(:reporting_event, account: account, inbox: other_inbox, conversation: other_conversation, user: other_actor,
                                   name: 'conversation_resolved', created_at: since_time + 1.hour)

          report = runner.perform
          expected_count = scope_type == 'account' ? 3 : 2
          expect(report[:widgets].map { |widget| widget[:error] }).to eq([nil, nil])
          expect(report[:widgets][0][:value]).to eq(expected_count)
          expect(report[:widgets][1][:points].sum { |point| point[:value] }).to eq(expected_count)
        end
      end
    end
  end

  describe 'event agent attribution (D8)' do
    let(:actor) { create(:user, account: account, role: :agent) }
    let(:assignee) { create(:user, account: account, role: :agent) }
    let(:widgets) do
      [{ id: 'agents', type: 'table', table_kind: 'pivot',
         columns: %w[name conversations_count resolved_conversations_count], pivot: { row_attribute: 'agent' } }]
    end

    before do
      create(:custom_attribute_definition, account: account, attribute_key: 'segment', attribute_model: :conversation_attribute)
      conversation = create(:conversation, account: account, inbox: inbox, assignee: assignee, created_at: since_time,
                                           custom_attributes: { segment: 'A' })
      { 'conversation_resolved' => 100, 'first_response' => 20, 'reply_time' => 40 }.each do |name, value|
        create(:reporting_event, account: account, inbox: inbox, conversation: conversation, user: actor,
                                 name: name, value: value, created_at: since_time + 1.hour)
      end
      { 'first_response' => 60, 'reply_time' => 80 }.each do |name, value|
        create(:reporting_event, account: account, inbox: inbox, conversation: conversation, user: nil,
                                 name: name, value: value, created_at: since_time + 1.hour)
      end
      old_assigned = create(:conversation, account: account, inbox: inbox, assignee: assignee, created_at: since_time - 30.days,
                                           custom_attributes: { segment: 'A' })
      2.times do
        create(:reporting_event, account: account, inbox: inbox, conversation: old_assigned, user: nil,
                                 name: 'conversation_resolved', created_at: since_time + 1.hour)
      end
    end

    [false, true].each do |filtered|
      context "with #{filtered ? 'an inbox filter' : 'no filters'}" do
        let(:filters) do
          filtered ? [{ attribute_key: 'inbox_id', filter_operator: 'equal_to', values: [inbox.id], query_operator: nil }] : []
        end

        it 'credits the event actor and counts nil-actor resolutions in the unassigned row' do
          expect(result[:error]).to be_nil
          actor_row = result[:rows].find { |row| row[:id] == actor.id }
          assignee_row = result[:rows].find { |row| row[:id] == assignee.id }
          unassigned_row = result[:rows].find { |row| row[:id] == 0 }
          expect(actor_row[:resolved_conversations_count]).to eq(1)
          expect(assignee_row[:conversations_count]).to eq(1)
          expect(assignee_row[:resolved_conversations_count]).to eq(0)
          expect(unassigned_row[:resolved_conversations_count]).to eq(1)
        end

        context 'with a pivot' do
          let(:widgets) do
            [{ id: 'agents', type: 'table', table_kind: 'pivot', columns: %w[name resolved_conversations_count],
               pivot: { row_attribute: 'agent', column_attribute: 'ca:segment', column_values: ['A'] } }]
          end

          it 'uses event actors for pivot resolutions, including nil actors on assigned conversations' do
            expect(result[:error]).to be_nil
            actor_row = result[:rows].find { |row| row[:id] == actor.id }
            assignee_row = result[:rows].find { |row| row[:id] == assignee.id }
            unassigned_row = result[:rows].find { |row| row[:id] == 0 }
            expect(actor_row['resolved_conversations_count__pv__A']).to eq(1)
            expect(assignee_row['resolved_conversations_count__pv__A']).to eq(0)
            expect(unassigned_row['resolved_conversations_count__pv__A']).to eq(1)
          end
        end
      end
    end
  end

  describe 'dynamic summary tables' do
    let(:measures) { %w[conversations_count ca:amount__sum] }
    let(:pivot) { { row_attribute: 'ca:segment' } }
    let(:widget) { { id: 'dynamic', type: 'table', table_kind: 'pivot', columns: ['name'] + measures, pivot: pivot } }
    let(:widgets) { [widget] }

    # The panel keeps its own copy of the widgets, so run again after mutating `widget`.
    def rerun
      panel.widgets = [widget]
      runner.perform[:widgets].first.with_indifferent_access
    end

    before do
      create(:custom_attribute_definition, account: account, attribute_key: 'segment', attribute_model: :conversation_attribute)
      create(:custom_attribute_definition, account: account, attribute_key: 'amount', attribute_model: :conversation_attribute,
                                           attribute_display_type: :currency)
    end

    it 'calculates uncrossed percentages and keeps the selected measures' do
      pivot[:row_attribute] = 'inbox'
      widget[:column_aggregations] = { 'ca:amount__sum' => 'sum' }
      widget[:measure_display] = { 'ca:amount__sum' => 'column_percent' }
      other_inbox = create(:inbox, account: account)
      [[inbox, 10], [other_inbox, 30]].each do |box, amount|
        create(:conversation, account: account, inbox: box, created_at: since_time, custom_attributes: { amount: amount })
      end
      expect(result[:columns]).to eq(['name'] + measures)
      expect(result[:rows].map { |row| row['ca:amount__sum'] }.sort).to eq([25, 75])
      expect(result[:totals][:columns]['ca:amount__sum']).to eq(100)
    end

    it 'groups all scalar attribute values, false, zero, blank and the first nonempty array value without crossed columns' do
      ['text', 0, false, nil, '', ['', 'array', 'ignored']].each do |value|
        create(:conversation, account: account, inbox: inbox, created_at: since_time, custom_attributes: { segment: value, amount: 2 })
      end
      expect(result[:error]).to be_nil
      expect(result[:columns]).to eq(['name'] + measures)
      expect(result[:rows].map { |row| [row[:name], row[:conversations_count]] }.to_h).to eq(
        'text' => 1, '0' => 1, 'false' => 1, '' => 2, 'array' => 1
      )
      expect(result[:rows].flat_map(&:keys).none? { |key| key.include?('__pv__') }).to be true
    end

    { number: 0, checkbox: false, currency: 10.9, percent: 25, date: '2026-10-05',
      datetime: '2026-10-05T12:30:00Z', link: 'https://example.com', list: 'A' }.each do |type, value|
      it "groups scalar #{type} attributes without dropping zero or false" do
        account.custom_attribute_definitions.find_by!(attribute_key: 'segment').update!(attribute_display_type: type)
        create(:conversation, account: account, inbox: inbox, created_at: since_time, custom_attributes: { segment: value })
        expect(result[:rows].first[:name]).to eq(value.to_s)
        expect(result[:rows].first[:conversations_count]).to eq(1)
      end
    end

    it 'separates homonymous contact and conversation attributes for rows and measure types' do
      create(:custom_attribute_definition, account: account, attribute_key: 'segment', attribute_model: :contact_attribute)
      create(:custom_attribute_definition, account: account, attribute_key: 'amount', attribute_model: :contact_attribute,
                                           attribute_display_type: :number)
      measures << 'contact_ca:amount__sum'
      contact = create(:contact, account: account, custom_attributes: { segment: 'Contact', amount: 7 })
      create(:conversation, account: account, inbox: inbox, contact: contact, created_at: since_time,
                            custom_attributes: { segment: 'Conversation', amount: 10 })
      expect(result[:rows].first[:name]).to eq('Conversation')
      expect(result[:attribute_types]).to include('ca:amount__sum' => 'currency', 'contact_ca:amount__sum' => 'number')
      pivot[:row_attribute] = 'contact_ca:segment'
      contact_result = rerun
      expect(contact_result[:rows].first[:name]).to eq('Contact')
    end

    it 'scans more than one batch and deduplicates both contact measures per row and column (D5)' do
      measures.replace(%w[conversations_count contact_ca:amount__sum contact_ca:score__sum])
      pivot[:column_attribute] = 'ca:segment'
      contact = create(:contact, account: account, custom_attributes: { amount: 100, score: 7 })
      create_list(:conversation, 251, account: account, inbox: inbox, contact: contact, created_at: since_time,
                                      custom_attributes: { segment: 'A' })
      create(:conversation, account: account, inbox: inbox, contact: contact, created_at: since_time, custom_attributes: { segment: 'B' })
      rows = result[:rows].index_by { |row| row[:name] }
      expect(rows['A']['conversations_count__pv__A']).to eq(251)
      %w[A B].each do |value|
        expect(rows[value]["contact_ca:amount__sum__pv__#{value}"]).to eq(100)
        expect(rows[value]["contact_ca:score__sum__pv__#{value}"]).to eq(7)
      end
    end

    it 'sorts decimals numerically, puts nulls last in both directions and breaks ties by stable id' do
      measures.replace(%w[ca:amount__avg])
      widget[:sort] = { column: 'ca:amount__avg', direction: 'desc' }
      [['A', 10.1], ['B', 10.9], ['C', 10.9], ['D', nil]].each do |segment, amount|
        create(:conversation, account: account, inbox: inbox, created_at: since_time, custom_attributes: { segment: segment, amount: amount })
      end
      expect(result[:rows].map { |row| row[:name] }).to eq(%w[B C A D])
      widget[:sort][:direction] = 'asc'
      expect(rerun[:rows].map { |row| row['name'] }).to eq(%w[A B C D])
    end

    [nil, 5, 10, 20].each do |limit|
      it "supports Top #{limit || 'All'} independently of presentation order, retaining global totals" do
        21.times do |index|
          create(:conversation, account: account, inbox: inbox, created_at: since_time,
                                custom_attributes: { segment: format('%02d', index), amount: index + 1 })
        end
        widget[:top_n] = { limit: limit, column: 'ca:amount__sum', include_others: false }
        widget[:sort] = { column: 'name', direction: 'asc' }
        expect(result[:rows].size).to eq(limit || 21)
        expect(result[:rows].first[:name]).to eq(format('%02d', limit ? 21 - limit : 0))
        expect(result[:total_count]).to eq(21)
        expect(result[:totals][:columns]['ca:amount__sum']).to eq(231)
      end
    end

    it 'combines original averages and distinct resolution sets for Others and pins it last' do
      measures.replace(%w[ca:amount__avg resolved_conversations_count])
      widget[:top_n] = { limit: 5, column: 'ca:amount__avg', include_others: true }
      widget[:sort] = { column: 'ca:amount__avg', direction: 'asc' }
      [100, 90, 80, 70, 60, 10, 10, 10, 40].each_with_index do |amount, index|
        segment = index < 5 ? index.to_s : { 10 => 'low' }.fetch(amount, 'last')
        conversation = create(:conversation, account: account, inbox: inbox, created_at: since_time,
                                             custom_attributes: { segment: segment, amount: amount })
        2.times do
          create(:reporting_event, account: account, inbox: inbox, conversation: conversation,
                                   name: 'conversation_resolved', created_at: since_time + 1.hour)
        end
      end
      expect(result[:rows].last).to include('is_others' => true, 'ca:amount__avg' => 17.5, 'resolved_conversations_count' => 4)
      expect(result[:totals][:columns]['resolved_conversations_count']).to eq(9)
      expect(result[:totals][:columns]['ca:amount__avg']).to eq(52.22)
    end

    it 'uses base and expanded measures for Top N and sort when row totals are hidden' do
      pivot.merge!(column_attribute: 'ca:segment', column_values: %w[A B], show_row_totals: false)
      pivot[:row_attribute] = 'created_at'
      7.times do |index|
        create(:conversation, account: account, inbox: inbox, created_at: since_time + index.days,
                              custom_attributes: { segment: index.even? ? 'A' : 'B', amount: index + 1 })
      end
      widget[:top_n] = { limit: 5, column: 'ca:amount__sum', include_others: false }
      widget[:sort] = { column: 'ca:amount__sum__pv__A', direction: 'desc' }
      expect(result[:rows].map { |row| row['ca:amount__sum__pv__A'] }).to eq([7, 5, 3, 0, 0])
      widget[:top_n][:column] = 'ca:amount__sum__pv__B'
      expect(rerun[:rows].sum { |row| row['ca:amount__sum__pv__B'] }).to eq(12)
    end

    it 'calculates 25/75 for each measure and returns null for zero denominators' do
      pivot.merge!(column_attribute: 'ca:segment', column_values: %w[A B Zero], row_attribute: 'inbox')
      widget[:measure_display] = { 'conversations_count' => 'row_percent', 'ca:amount__sum' => 'column_percent' }
      other_inbox = create(:inbox, account: account)
      [['A', inbox, 1], ['B', inbox, 1], ['B', inbox, 1], ['B', inbox, 1], ['A', other_inbox, 3]].each do |segment, box, amount|
        create(:conversation, account: account, inbox: box, created_at: since_time, custom_attributes: { segment: segment, amount: amount })
      end
      row = result[:rows].find { |item| item[:id] == inbox.id }
      expect(row['conversations_count__pv__A']).to eq(25)
      expect(row['conversations_count__pv__B']).to eq(75)
      expect(row['ca:amount__sum__pv__A']).to eq(25)
      expect(row['ca:amount__sum__pv__Zero']).to be_nil
      expect(result[:totals][:columns]['ca:amount__sum__pv__A']).to eq(100)
    end

    it 'uses full-population percentage denominators before Top N and Others' do
      widget[:top_n] = { limit: 5, column: 'ca:amount__sum', include_others: true }
      widget[:measure_display] = { 'ca:amount__sum' => 'column_percent' }
      8.times do |index|
        create(:conversation, account: account, inbox: inbox, created_at: since_time, custom_attributes: { segment: index.to_s, amount: 10 })
      end
      expect(result[:rows].first['ca:amount__sum']).to eq(12.5)
      expect(result[:rows].last['ca:amount__sum']).to eq(37.5)
      expect(result[:totals][:columns]['ca:amount__sum']).to eq(100)
    end

    it 'returns only twelve crossed columns while still scanning all discovered values' do
      pivot[:column_attribute] = 'ca:segment'
      13.times do |index|
        create(:conversation, account: account, inbox: inbox, created_at: since_time, custom_attributes: { segment: index.to_s })
      end
      expect(result[:pivot][:column_values].size).to eq(12)
      expect(result[:totals][:columns]['conversations_count']).to eq(13)
    end

    it 'keeps blank, literal blank markers and escaped column values distinct' do
      pivot.merge!(row_attribute: 'inbox', column_attribute: 'ca:segment', column_values: ['', '__blank__', 'A ~!*()'])
      [nil, '__blank__', 'A ~!*()'].each do |segment|
        create(:conversation, account: account, inbox: inbox, created_at: since_time, custom_attributes: { segment: segment })
      end
      row = result[:rows].first
      expect(row['conversations_count__pv__']).to eq(1)
      expect(row['conversations_count__pv____blank__']).to eq(1)
      expect(row['conversations_count__pv__A%20%7E%21%2A%28%29']).to eq(1)
      expect(result[:totals][:columns]['conversations_count']).to eq(3)
    end

    it 'fails explicitly at row 1001 without partial results' do
      conversations = Array.new(1001) do |index|
        build_stubbed(:conversation, account: account, inbox: inbox, created_at: since_time, custom_attributes: { segment: index.to_s })
      end
      scope = instance_double(ActiveRecord::Relation)
      allow(scope).to receive(:unscope).with(:order).and_return(scope)
      allow(scope).to receive(:includes).with(:contact).and_return(scope)
      allow(scope).to receive(:find_each).with(batch_size: 250) { |&block| conversations.each(&block) }
      allow(runner).to receive(:filtered_conversations_scope).and_return(scope)
      expect(result[:error]).to start_with('pivot_row_limit_exceeded')
      expect(result[:rows]).to eq([])
    end

    it 'limits internal buckets even when automatic columns return only twelve values' do
      stub_const('Reports::PanelPivotBuckets::MAX_BUCKETS', 12)
      pivot[:row_attribute] = 'inbox'
      pivot[:column_attribute] = 'ca:segment'
      13.times do |index|
        create(:conversation, account: account, inbox: inbox, created_at: since_time, custom_attributes: { segment: index.to_s })
      end
      expect(result[:error]).to start_with('pivot_bucket_limit_exceeded')
      expect(result[:rows]).to eq([])
    end

    context 'with creation-date rows' do
      let(:pivot) { { row_attribute: 'created_at' } }

      [-5, 5.5].each do |offset|
        it "groups both inclusive range boundaries with fixed offset #{offset}" do
          [since_time, until_time].each { |time| create(:conversation, account: account, inbox: inbox, created_at: time) }
          service = described_class.new(panel: panel, account: account, user: admin, timezone_offset: offset,
                                        date_overrides: { since: since_time.to_i, until: until_time.to_i })
          rows = service.perform[:widgets].first[:rows]
          expected = [since_time, until_time].map { |time| time.getlocal((offset * 3600).to_i).to_date.iso8601 }
          expect(rows.map { |row| row['name'] }).to eq(expected)
        end
      end

      it 'starts weeks on Monday and keeps Sunday in the previous week' do
        pivot[:row_granularity] = 'week'
        [since_time - 1.day, since_time, until_time].each do |time|
          create(:conversation, account: account, inbox: inbox, created_at: time)
        end
        service = described_class.new(panel: panel, account: account, user: admin,
                                      date_overrides: { since: (since_time - 1.day).to_i, until: until_time.to_i })
        expect(service.perform[:widgets].first[:rows].map { |row| [row['name'], row['conversations_count']] }).to eq(
          [['2026-09-28', 1], ['2026-10-05', 2]]
        )
      end

      it 'groups month/year transitions chronologically' do
        pivot[:row_granularity] = 'month'
        create(:conversation, account: account, inbox: inbox, created_at: Time.utc(2025, 12, 31, 23, 59))
        create(:conversation, account: account, inbox: inbox, created_at: Time.utc(2026, 1, 1))
        service = described_class.new(panel: panel, account: account, user: admin,
                                      date_overrides: { since: Time.utc(2025, 12, 31).to_i, until: Time.utc(2026, 1, 2).to_i })
        expect(service.perform[:widgets].first[:rows].map { |row| row['name'] }).to eq(%w[2025-12-01 2026-01-01])
      end

      it 'uses the filtered conversation population for resolutions while grouping by creation date' do
        create(:custom_attribute_definition, account: account, attribute_key: 'business_date', attribute_model: :conversation_attribute,
                                             attribute_display_type: :date)
        measures << 'resolved_conversations_count'
        panel.date_attribute = 'ca:business_date'
        [since_time - 30.days, since_time - 60.days].each_with_index do |created_at, index|
          conversation = create(:conversation, account: account, inbox: inbox, created_at: created_at,
                                               custom_attributes: { business_date: index.zero? ? '2026-10-05' : '2026-09-01' })
          create(:reporting_event, account: account, inbox: inbox, conversation: conversation,
                                   name: 'conversation_resolved', created_at: since_time + 1.hour)
        end
        expect(result[:rows].map { |row| row[:name] }).to eq(['2026-09-05'])
        expect(result[:totals][:columns]['resolved_conversations_count']).to eq(1)
      end

      it 'excludes older resolved conversations when the panel filters by creation' do
        measures << 'resolved_conversations_count'
        [since_time - 1.day, since_time].each do |time|
          conversation = create(:conversation, account: account, inbox: inbox, created_at: time)
          create(:reporting_event, account: account, inbox: inbox, conversation: conversation,
                                   name: 'conversation_resolved', created_at: since_time + 1.hour)
        end
        expect(result[:totals][:columns]['resolved_conversations_count']).to eq(1)
      end
    end
  end
end
# rubocop:enable RSpec/MultipleExpectations, RSpec/MultipleMemoizedHelpers, Performance/CollectionLiteralInLoop
