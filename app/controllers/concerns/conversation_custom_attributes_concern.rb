module ConversationCustomAttributesConcern
  def custom_attributes
    @conversation.custom_attributes = Variables::Writer.new(account: @conversation.account).patch(
      scope: 'conversation', current: @conversation.custom_attributes, values: params[:custom_attributes],
      replace: !ActiveModel::Type::Boolean.new.cast(params[:merge])
    )
    @conversation.save!
  end

  def destroy_custom_attributes
    @conversation.custom_attributes = Variables::Writer.new(account: @conversation.account).remove(
      scope: 'conversation', current: @conversation.custom_attributes, keys: params[:custom_attributes]
    )
    @conversation.save!
  end
end
