module Enterprise::Variables::ContextFactory
  def build(surface:)
    values = super
    return values unless surface == 'captain'

    values['assistant'] = { 'name' => @records[:assistant].name } if @records[:assistant]
    values['appointment'] = @records[:appointment].to_h.stringify_keys if @records[:appointment]
    values
  end
end
