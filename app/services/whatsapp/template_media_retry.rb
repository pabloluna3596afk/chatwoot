# Meta refused the media_id of a template header (expired or invalid): upload the stored copy again and resend once, then
# send the link of that copy. Anything else is returned as it came. See Whatsapp::TemplateHeaderMedia.
class Whatsapp::TemplateMediaRetry
  pattr_initialize [:channel!, :request_body!, :response!]

  # Yields the request body to send again; returns the response to use.
  def perform(&)
    return response if parameter.nil? || !refused?(response)

    retried = resend_with_new_id(&)
    return retried if retried && (retried.success? || !refused?(retried))

    resend_with_link(&) || response
  end

  private

  def parameter
    @parameter ||= Whatsapp::TemplateHeaderMedia.header_media_parameter(request_body.dig(:template, :components))
  end

  def refused_id
    parameter.dig(parameter[:type].to_sym, :id)
  end

  def refused?(reply)
    !reply.success? && Whatsapp::TemplateHeaderMedia.media_error?(reply.parsed_response)
  end

  def resend_with_new_id
    new_id = Whatsapp::TemplateHeaderMedia.reupload(channel, refused_id)
    yield body_with(id: new_id) if new_id.present?
  end

  def resend_with_link
    link = Whatsapp::TemplateHeaderMedia.link_for(channel, refused_id)
    yield body_with(link: link) if link.present?
  end

  def body_with(id: nil, link: nil)
    type = parameter[:type].to_sym
    swapped = parameter.merge(type => parameter[type].except(:id).merge(id.present? ? { id: id } : { link: link }))
    request_body.deep_dup.tap do |body|
      header = body[:template][:components].find { |component| component[:type].to_s == 'header' }
      header[:parameters] = header[:parameters].map { |item| item == parameter ? swapped : item }
    end
  end
end
