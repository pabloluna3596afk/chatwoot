class AddTemplateVariableBindingsToChannelWhatsapp < ActiveRecord::Migration[7.2]
  def change
    # What each variable of a template is filled with ({ 'template_name' => { 'pedido' => 'contact.custom_attribute.pedido' } }).
    # Meta replaces `message_templates` on every sync, so what ChatHub knows about the variables lives apart.
    add_column :channel_whatsapp, :template_variable_bindings, :jsonb, default: {}, null: false
  end
end
