class CreatePayphonePayments < ActiveRecord::Migration[7.2]
  # Keep the ledger columns together so the immutable snapshot can be reviewed at once.
  # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
  def change
    create_table :payphone_payments do |t|
      t.references :account, null: false, foreign_key: { on_delete: :restrict }
      t.references :user, null: false, foreign_key: { on_delete: :restrict }
      t.references :plan, null: false, foreign_key: { on_delete: :restrict }
      t.string :client_transaction_id, null: false
      t.integer :amount, null: false
      t.integer :amount_without_tax, null: false, default: 0
      t.integer :amount_with_tax, null: false, default: 0
      t.integer :tax, null: false, default: 0
      t.integer :base_cents, null: false
      t.integer :tax_cents, null: false, default: 0
      t.integer :commission_cents, null: false, default: 0
      t.string :currency, limit: 3, null: false, default: 'USD'
      t.string :status, null: false, default: 'pending'
      t.string :payphone_transaction_id
      t.string :authorization_code
      t.jsonb :raw_response, null: false, default: {}
      t.jsonb :status_history, null: false, default: []
      t.boolean :needs_invoice, null: false, default: false
      t.string :billing_tax_id_type
      t.string :billing_tax_id
      t.string :billing_name
      t.string :billing_email
      t.string :billing_phone
      t.string :billing_address
      t.text :card_token
      t.datetime :paid_at
      t.datetime :period_start
      t.datetime :period_end
      t.datetime :confirmed_at
      t.timestamps
    end

    add_index :payphone_payments, :client_transaction_id, unique: true
    add_index :payphone_payments, :payphone_transaction_id, unique: true, where: 'payphone_transaction_id IS NOT NULL'
    add_index :payphone_payments, %i[account_id status]
    add_index :payphone_payments, %i[status created_at]
    add_check_constraint :payphone_payments, 'status IN (\'pending\', \'approved\', \'cancelled\', \'failed\', \'expired\')',
                         name: 'payphone_payments_status_check'
    add_check_constraint :payphone_payments, 'amount = amount_without_tax + amount_with_tax + tax + commission_cents',
                         name: 'payphone_payments_amount_breakdown_check'
    add_check_constraint :payphone_payments, "currency = 'USD'", name: 'payphone_payments_currency_check'
  end
  # rubocop:enable Metrics/AbcSize, Metrics/MethodLength
end
